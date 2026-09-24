#!/usr/bin/env bash
#
# aws console-url — open (or print) an AWS Management Console sign-in URL for a profile.
#
# Credential handling is fully delegated to the AWS CLI: this script never reads
# ~/.aws/sso/cache and never calls SSO/STS itself for tokens. It asks the CLI for
# already-resolved temporary credentials via `aws configure export-credentials`,
# then performs the standard AWS federation getSigninToken flow.
#
# Usage:
#   console-url.sh <profile> [service] [--print] [--browser <app>] [--no-multi]
#                            [--service <name>] [--region <r>] [--destination <url>]
#                            [--duration <sec>]
#
# Options:
#   [service]       Optional 2nd positional: open a service deep-link instead of the
#                   console home, e.g. `console-url myprofile ec2`. Same as --service.
#   --service       Service to deep-link into (e.g. ec2, lambda, s3, rds, dynamodb).
#                   Most services resolve to /<service>/home; a few special cases are
#                   mapped (s3, iam, stepfunctions). Use --destination for anything else.
#   --print         Print the URL instead of opening a browser.
#   --browser       Browser app to open the URL in. On macOS this is an app name
#                   (e.g. "Google Chrome", "Safari", "Firefox"); on Linux it is a
#                   command on PATH (e.g. "firefox", "google-chrome"). Overrides the
#                   AWS_CONSOLE_BROWSER env var. Defaults to the system default.
#   --no-multi      Disable multi-session (account-scoped) routing. By default the
#                   destination is scoped to the profile's account id so you can be
#                   signed into multiple accounts at once (up to AWS's limit of 5).
#   --region        Console home region (default: profile/region or us-east-1).
#   --destination   Destination URL after sign-in (overrides region/service/multi).
#   --duration      Federation session duration in seconds. Only honored for IAM
#                   long-term-key profiles; ignored for SSO/assume-role sessions.
#
# Requirements: aws (CLI v2), curl, python3.
#
set -euo pipefail

PROFILE="${1:-}"
if [[ -z "$PROFILE" || "$PROFILE" == "--help" || "$PROFILE" == "-h" ]]; then
  echo "usage: console-url <profile> [service] [--print] [--browser <app>] [--no-multi] [--service <name>] [--region <r>] [--destination <url>] [--duration <sec>]" >&2
  exit 2
fi
shift || true

PRINT_ONLY=0
REGION=""
DESTINATION=""
DURATION=3600
BROWSER="${AWS_CONSOLE_BROWSER:-}"
MULTI=1
SERVICE=""

# Optional 2nd positional argument = service (if it doesn't look like an option).
if [[ -n "${1:-}" && "$1" != -* ]]; then SERVICE="$1"; shift; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --print) PRINT_ONLY=1; shift ;;
    --browser) BROWSER="${2:?--browser needs a value}"; shift 2 ;;
    --no-multi) MULTI=0; shift ;;
    --multi) MULTI=1; shift ;;
    --service) SERVICE="${2:?--service needs a value}"; shift 2 ;;
    --region) REGION="${2:?--region needs a value}"; shift 2 ;;
    --destination) DESTINATION="${2:?--destination needs a value}"; shift 2 ;;
    --duration) DURATION="${2:?--duration needs a value}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# --- Dependency checks -------------------------------------------------------
for dep in aws curl python3; do
  command -v "$dep" >/dev/null 2>&1 || { echo "error: required dependency '$dep' not found on PATH." >&2; exit 1; }
done

# Resolve region: explicit flag > profile config > us-east-1
if [[ -z "$REGION" ]]; then
  REGION="$(aws configure get region --profile "$PROFILE" 2>/dev/null || true)"
fi
[[ -z "$REGION" ]] && REGION="us-east-1"

# Build the destination. For multi-session, scope it to the profile's account id
# (&account=<id>) so multiple accounts get separate console sessions/tabs.
# Account id, resolved once via the AWS CLI (no direct credential handling here).
# Used for multi-session scoping and shown in the final message.
ACCOUNT_ID="$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null || true)"
[[ "$ACCOUNT_ID" == "None" ]] && ACCOUNT_ID=""

