#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Codex Token Bar"
PRODUCT_NAME="CodexTokenBar"
REPO="hututuo/codex-token-bar"
VERSION="${1:-${APP_VERSION:-0.3.0}}"
VERSION="${VERSION#v}"
BUILD="${APP_BUILD:-}"
ARCH_LABEL="${ARCH_LABEL:-arm64}"
PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-$HOME/.config/codex-token-bar/sparkle-ed25519-private.key}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-$ROOT_DIR/release-notes/v$VERSION.md}"

if [[ -z "$BUILD" ]]; then
  BUILD="$(python3 - "$VERSION" <<'PY'
import sys
parts = [int(p) for p in sys.argv[1].split(".")]
while len(parts) < 3:
    parts.append(0)
print(parts[0] * 10000 + parts[1] * 100 + parts[2])
PY
)"
fi

if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
  echo "Missing Sparkle private key file: $PRIVATE_KEY_FILE" >&2
  echo "Create it before releasing, or set SPARKLE_PRIVATE_KEY_FILE." >&2
  exit 1
fi

if [[ ! -f "$RELEASE_NOTES_FILE" ]]; then
  echo "Missing release notes: $RELEASE_NOTES_FILE" >&2
  exit 1
fi

cd "$ROOT_DIR"

APP_VERSION="$VERSION" APP_BUILD="$BUILD" CODEX_TOKEN_BAR_NO_OPEN=1 \
  "$ROOT_DIR/scripts/package_app.sh" release >/dev/null

APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
RELEASE_DIR="$ROOT_DIR/dist/release/v$VERSION"
APPCAST_SOURCE_DIR="$RELEASE_DIR/appcast-source"
VERSIONED_ZIP="CodexTokenBar-v$VERSION-macos-$ARCH_LABEL.app.zip"
LEGACY_ZIP="CodexTokenBar.app.zip"
DMG_NAME="CodexTokenBar-v$VERSION-macos-$ARCH_LABEL.dmg"
CHECKSUM_FILE="SHA256SUMS-v$VERSION.txt"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR" "$APPCAST_SOURCE_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$RELEASE_DIR/$VERSIONED_ZIP"
cp "$RELEASE_DIR/$VERSIONED_ZIP" "$RELEASE_DIR/$LEGACY_ZIP"

DMG_STAGING="$(mktemp -d "$RELEASE_DIR/dmg-staging.XXXXXX")"
cleanup() {
  rm -rf "$DMG_STAGING"
}
trap cleanup EXIT

ditto "$APP_DIR" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov "$RELEASE_DIR/$DMG_NAME" >/dev/null

hdiutil verify "$RELEASE_DIR/$DMG_NAME" >/dev/null

cp "$RELEASE_DIR/$VERSIONED_ZIP" "$APPCAST_SOURCE_DIR/$VERSIONED_ZIP"
cp "$RELEASE_NOTES_FILE" "$APPCAST_SOURCE_DIR/${VERSIONED_ZIP%.zip}.md"

"$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" \
  --ed-key-file "$PRIVATE_KEY_FILE" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --embed-release-notes \
  --maximum-versions 5 \
  -o "$ROOT_DIR/appcast.xml" \
  "$APPCAST_SOURCE_DIR" >/dev/null

cp "$ROOT_DIR/appcast.xml" "$RELEASE_DIR/appcast.xml"

UPDATE_SIGNATURE="$(python3 - "$ROOT_DIR/appcast.xml" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r'sparkle:edSignature="([^"]+)"', text)
if not match:
    raise SystemExit("missing sparkle:edSignature in appcast")
print(match.group(1))
PY
)"
"$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update" \
  --verify \
  --ed-key-file "$PRIVATE_KEY_FILE" \
  "$RELEASE_DIR/$VERSIONED_ZIP" \
  "$UPDATE_SIGNATURE"

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$DMG_NAME" "$VERSIONED_ZIP" "$LEGACY_ZIP" appcast.xml > "$CHECKSUM_FILE"
)

codesign --verify --deep --strict --verbose=2 "$APP_DIR" >/dev/null
spctl --assess --type execute -vv "$APP_DIR" >/dev/null 2>&1 || true

cat <<REPORT
Release build complete.
Version: $VERSION
Build: $BUILD
App: $APP_DIR
DMG: $RELEASE_DIR/$DMG_NAME
Zip: $RELEASE_DIR/$VERSIONED_ZIP
Compat zip: $RELEASE_DIR/$LEGACY_ZIP
Checksums: $RELEASE_DIR/$CHECKSUM_FILE
Appcast: $ROOT_DIR/appcast.xml
REPORT
