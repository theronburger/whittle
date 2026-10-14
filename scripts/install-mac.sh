#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Whittle.xcodeproj -scheme WhittleMac \
  -destination 'platform=macOS' -derivedDataPath build/SignedMac \
  -allowProvisioningUpdates build
candidate="$(pwd)/build/SignedMac/Build/Products/Debug/Whittle.app"
installed="$HOME/Applications/Whittle.app"
python3 scripts/check-signing.py "$candidate" "$installed"
python3 - "$installed" <<'PYTHON'
import subprocess
import sys
import os
import time
executable = sys.argv[1] + '/Contents/MacOS/Whittle'
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
PYTHON
mkdir -p "$HOME/Applications"
ditto "$candidate" "$installed"
open --stdout "$(pwd)/build/MacConsole.log" --stderr "$(pwd)/build/MacConsole.log" "$installed"
