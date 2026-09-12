# aws-console-url — optional zsh/bash helpers: al / ap / ac
#
# Source this from your ~/.zshrc (or ~/.bashrc):
#
#     source /path/to/aws-console-url/shell/aws-helpers.sh
#     export AWS_DEFAULT_SSO_PROFILE="my-sso-profile"   # optional; used by `al`
#
# The trio:
#   al  — AWS login: ensure you have a valid SSO session (or export temp creds)
#   ap  — AWS profile: set the ambient AWS_PROFILE for subsequent commands
#   ac  — AWS console: open the console for a profile (uses `aws console`)
#
# `ac` requires the `aws console` subcommand from this repo (run ./install.sh).

# --- al: log in via SSO (idempotent) ----------------------------------------
# Usage:
#   al                 check current session; log in via SSO if needed
#   al -f              force an SSO login
#   al -tmp <profile>  export that profile's temporary creds into the current shell
#
# Set AWS_DEFAULT_SSO_PROFILE to the profile whose sso-session should be used.
al() {
  local sso_profile="${AWS_DEFAULT_SSO_PROFILE:-default}"
  if [[ "$1" == "-f" ]]; then
    aws sso login --profile "$sso_profile"
  elif [[ "$1" == "-tmp" ]]; then
    [[ -z "$2" ]] && { echo "Usage: al -tmp <profile>"; return 1; }
    eval "$(aws configure export-credentials --profile "$2" --format env)"
  elif aws sts get-caller-identity >/dev/null 2>&1; then
    echo "✅ Already logged in: $(aws sts get-caller-identity --query Arn --output text)"
  elif aws sts get-caller-identity --profile "$sso_profile" >/dev/null 2>&1; then
    echo "✅ Already logged in ($sso_profile profile)"
  else
    aws sso login --profile "$sso_profile"
  fi
}

# --- ap: set the ambient profile --------------------------------------------
# Usage: ap <profile>
ap() { export AWS_PROFILE="$1"; }

# --- ac: open the AWS console -----------------------------------------------
# Usage:
#   ac <profile> [options...]   open the console for <profile>
#   ap <profile>; ac            with no profile arg, falls back to $AWS_PROFILE
#   ac [options...]             (after `ap`) options pass through to `aws console`
#
# Requires the `aws console` alias from this repo.
ac() {
  local profile
  if [[ -n "$1" && "$1" != -* ]]; then profile=$1; shift
  else profile="${AWS_PROFILE:-}"; fi
  [[ -z "$profile" ]] && { echo "Usage: ac <profile> [options...]  (or run 'ap <profile>' first, then 'ac')"; return 1; }
  aws console "$profile" "$@"
}
