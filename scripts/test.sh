#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift test
xcodegen generate
xcodebuild -project Whittle.xcodeproj -scheme WhittleMac \
  -destination 'platform=macOS' -derivedDataPath build/Mac \
  -only-testing:WhittleMacTests CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Whittle.xcodeproj -scheme WhittlePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.5' \
  -derivedDataPath build/iPad -only-testing:WhittlePadTests \
  CODE_SIGNING_ALLOWED=NO test
