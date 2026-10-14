#!/usr/bin/env python3
"""Reject unstable signatures and accidental identity changes before installation."""
import pathlib
import subprocess
import sys


def run(*args):
    return subprocess.run(args, capture_output=True, text=True)


def requirement(bundle):
    result = run('codesign', '-d', '-r-', str(bundle))
    if result.returncode:
        raise ValueError(f'Cannot read signing requirement: {bundle}')
    for line in (result.stdout + result.stderr).splitlines():
        if 'designated =>' in line:
            return line.split('designated =>', 1)[1].strip()
    raise ValueError(f'No signing requirement: {bundle}')


def stable(bundle):
    result = run('codesign', '-dv', str(bundle))
    if result.returncode or 'Signature=adhoc' in result.stderr:
        return False
    return 'cdhash ' not in requirement(bundle)


def check(candidate, installed):
    if not stable(candidate):
        raise ValueError('Refusing an unstable app signature; use a persistent code-signing certificate.')
    if not installed.exists():
        print('Certificate-signed app ready. A first installation may need Screen Recording permission.')
        return
    result = run('codesign', '--verify', '--strict', '-R=' + requirement(installed), str(candidate))
    if result.returncode:
        raise ValueError('Signing identity changed. Installation stopped to preserve Screen Recording permission.')
    else:
        print('Verified: update satisfies the installed app’s signing requirement.')


if __name__ == '__main__':
    try:
        check(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
    except ValueError as error:
        sys.exit(str(error))
