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

# Номер сборки растёт на единицу при каждой выгрузке и коммитится, чтобы App Store Connect не отклонил повтор.
if [[ "$MODE" == "upload" ]]; then
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "В рабочем дереве есть незакоммиченные изменения. Закоммитьте их перед выгрузкой."; exit 1
  fi
  CUR=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed -E 's/.*"([0-9]+)".*/\1/')
  VER=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  NEXT=$((CUR + 1))
  sed -i '' -E "s/^(\s*CURRENT_PROJECT_VERSION:) \"$CUR\"/\1 \"$NEXT\"/" project.yml
  xcodegen generate > /dev/null
  git add project.yml UlyKosh.xcodeproj/project.pbxproj
  git commit -q -m "Сборка $VER ($NEXT) для TestFlight"
  echo "Номер сборки: $CUR → $NEXT, версия $VER"
fi
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
  echo "EXPORT SUCCEEDED ($MODE)"; ls -la "$BUILD_DIR/export" 2>/dev/null | grep -E 'ipa|log'
  if [[ "$MODE" == "upload" ]]; then git tag -f "build-$NEXT" > /dev/null && git push -q origin HEAD --tags && echo "Коммит и тег build-$NEXT запушены"; fi
  exit 0
fi
echo "$log" | grep -iE 'error|failed' | grep -v 'export ' | sort -u | head -20
echo "EXPORT FAILED"; exit 1
