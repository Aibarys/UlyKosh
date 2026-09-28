#!/bin/zsh
# Запуск тестов в симуляторе с повтором при сбое подписи из-за xattr.
set -u
cd "$(dirname "$0")/.."
DEST="${1:-platform=iOS Simulator,id=2A4F6E7A-D826-4770-B6D1-F86F4CA1FE8A}"
for attempt in 1 2 3; do
  xattr -cr build 2>/dev/null
  log=$(xcodebuild test -project UlyKosh.xcodeproj -scheme UlyKosh -destination "$DEST" -derivedDataPath build 2>&1)
  if echo "$log" | grep -q 'detritus'; then continue; fi
  echo "$log" | grep -E 'error:|✘|Expectation failed|Issue recorded|Test run with|TEST (SUCCEEDED|FAILED)'
  echo "$log" | grep -q 'TEST SUCCEEDED' && exit 0 || exit 1
done
echo "TEST FAILED after 3 attempts (codesign xattr)"; exit 1
