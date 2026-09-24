#!/bin/zsh
# Сборка для симулятора. macOS помечает файлы атрибутом com.apple.provenance,
# из-за чего codesign иногда падает; тогда чистим атрибуты и пробуем ещё раз.
set -u
cd "$(dirname "$0")/.."
DEST="${1:-platform=iOS Simulator,id=2A4F6E7A-D826-4770-B6D1-F86F4CA1FE8A}"
for attempt in 1 2 3; do
  xattr -cr build/Build/Products 2>/dev/null
  log=$(xcodebuild -project UlyKosh.xcodeproj -scheme UlyKosh -destination "$DEST" -configuration Debug -derivedDataPath build build 2>&1)
  if echo "$log" | grep -q 'BUILD SUCCEEDED'; then
    echo "BUILD SUCCEEDED (attempt $attempt)"
    exit 0
  fi
  if ! echo "$log" | grep -q 'detritus'; then
    echo "$log" | grep -E 'error:' | head -20
    echo "BUILD FAILED"
    exit 1
  fi
done
echo "BUILD FAILED after 3 attempts (codesign xattr)"
exit 1
