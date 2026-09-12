#!/usr/bin/env bash
#
# install.sh — install `aws console-url` as an AWS CLI subcommand.
#
# What it does:
#   1. Copies bin/console-url.sh to ~/.aws/cli/console-url.sh (override with --dir).
#   2. Registers the `console-url` alias in ~/.aws/cli/alias, preserving any
#      existing [toplevel] aliases.
#
# It is idempotent: re-running updates the script and refreshes the alias line.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.aws/cli"
SCRIPT_SRC="${REPO_DIR}/bin/console-url.sh"
SCRIPT_DST="${INSTALL_DIR}/console-url.sh"
ALIAS_FILE="${INSTALL_DIR}/alias"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) INSTALL_DIR="${2:?--dir needs a value}"; SCRIPT_DST="${INSTALL_DIR}/console-url.sh"; ALIAS_FILE="${INSTALL_DIR}/alias"; shift 2 ;;
    -h|--help) echo "usage: ./install.sh [--dir <aws-cli-dir>]"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

echo "Installing to ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"

# 1) Copy the script.
cp "$SCRIPT_SRC" "$SCRIPT_DST"
chmod +x "$SCRIPT_DST"
echo "  • installed ${SCRIPT_DST}"

# 2) Register the alias line, preserving existing [toplevel] content.
ALIAS_LINE="console-url = !bash \"${SCRIPT_DST}\""

if [[ ! -f "$ALIAS_FILE" ]]; then
  printf '[toplevel]\n\n%s\n' "$ALIAS_LINE" > "$ALIAS_FILE"
  echo "  • created ${ALIAS_FILE}"
else
  # Remove any existing console-url line, then ensure [toplevel] + our line exist.
  tmp="$(mktemp)"
  grep -vE '^[[:space:]]*console-url[[:space:]]*=' "$ALIAS_FILE" > "$tmp" || true
  if ! grep -qE '^\[toplevel\]' "$tmp"; then
    printf '[toplevel]\n\n' | cat - "$tmp" > "${tmp}.2" && mv "${tmp}.2" "$tmp"
  fi
  printf '%s\n' "$ALIAS_LINE" >> "$tmp"
  mv "$tmp" "$ALIAS_FILE"
  echo "  • updated ${ALIAS_FILE} (preserved existing aliases)"
fi

echo
echo "Done. Try:"
echo "  aws console-url <profile> --print"
echo "  aws console-url <profile>"
