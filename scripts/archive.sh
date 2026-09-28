#!/bin/zsh
# Release-архив для TestFlight и экспорт IPA. Требует вход в Apple ID в Xcode.
#   scripts/archive.sh            — архив + экспорт в build/export
#   scripts/archive.sh upload     — архив + выгрузка в App Store Connect
set -u
cd "$(dirname "$0")/.."
MODE="${1:-export}"
ARCHIVE="$PWD/build/UlyKosh.xcarchive"
rm -rf "$ARCHIVE" build/export
for attempt in 1 2 3; do
  xattr -cr build 2>/dev/null
  log=$(xcodebuild archive -project UlyKosh.xcodeproj -scheme UlyKosh -configuration Release \
        -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath build \
        -allowProvisioningUpdates 2>&1)
  if echo "$log" | grep -q 'ARCHIVE SUCCEEDED'; then break; fi
  if ! echo "$log" | grep -q detritus; then echo "$log" | grep -E 'error:' | sort -u; echo "ARCHIVE FAILED"; exit 1; fi
done
echo "ARCHIVE SUCCEEDED"
xattr -cr "$ARCHIVE" 2>/dev/null
OPTS=scripts/ExportOptions.plist
if [[ "$MODE" == "upload" ]]; then
  OPTS=build/ExportOptionsUpload.plist
  /usr/libexec/PlistBuddy -c "Set :destination upload" -x scripts/ExportOptions.plist > /dev/null 2>&1 || true
  sed 's#<string>export</string>#<string>upload</string>#' scripts/ExportOptions.plist > "$OPTS"
fi
log=$(xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$PWD/build/export" -exportOptionsPlist "$OPTS" -allowProvisioningUpdates 2>&1)
if echo "$log" | grep -q 'EXPORT SUCCEEDED'; then
  echo "EXPORT SUCCEEDED ($MODE)"; ls -la build/export 2>/dev/null | grep -E 'ipa|log' ; exit 0
fi
echo "$log" | grep -iE 'error|failed' | grep -v 'export ' | sort -u | head -20
echo "EXPORT FAILED"; exit 1
