"""Package a signed Runner.app as an IPA and check IPAs before release.

  python3 tool/package_ipa.py package <Runner.app> <output.ipa>
  python3 tool/package_ipa.py check <file.ipa> [--min-profile-days N]

The IPA is written with Python's zipfile, which never adds macOS resource-fork
or Finder metadata (`._*`, `__MACOSX`, `.DS_Store`). Do not use `ditto -c -k`
without `--norsrc`, or Finder "Compress", to make release IPAs.
"""
from datetime import datetime, timezone
from pathlib import Path
import argparse, hashlib, json, os, plistlib, stat, subprocess, sys, tempfile, zipfile

APP = 'Payload/Runner.app/'


def is_metadata(name):
    return any(p.startswith('._') or p in ('__MACOSX', '.DS_Store') for p in name.split('/'))


def package(app, output):
    app, output = Path(app).resolve(), Path(output).resolve()
    if app.name != 'Runner.app' or not (app / 'Info.plist').is_file():
        raise SystemExit(f'Not a built Runner.app: {app}')
    if output.exists():
        raise SystemExit(f'Refusing to overwrite {output}; choose a new file name.')
    junk = [str(p.relative_to(app)) for p in app.rglob('*') if is_metadata(p.name)]
    if junk:
        # These would sit inside the signed bundle; removing them here would hide a build problem.
        raise SystemExit('Runner.app contains metadata files; rebuild cleanly:\n  ' + '\n  '.join(junk))
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as z:
        for base in ('Payload/', APP):
            info = zipfile.ZipInfo(base)
            info.external_attr = (stat.S_IFDIR | 0o755) << 16
            z.writestr(info, b'')
        for path in sorted(app.rglob('*')):
            name = APP + path.relative_to(app).as_posix()
            mode = os.lstat(path).st_mode
            if path.is_symlink():
                info = zipfile.ZipInfo(name)
                info.external_attr = (stat.S_IFLNK | 0o755) << 16
                z.writestr(info, os.readlink(path))
            elif path.is_dir():
                info = zipfile.ZipInfo(name + '/')
                info.external_attr = (stat.S_IFDIR | stat.S_IMODE(mode)) << 16
                z.writestr(info, b'')
            else:
                z.write(path, name)
    return check(output)


def _plist(z, name):
    return plistlib.loads(z.read(name))


def _profile(path):
    if not path.is_file():
        return None
    raw = subprocess.run(['security', 'cms', '-D', '-i', str(path)], capture_output=True, check=True).stdout
    p = plistlib.loads(raw)
    return {'name': p.get('Name'), 'expires': p['ExpirationDate'].replace(tzinfo=timezone.utc).isoformat(),
            'days_left': (p['ExpirationDate'].replace(tzinfo=timezone.utc) - datetime.now(timezone.utc)).days,
            'devices': len(p.get('ProvisionedDevices', [])), 'all_devices': bool(p.get('ProvisionsAllDevices'))}


def check(ipa, min_profile_days=0, codesign=True):
    ipa = Path(ipa)
    errors, warnings = [], []
    with zipfile.ZipFile(ipa) as z:
        names = z.namelist()
        if len(names) != len(set(names)):
            errors.append('duplicate entry names')
        junk = [n for n in names if is_metadata(n)]
        if junk:
            errors.append(f'{len(junk)} macOS metadata entries, e.g. {junk[0]}')
        outside = [n for n in names if not n.startswith('Payload/') or '..' in n.split('/')]
        if outside:
            errors.append(f'entries outside Payload/: {outside[:3]}')
        if z.testzip() is not None:
            errors.append('ZIP CRC check failed')
        if APP + 'Info.plist' not in names:
            raise SystemExit(f'{ipa}: missing {APP}Info.plist')
        bundles = {APP.rstrip('/'): _plist(z, APP + 'Info.plist')}
        for n in names:
            parts = n.split('/')
            if len(parts) == 5 and parts[2] == 'PlugIns' and parts[3].endswith('.appex') and parts[4] == 'Info.plist':
                bundles['/'.join(parts[:4])] = _plist(z, n)
        appex_dirs = {'/'.join(n.split('/')[:4]) for n in names if n.startswith(APP + 'PlugIns/') and n.split('/')[3:4] and n.split('/')[3].endswith('.appex')}
        for d in appex_dirs - set(bundles):
            errors.append(f'{d} has no Info.plist')
        versions = {k: (v.get('CFBundleIdentifier'), v.get('CFBundleShortVersionString'), v.get('CFBundleVersion')) for k, v in bundles.items()}
        if len({v[1:] for v in versions.values()}) > 1:
            errors.append(f'app and extension versions differ: {versions}')
        profiles = {}
        if codesign:
            with tempfile.TemporaryDirectory() as tmp:
                z.extractall(tmp)  # entry names were checked above
                for bundle in bundles:
                    r = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(Path(tmp, bundle))], capture_output=True, text=True)
                    if r.returncode:
                        errors.append(f'codesign failed for {bundle}: {r.stderr.strip()}')
                    prof = _profile(Path(tmp, bundle, 'embedded.mobileprovision'))
                    profiles[bundle] = prof
                    if prof and prof['days_left'] < min_profile_days:
                        errors.append(f'{bundle} profile expires in {prof["days_left"]} days ({prof["expires"]})')
                    elif prof and prof['days_left'] < 14:
                        warnings.append(f'{bundle} profile expires {prof["expires"]}')
                    if prof and not prof['all_devices']:
                        warnings.append(f'{bundle} profile installs directly on {prof["devices"]} registered device(s) only; others must re-sign')
    return {'ipa': str(ipa), 'ok': not errors, 'errors': errors, 'warnings': warnings,
            'entries': len(names), 'bundles': versions, 'profiles': profiles,
            'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest()}


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('package'); p.add_argument('app'); p.add_argument('output')
    c = sub.add_parser('check'); c.add_argument('ipa'); c.add_argument('--min-profile-days', type=int, default=0)
    c.add_argument('--no-codesign', action='store_true', help='skip signature/profile checks (non-macOS)')
    a = ap.parse_args()
    result = package(a.app, a.output) if a.cmd == 'package' else check(a.ipa, a.min_profile_days, not a.no_codesign)
    print(json.dumps(result, indent=2))
    sys.exit(0 if result['ok'] else 1)
