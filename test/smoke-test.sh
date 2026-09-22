#!/usr/bin/env bash
#
# smoke-test.sh — validate the script without opening a browser.
#
# Usage: ./test/smoke-test.sh <profile>
#
# Checks:
#   1. bash syntax is valid
#   2. --print produces a well-formed federation login URL with a SigninToken
#   3. multi-session URL carries an &account=<id> in the Destination
#   4. --no-multi URL does NOT carry account scoping
#   5. (optional) the login URL yields an HTTP 302 to the console
#
set -euo pipefail

PROFILE="${1:?usage: ./test/smoke-test.sh <profile>}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${DIR}/bin/console-url.sh"

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

echo "1) syntax"
bash -n "$SCRIPT" && pass "bash -n" || fail "syntax error"

echo "2) --print login URL shape"
url="$(bash "$SCRIPT" "$PROFILE" --print)"
[[ "$url" == https://signin.aws.amazon.com/federation?Action=login* ]] || fail "unexpected URL prefix"
[[ "$url" == *SigninToken=* ]] || fail "missing SigninToken"
pass "login URL with SigninToken"

echo "3) multi-session scoping"
echo "$url" | grep -q 'account%3D' && pass "Destination carries account=" || fail "no account scoping in default (multi) mode"

echo "4) --no-multi has no scoping"
nurl="$(bash "$SCRIPT" "$PROFILE" --no-multi --print)"
echo "$nurl" | grep -q 'account%3D' && fail "--no-multi should not scope account" || pass "--no-multi unscoped"

echo "5) federation 302 (optional; requires network)"
if command -v curl >/dev/null 2>&1; then
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$url" || echo "000")"
  [[ "$code" == "302" ]] && pass "HTTP 302 from federation endpoint" || echo "  SKIP/NOTE: got HTTP $code (creds may be expired)"
fi

echo "6) service deep-link (positional + --service)"
surl="$(bash "$SCRIPT" "$PROFILE" ec2 --print)"
echo "$surl" | grep -q 'ec2%2Fhome' && pass "positional service -> /ec2/home" || fail "service deep-link not applied (positional)"
surl2="$(bash "$SCRIPT" "$PROFILE" --service lambda --print)"
echo "$surl2" | grep -q 'lambda%2Fhome' && pass "--service lambda -> /lambda/home" || fail "service deep-link not applied (--service)"

echo "All checks completed."