if [[ -z "$DESTINATION" ]]; then
  # Resolve the console path for the requested service (if any).
  #  - most services live at /<service>/home?region=<r>
  #  - a few use a different console slug or are global (region-less)
  GLOBAL=0
  if [[ -n "$SERVICE" ]]; then
    case "$SERVICE" in
      s3)             SVC_PATH="s3"; GLOBAL=1 ;;              # S3 console is global
      iam)            SVC_PATH="iam"; GLOBAL=1 ;;             # IAM is global
      route53|r53)    SVC_PATH="route53/v2"; GLOBAL=1 ;;      # Route 53 is global
      billing|cost)   SVC_PATH="billing"; GLOBAL=1 ;;
      stepfunctions|sfn) SVC_PATH="states" ;;                # Step Functions -> states
      *)              SVC_PATH="$SERVICE" ;;                  # generic: /<service>/home
    esac
    if [[ "$GLOBAL" -eq 1 ]]; then
      BASE="https://console.aws.amazon.com/${SVC_PATH}/home"
    else
      BASE="https://${REGION}.console.aws.amazon.com/${SVC_PATH}/home?region=${REGION}"
    fi
  else
    BASE="https://${REGION}.console.aws.amazon.com/console/home?region=${REGION}"
  fi

  if [[ "$MULTI" -eq 1 ]]; then
    if [[ -n "$ACCOUNT_ID" ]]; then
      # Append account with the right separator depending on existing query string.
      if [[ "$BASE" == *\?* ]]; then DESTINATION="${BASE}&account=${ACCOUNT_ID}"
      else DESTINATION="${BASE}?account=${ACCOUNT_ID}"; fi
    else
      echo "warning: could not resolve account id; opening without multi-session scoping." >&2
      DESTINATION="$BASE"
    fi
  else
    DESTINATION="$BASE"
  fi
fi

# --- Credentials: delegated entirely to the AWS CLI --------------------------
if ! CREDS_JSON="$(aws configure export-credentials --profile "$PROFILE" --format process 2>/dev/null)"; then
  echo "Not signed in for profile '$PROFILE' (or the session has expired)." >&2
  echo "Run:  aws sso login --profile $PROFILE" >&2
  exit 1
fi

read -r AK SK ST <<<"$(printf '%s' "$CREDS_JSON" | python3 -c '
import sys, json
d = json.load(sys.stdin)
print(d["AccessKeyId"], d["SecretAccessKey"], d.get("SessionToken", ""))
')"

if [[ -z "$ST" ]]; then
  echo "error: federation requires temporary credentials (a SessionToken); profile \"$PROFILE\" returned long-term keys." >&2
  echo "       Use an SSO/assume-role profile." >&2
  exit 1
fi

# Build the {"sessionId","sessionKey","sessionToken"} JSON the federation endpoint expects.
SESSION_JSON="$(python3 -c '
import json, sys
ak, sk, st = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({"sessionId": ak, "sessionKey": sk, "sessionToken": st}))
' "$AK" "$SK" "$ST")"

FED="https://signin.aws.amazon.com/federation"

# URL-encode a string using python3 (no network) for safe query construction.
urlencode() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

# Step 1: exchange session for a SigninToken. Use curl (system CA trust store).
# NOTE: SessionDuration is ONLY valid when federating with an IAM user's long-term
# keys. For temporary credentials (SSO / assume-role, which always carry a
# SessionToken) it must be omitted, or the endpoint rejects the request.
GETTOKEN_URL="${FED}?Action=getSigninToken&Session=$(urlencode "$SESSION_JSON")"
TOKEN_RESPONSE="$(curl -fsS "$GETTOKEN_URL")"
SIGNIN_TOKEN="$(printf '%s' "$TOKEN_RESPONSE" | python3 -c 'import sys, json; print(json.load(sys.stdin)["SigninToken"])')"

# Step 2: build the login URL.
LOGIN_URL="${FED}?Action=login&Issuer=$(urlencode "console-url")&Destination=$(urlencode "$DESTINATION")&SigninToken=$(urlencode "$SIGNIN_TOKEN")"

# --- Output / open -----------------------------------------------------------
open_url() {
  local url="$1"
  if [[ -n "$BROWSER" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      open -a "$BROWSER" "$url"
    else
      "$BROWSER" "$url" >/dev/null 2>&1 &
    fi
  else
    if [[ "$(uname)" == "Darwin" ]]; then
      open "$url"
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$url" >/dev/null 2>&1 &
    elif command -v wslview >/dev/null 2>&1; then
      # WSL (wslu package): opens in the Windows default browser.
      wslview "$url" >/dev/null 2>&1 &
    elif command -v cmd.exe >/dev/null 2>&1; then
      # WSL / Git Bash: hand the URL to Windows' shell.
      cmd.exe /c start "" "$url" >/dev/null 2>&1 &
    else
      echo "error: no way to open a browser; use --print and open the URL yourself." >&2
      return 1
    fi
  fi
}

if [[ "$PRINT_ONLY" -eq 1 ]]; then
  printf '%s\n' "$LOGIN_URL"
else
  open_url "$LOGIN_URL"
  WHAT="AWS Console"
  [[ -n "$SERVICE" ]] && WHAT="AWS $SERVICE console"
  ACCT=""
  [[ -n "$ACCOUNT_ID" ]] && ACCT=" account $ACCOUNT_ID"
  if [[ -n "$BROWSER" ]]; then
    echo "Opened $WHAT for profile '$PROFILE'$ACCT (region $REGION) in $BROWSER." >&2
  else
    echo "Opened $WHAT for profile '$PROFILE'$ACCT (region $REGION)." >&2
  fi
fi
