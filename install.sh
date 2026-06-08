#!/usr/bin/env bash
set -euo pipefail

REPO="hututuo/codex-token-bar"
APP_NAME="Codex Token Bar.app"
ASSET_NAME="CodexTokenBar.app.zip"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Codex Token Bar is a macOS app. This installer only supports macOS." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading Codex Token Bar..."
curl -fL --progress-bar "$DOWNLOAD_URL" -o "$TMP_DIR/$ASSET_NAME"

echo "Unpacking..."
ditto -x -k "$TMP_DIR/$ASSET_NAME" "$TMP_DIR"

APP_PATH="$TMP_DIR/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Install failed: $APP_NAME was not found in the downloaded archive." >&2
  exit 1
fi

if [[ -n "${CODEX_TOKEN_BAR_INSTALL_DIR:-}" ]]; then
  INSTALL_DIR="$CODEX_TOKEN_BAR_INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
elif [[ -n "${CODEX_TOKEN_DASHBOARD_INSTALL_DIR:-}" ]]; then
  INSTALL_DIR="$CODEX_TOKEN_DASHBOARD_INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
elif [[ -d "/Applications" && -w "/Applications" ]]; then
  INSTALL_DIR="/Applications"
else
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi

TARGET="$INSTALL_DIR/$APP_NAME"

echo "Installing to $TARGET..."
rm -rf "$TARGET"
ditto "$APP_PATH" "$TARGET"

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
fi

echo
echo "Installed: $TARGET"
NO_OPEN="${CODEX_TOKEN_BAR_NO_OPEN:-${CODEX_TOKEN_DASHBOARD_NO_OPEN:-0}}"
if [[ "$NO_OPEN" != "1" ]]; then
  echo "Opening Codex Token Bar..."
  open "$TARGET"
fi
echo
echo "Note: this installer removes the common browser-download quarantine flag."
echo "It is still an unsigned app, so strict MDM, security tools, or macOS policy can still block it."
