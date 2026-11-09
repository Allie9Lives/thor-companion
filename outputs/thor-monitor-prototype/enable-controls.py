#!/usr/bin/env python3
"""Bootstrap Thor controls over authorized USB debugging; optionally enable automatic recovery."""
import argparse
import re
import shlex
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--adb', default=str(Path(__file__).resolve().parents[2] / 'work/android-tools/platform-tools/adb'))
parser.add_argument('--serial', help='ADB serial when more than one Android device is connected')
parser.add_argument('--restart', action='store_true', help='Restart the helper after a host update')
parser.add_argument('--enable-recovery',action='store_true',help='Grant the one-time permission for boot recovery; pair locally in Thor Monitor next')
args = parser.parse_args()
adb = [args.adb] + (['-s', args.serial] if args.serial else [])
def shell(*parts):
    return subprocess.check_output(adb + ['shell', shlex.join(parts)], text=True).strip()
if args.enable_recovery:
    shell('pm','grant','com.alan.thormonitor','android.permission.WRITE_SECURE_SETTINGS')
name = shell('run-as', 'com.alan.thormonitor', 'cat', 'files/control-socket')
if not re.fullmatch(r'thor-controls-[a-f0-9]{32}', name):
    raise SystemExit('Open Thor Monitor once, then run this again.')
uid = re.search(r'uid:(\d+)', shell('cmd', 'package', 'list', 'packages', '-U', 'com.alan.thormonitor'))
if not uid:
    raise SystemExit('Thor Monitor is not installed.')
apk = shell('pm', 'path', 'com.alan.thormonitor').removeprefix('package:')
if not apk.startswith('/data/app/') or '\n' in apk:
    raise SystemExit('Unexpected app location.')
if args.restart:
    running = subprocess.run(adb + ['shell','pidof','thor-control-helper'], text=True, capture_output=True)
    pids = running.stdout.split()
    if pids and all(pid.isdecimal() for pid in pids):
        shell('kill', *pids)
command = 'CLASSPATH=' + shlex.quote(apk) + ' ' + shlex.join(['/system/bin/setsid', '/system/bin/nohup', '/system/bin/app_process', '/system/bin', '--nice-name=thor-control-helper', 'com.alan.thormonitor.ControlHelper', name, uid.group(1)])
# A running helper already owns the socket; a second invocation exits harmlessly.
subprocess.run(adb + ['shell', command + ' </dev/null >/data/local/tmp/thor-control-helper.log 2>&1 & sleep 1'], check=True)
print('Controls helper launched. Complete Automatic recovery pairing in Thor Monitor for future restarts without a connected computer.')
