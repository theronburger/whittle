#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--developer-id" ) ]]; then
  echo 'Usage: scripts/install-mac.sh [--developer-id]' >&2
  exit 2
fi
xcodegen generate
if [[ "${1:-}" == "--developer-id" ]]; then
  archive="$(pwd)/build/Archives/WhittleMac.xcarchive"
  xcodebuild -project Whittle.xcodeproj -scheme WhittleMac \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath build/ArchiveMac -archivePath "$archive" \
    -allowProvisioningUpdates archive
  python3 - <<'PYTHON'
import pathlib
import plistlib
options = {'method': 'developer-id', 'signingStyle': 'automatic', 'destination': 'upload'}
pathlib.Path('build/DeveloperID-ExportOptions.plist').write_bytes(plistlib.dumps(options))
PYTHON
  xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist build/DeveloperID-ExportOptions.plist \
    -exportPath build/DeveloperID-Submission -allowProvisioningUpdates
  export_directory=$(mktemp -d "$(pwd)/build/DeveloperID-Notarized.XXXXXXXX")
  for attempt in {1..120}; do
    if notarization_result=$(xcodebuild -exportNotarizedApp -archivePath "$archive" \
      -exportPath "$export_directory" -allowProvisioningUpdates 2>&1); then
      printf '%s\n' "$notarization_result"
      break
    fi
    printf '%s\n' "$notarization_result" >&2
    if [[ "$notarization_result" != *'is processing and not ready for distribution'* || "$attempt" -eq 120 ]]; then
      exit 1
    fi
    printf 'Waiting for Apple notarization (%s/120)…\n' "$attempt"
    sleep 15
  done
  candidate="$export_directory/Whittle.app"
  xcrun stapler validate "$candidate"
  spctl --assess --type execute "$candidate"
else
  xcodebuild -project Whittle.xcodeproj -scheme WhittleMac \
    -destination 'platform=macOS' -derivedDataPath build/SignedMac \
    -allowProvisioningUpdates build
  candidate="$(pwd)/build/SignedMac/Build/Products/Debug/Whittle.app"
fi
installed="$HOME/Applications/Whittle.app"
python3 scripts/check-signing.py "$candidate" "$installed"
mkdir -p "$HOME/Applications"
staging_directory=$(mktemp -d "$HOME/Applications/.whittle-install.XXXXXXXX")
ditto "$candidate" "$staging_directory/Whittle.app"
codesign --verify --deep --strict "$staging_directory/Whittle.app"
python3 - "$installed" "$staging_directory" <<'PYTHON'
import subprocess
import sys
import os
import time
from pathlib import Path
installed = Path(sys.argv[1])
staging_directory = Path(sys.argv[2])
executable = str(installed / 'Contents/MacOS/Whittle')
for line in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines():
    process = line.strip().split(maxsplit=1)
    if len(process) == 2 and process[1] == executable:
        pid = int(process[0])
        os.kill(pid, 15)
        for _ in range(100):
            try: os.kill(pid, 0)
            except ProcessLookupError: break
            time.sleep(0.1)
        else: raise SystemExit('Whittle did not quit. Close it before installing the update.')
previous = staging_directory / 'Previous.app'
if installed.exists(): installed.rename(previous)
try:
    (staging_directory / 'Whittle.app').rename(installed)
except OSError:
    if previous.exists() and not installed.exists(): previous.rename(installed)
    raise
if previous.exists(): print(f'Previous app retained for rollback: {previous}')
PYTHON
open --stdout "$(pwd)/build/MacConsole.log" --stderr "$(pwd)/build/MacConsole.log" "$installed"
