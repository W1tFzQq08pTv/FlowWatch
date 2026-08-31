#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/FlowWatch.xcodeproj"
SCHEME="FlowWatch"
CONFIGURATION="Release"

: "${OUTPUT_DIR:?OUTPUT_DIR must point to a new QA output directory}"
: "${MARKETING_VERSION:?MARKETING_VERSION is required}"
: "${CURRENT_PROJECT_VERSION:?CURRENT_PROJECT_VERSION is required}"

if [[ "$OUTPUT_DIR" != /* || "$OUTPUT_DIR" == "/" ]]; then
  echo "OUTPUT_DIR must be an absolute, non-root path."
  exit 1
fi
if [[ -e "$OUTPUT_DIR" ]]; then
  echo "Refusing to overwrite existing QA output directory: $OUTPUT_DIR"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
DERIVED_DATA_PATH="$OUTPUT_DIR/DerivedData"
PRODUCT_NAME="FlowWatchUpdateQA"
SOURCE_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$PRODUCT_NAME.app"
OUTPUT_APP="$OUTPUT_DIR/FlowWatch Update QA.app"
OUTPUT_ZIP="$OUTPUT_DIR/FlowWatchUpdateQA.zip"
PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-Kw0xtR66Yv2vZR3BhYrO1fHoVJDj2/wr5KsPNHBHUd4=}"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION" \
  INFOPLIST_FILE="Config/FlowWatch-QA-Info.plist" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  PRODUCT_BUNDLE_IDENTIFIER="com.hxd.FlowWatch.UpdateQA" \
  PRODUCT_MODULE_NAME="$PRODUCT_NAME" \
  PRODUCT_NAME="$PRODUCT_NAME" \
  SPARKLE_PUBLIC_KEY="$PUBLIC_KEY" \
  build

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "QA build product was not found: $SOURCE_APP"
  exit 1
fi

ditto "$SOURCE_APP" "$OUTPUT_APP"
/usr/bin/codesign \
  --force \
  --deep \
  --sign - \
  --entitlements "$ROOT_DIR/FlowWatch/FlowWatch.entitlements" \
  "$OUTPUT_APP"
/usr/bin/codesign --verify --deep --strict "$OUTPUT_APP"

INFO_PLIST="$OUTPUT_APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")" == "com.hxd.FlowWatch.UpdateQA" ]]
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")" == "$MARKETING_VERSION" ]]
[[ "$(plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")" == "$CURRENT_PROJECT_VERSION" ]]
[[ "$(plutil -extract SUPublicEDKey raw -o - "$INFO_PLIST")" == "$PUBLIC_KEY" ]]

ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_APP" "$OUTPUT_ZIP"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$OUTPUT_ZIP")" > SHA256SUMS.txt
)

echo "QA app generated: $OUTPUT_APP"
echo "QA archive generated: $OUTPUT_ZIP"
