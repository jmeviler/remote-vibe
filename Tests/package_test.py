#!/usr/bin/env python3
"""Inspect built/downloaded packages; never install an App or HAL driver."""
import argparse
import hashlib
import io
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def check_zip(archive):
    assert archive.testzip() is None, 'Corrupt ZIP'
    assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in archive.namelist())


def signature(bundle):
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--arch', required=True, choices=['arm64', 'x86_64'])
    parser.add_argument('--directory', type=Path, default=Path('build/share'))
    parser.add_argument('--source-commit', default=None)
    parser.add_argument('--check-installer', action='store_true')
    args = parser.parse_args()
    chip = {'arm64': 'AppleSilicon', 'x86_64': 'Intel'}[args.arch]
    info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    commit = args.source_commit or run('git', 'rev-parse', 'HEAD')
    base = f'Remote-Vibe-{version}-Mac-{chip}'
    app_name = f'Remote-Vibe-{version}-App-{chip}.zip'
    checksums = args.directory / f'SHA256SUMS-{chip}.txt'
    if not checksums.exists():
        checksums = args.directory / 'SHA256SUMS.txt'
    expected = {base + '.zip', app_name}
    verified = set()
    for line in checksums.read_text().splitlines():
        digest, name = line.split(maxsplit=1)
        if name in expected:
            assert name not in verified
            assert hashlib.sha256((args.directory / name).read_bytes()).hexdigest() == digest, name
            verified.add(name)
    assert verified == expected, 'Missing downloads/checksums'

    with tempfile.TemporaryDirectory(prefix='remote-vibe-package-') as temp:
        temp = Path(temp)
        with zipfile.ZipFile(args.directory / (base + '.zip')) as full:
            check_zip(full)
            assert full.read(base + '/源码与许可证/源代码版本.txt').decode().strip() == commit
            with zipfile.ZipFile(io.BytesIO(full.read(base + '/源码与许可证/remote-vibe-source.zip'))) as source:
                check_zip(source)
                tracked = set(run('git', 'ls-files', '-z').rstrip('\0').split('\0'))
                assert {n for n in source.namelist() if not n.endswith('/')} == tracked
                for name in tracked:
                    assert source.read(name) == Path(name).read_bytes(), f'Incorrect source: {name}'
            for line in full.read(base + '/SHA256.txt').decode().splitlines():
                digest, name = line.split(maxsplit=1)
                assert hashlib.sha256(full.read(base + '/' + name)).hexdigest() == digest
            full.extractall(temp / 'full')
        with zipfile.ZipFile(args.directory / app_name) as archive:
            check_zip(archive)
        subprocess.run(['ditto', '-x', '-k', str(args.directory / app_name), str(temp / 'update')], check=True)
        app = temp / 'update/Remote Vibe.app'
        assert plistlib.loads((app / 'Contents/Info.plist').read_bytes()) == info
        assert (app / 'Contents/Resources/Source-Commit.txt').read_text().strip() == commit
        assert (temp / 'update/Source-Commit.txt').read_text().strip() == commit
        assert run('lipo', '-archs', str(app / 'Contents/MacOS/RemoteVibe')) == args.arch
        signature(app)
        for image in Path('Resources/StatusBar').glob('StatusBar*Template*.png'):
            assert (app / 'Contents/Resources' / image.name).read_bytes() == image.read_bytes()

        expanded = temp / 'installer'
        subprocess.run(['pkgutil', '--expand-full', str(temp / 'full' / base / '1-安装 Remote Vibe.pkg'),
                        str(expanded)], check=True)
        options = ET.parse(expanded / 'Distribution').getroot().find('options')
        assert options is not None and options.attrib['hostArchitectures'] == args.arch
        installed_apps = list(expanded.rglob('Remote Vibe.app'))
        drivers = list(expanded.rglob('RemoteVibeMic.driver'))
        assert len(installed_apps) == len(drivers) == 1
        for path in app.rglob('*'):
            if path.is_file():
                assert (installed_apps[0] / path.relative_to(app)).read_bytes() == path.read_bytes()
        driver = drivers[0]
        assert run('lipo', '-archs', str(driver / 'Contents/MacOS/RemoteVibeMic')) == args.arch
        signature(installed_apps[0])
        signature(driver)
        for name in ['Driver/RemoteVibeMic.c', 'Scripts/build-driver.sh', 'Scripts/build-target.sh']:
            assert (driver / 'Contents/Resources' / name).read_bytes() == Path(name).read_bytes()
        installers = list(expanded.rglob('preinstall'))
        assert len(installers) == 1
        preinstall = installers[0]
        assert preinstall.read_text() == Path('Installer/preinstall').read_text().replace('@REMOTE_VIBE_ARCH@', args.arch)
        if args.check_installer:
            # Only exercise read-only preflight on an empty native CI runner.
            assert os.environ.get('CI') == 'true' and run('uname', '-m') == args.arch
            assert not Path('/Applications/Remote Vibe.app').exists()
            assert not Path('/Library/Audio/Plug-Ins/HAL/RemoteVibeMic.driver').exists()
            subprocess.run(['zsh', str(preinstall)], check=True)
            wrong = temp / 'wrong-architecture-preinstall'
            other = 'x86_64' if args.arch == 'arm64' else 'arm64'
            wrong.write_text(preinstall.read_text().replace(f"package_arch='{args.arch}'", f"package_arch='{other}'"))
            rejected = subprocess.run(['zsh', str(wrong)], capture_output=True, text=True)
            assert rejected.returncode != 0 and '本安装包不适用于这台 Mac 的芯片' in rejected.stderr
    print(f'PASS [{chip}]: checksums, source, native App/driver, signatures, installer architecture and resources.')


if __name__ == '__main__':
    main()
