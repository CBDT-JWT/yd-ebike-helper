#!/bin/zsh
set -euo pipefail

PROJECT_ROOT=${0:A:h:h}
APP_NAME="YD E-Bike Helper"
EXECUTABLE_NAME="yd-ebike-helper"
OLD_APP_BUNDLE="$PROJECT_ROOT/dist/$APP_NAME.app"
ZIP_PATH="$PROJECT_ROOT/dist/yd-ebike-helper-macOS.zip"
ICON_SOURCE="$PROJECT_ROOT/Assets/AppIcon.png"
ICONSET="$PROJECT_ROOT/.build/AppIcon.iconset"
STAGING_ROOT=$(mktemp -d /tmp/yd-ebike-helper.XXXXXX)
STAGING_APP="$STAGING_ROOT/$APP_NAME.app"
STAGING_ZIP="$STAGING_ROOT/yd-ebike-helper-macOS.zip"
CONTENTS="$STAGING_APP/Contents"

trap 'rm -rf "$STAGING_ROOT"' EXIT

cd "$PROJECT_ROOT"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
ditto "$BIN_DIR/$EXECUTABLE_NAME" "$CONTENTS/MacOS/$EXECUTABLE_NAME"
ditto "$PROJECT_ROOT/Support/Info.plist" "$CONTENTS/Info.plist"

if [[ -f "$ICON_SOURCE" ]]; then
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
fi

rm -rf "$OLD_APP_BUNDLE"
rm -f "$ZIP_PATH"
xattr -cr "$STAGING_APP"
codesign --force --deep --sign - "$STAGING_APP"
codesign --verify --deep --strict "$STAGING_APP"
ditto -c -k --keepParent "$STAGING_APP" "$STAGING_ZIP"
ditto --norsrc --noextattr "$STAGING_ZIP" "$ZIP_PATH"

echo "$ZIP_PATH"
