#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FlowWatch.xcodeproj"
SCHEME="FlowWatch"
CONFIGURATION="Release"

DIST_DIR="$ROOT_DIR/dist"
DERIVED_DATA_PATH="$DIST_DIR/DerivedData"
EXTRA_BUILD_SETTINGS=()

if [[ -n "${MARKETING_VERSION:-}" ]]; then
  EXTRA_BUILD_SETTINGS+=("MARKETING_VERSION=$MARKETING_VERSION")
fi

if [[ -n "${CURRENT_PROJECT_VERSION:-}" ]]; then
  EXTRA_BUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION")
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "未找到 xcodebuild。请安装 Xcode（建议 Xcode 15+）后重试。"
  exit 1
fi

DEVELOPER_DIR_PATH="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEVELOPER_DIR_PATH" == *"CommandLineTools"* ]]; then
  if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    echo "检测到已安装 Xcode，临时切换 DEVELOPER_DIR=$DEVELOPER_DIR"
  else
    echo "当前开发者目录指向 CommandLineTools：$DEVELOPER_DIR_PATH"
    echo "未检测到 /Applications/Xcode.app。请确认 Xcode 安装位置，或执行："
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
  fi
fi

mkdir -p "$DIST_DIR"
rm -rf "$DERIVED_DATA_PATH" "$DIST_DIR/FlowWatch.app" "$DIST_DIR/FlowWatch.zip" "$DIST_DIR/FlowWatch.dmg" "$DIST_DIR/dmgroot"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  "${EXTRA_BUILD_SETTINGS[@]}" \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/FlowWatch.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "未找到构建产物：$APP_PATH"
  exit 1
fi

cp -R "$APP_PATH" "$DIST_DIR/FlowWatch.app"

ADHOC_SIGN="${ADHOC_SIGN:-1}"
if [[ "$ADHOC_SIGN" == "1" ]]; then
  /usr/bin/codesign --force --deep --sign - "$DIST_DIR/FlowWatch.app"
  /usr/bin/codesign --verify --deep --strict "$DIST_DIR/FlowWatch.app"
fi

ditto -c -k --sequesterRsrc --keepParent "$DIST_DIR/FlowWatch.app" "$DIST_DIR/FlowWatch.zip"

DMG_ROOT="$DIST_DIR/dmgroot"
mkdir -p "$DMG_ROOT"
cp -R "$DIST_DIR/FlowWatch.app" "$DMG_ROOT/FlowWatch.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "FlowWatch" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DIST_DIR/FlowWatch.dmg"

echo "未签名分发产物已生成："
echo "- $DIST_DIR/FlowWatch.dmg"
echo "- $DIST_DIR/FlowWatch.zip"
