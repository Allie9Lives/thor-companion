#!/usr/bin/env python3
"""Remove the approved access-point pin and restore normal Wi-Fi roaming."""
from pathlib import Path
import argparse, subprocess, shlex
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--adb',default=str(Path(__file__).resolve().parents[2]/'work/android-tools/platform-tools/adb'))
p.add_argument('--serial')
p.add_argument('--network-id',type=int,required=True,help='Saved network ID; the development device used 3')
a=p.parse_args()
if a.network_id<0:raise SystemExit('Network ID must be nonnegative.')
adb=[a.adb]+(['-s',a.serial] if a.serial else [])
subprocess.run(adb+['push',str(Path(__file__).with_name('wifi-band-tool.jar')),'/data/local/tmp/thor-wifi-band-tool.jar'],check=True)
command='CLASSPATH=/data/local/tmp/thor-wifi-band-tool.jar '+shlex.join(['app_process','/system/bin','WifiBandTool','clear',str(a.network_id)])
subprocess.run(adb+['shell',command],check=True)
print('Access-point pin removed. Android can roam again; the previous 6 GHz boot-connection issue may return.')
