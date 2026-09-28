#!/bin/zsh
# Release-архив для TestFlight и экспорт IPA. Требует вход в Apple ID в Xcode.
#   scripts/archive.sh            — архив + экспорт IPA в ~/Library/Caches/UlyKosh/build/export
#   scripts/archive.sh upload     — архив + выгрузка в App Store Connect
set -u
cd "$(dirname "$0")/.."
BUILD_DIR="$HOME/Library/Caches/UlyKosh/build"
mkdir -p "$BUILD_DIR"
MODE="${1:-export}"
ARCHIVE="$BUILD_DIR/UlyKosh.xcarchive"
rm -rf "$ARCHIVE" "$BUILD_DIR/export"
for attempt in 1 2 3; do
  true
  log=$(xcodebuild archive -project UlyKosh.xcodeproj -scheme UlyKosh -configuration Release \
        -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath "$BUILD_DIR" \
        -allowProvisioningUpdates 2>&1)
  if echo "$log" | grep -q 'ARCHIVE SUCCEEDED'; then break; fi
  if ! echo "$log" | grep -q detritus; then echo "$log" | grep -E 'error:' | sort -u; echo "ARCHIVE FAILED"; exit 1; fi
done
if [[ ! -d "$ARCHIVE" ]]; then
  echo "$log" | grep -E 'error:|detritus' | sort -u | head -5
  echo "ARCHIVE FAILED after 3 attempts"; exit 1
fi
echo "ARCHIVE SUCCEEDED"
xattr -cr "$ARCHIVE" 2>/dev/null
OPTS=scripts/ExportOptions.plist
if [[ "$MODE" == "upload" ]]; then
  OPTS="$BUILD_DIR/ExportOptionsUpload.plist"
  /usr/libexec/PlistBuddy -c "Set :destination upload" -x scripts/ExportOptions.plist > /dev/null 2>&1 || true
  sed 's#<string>export</string>#<string>upload</string>#' scripts/ExportOptions.plist > "$OPTS"
fi
log=$(xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$BUILD_DIR/export" -exportOptionsPlist "$OPTS" -allowProvisioningUpdates 2>&1)
if echo "$log" | grep -q 'EXPORT SUCCEEDED'; then
  echo "EXPORT SUCCEEDED ($MODE)"; ls -la "$BUILD_DIR/export" 2>/dev/null | grep -E 'ipa|log' ; exit 0
fi
echo "$log" | grep -iE 'error|failed' | grep -v 'export ' | sort -u | head -20
echo "EXPORT FAILED"; exit 1
