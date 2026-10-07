#!/usr/bin/env python3
"""Verify and stage a native release; signing/notarization require explicit options."""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from build_config import FLAGS, ROOT, TARGET, SIGNATURE_CMS_RESERVE_BYTES, preflight, source_hashes

BINARY_BUDGET = APP_BUDGET = 200000
DMG_BUDGET = 120000


def run(*command):
    return subprocess.run(command, cwd=ROOT, check=True, text=True,
                          capture_output=True).stdout.strip()


def version():
    value = (ROOT / 'VERSION').read_text().strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+', value):
        raise ValueError('VERSION must contain a numeric major.minor.patch version.')
    return value


def release_icon():
    icon = ROOT / 'Resources/AppIcon.icns'
    if not icon.is_file():
        raise ValueError('Required release icon is missing: Resources/AppIcon.icns')
    data = icon.read_bytes()
    if len(data) < 8 or data[:4] != b'icns' or int.from_bytes(data[4:8], 'big') != len(data):
        raise ValueError('Resources/AppIcon.icns is not a valid ICNS container.')
    return icon


def git_head():
    # Source ZIPs need no Git installation/repository. Do not report a parent repo.
    try:
        top = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '--show-toplevel'],
                             check=True, text=True, capture_output=True).stdout.strip()
        if pathlib.Path(top).resolve() != ROOT.resolve():
            return None
        return subprocess.run(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'],
                              check=True, text=True, capture_output=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def files_in(app):
    files = {}
    for path in sorted(app.rglob('*')):
        if path.is_symlink():
            raise ValueError('Unexpected symlink in app payload: ' + str(path))
        if path.is_file():
            files[str(path.relative_to(app))] = {'bytes': path.stat().st_size,
                                                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    return files


def enforce_budgets(report):
    if report['binary_bytes'] > BINARY_BUDGET or report['app_bytes'] > APP_BUDGET:
        raise ValueError('Release exceeds the 200,000-byte executable/app budgets; '
                         'icons, signing certificates and notarization overhead count toward the same caps.')
    if report.get('dmg_bytes', 0) > DMG_BUDGET:
        raise ValueError('Release exceeds the 120,000-byte download budget.')


def promote(staged, output):
    """Rename only verified output; restore the same previous directory on failure."""
    previous = output.with_name('.' + output.name + '-previous-' + uuid.uuid4().hex)
    had_previous = output.exists()
    if had_previous:
        output.rename(previous)
    try:
        staged.rename(output)
    except BaseException:
        if had_previous:
            # If restoration itself fails, preserve the backup outside staging.
            try:
                previous.rename(output)
            except OSError as error:
                raise RuntimeError('Promotion failed; previous release is preserved at ' + str(previous)) from error
        raise
    if had_previous:
        print('Previous release retained at ' + str(previous), file=sys.stderr)
    return previous if had_previous else None


def preserve_failure(workspace, error):
    """Keep bounded text diagnostics; staging binaries are never promoted."""
    directory = ROOT / 'artifacts/release-failures'
    directory.mkdir(parents=True, exist_ok=True)
    saved = pathlib.Path(tempfile.mkdtemp(prefix='release-', dir=directory))
    (saved / 'failure.json').write_text(json.dumps({'passed': False,
        'error': (type(error).__name__ + ': ' + str(error))[:8192]}, indent=2) + '\n')
    for source in sorted((workspace / 'gates').glob('*')):
        if source.is_file() and source.suffix in ('.log', '.json'):
            content = source.read_bytes()
            if len(content) <= 1024 * 1024:
                (saved / source.name).write_bytes(content)
            else:
                (saved / (source.name + '.tail.log')).write_bytes(content[-1024 * 1024:])
    if isinstance(error, subprocess.CalledProcessError):
        output = (error.stdout or '') + '\n' + (error.stderr or '')
        (saved / 'command.log').write_text(output[-1024 * 1024:])
    return saved


def verify_dmg(dmg, expected_files, mode, notarized=False):
    """Mount without writes or launch, compare every payload file, then detach."""
    run('hdiutil', 'verify', str(dmg))
    with tempfile.TemporaryDirectory(prefix='ultralight-dmg-audit-') as directory:
        mount = pathlib.Path(directory) / 'volume'
        mount.mkdir()
        attached = False
        try:
            run('hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
                '-mountpoint', str(mount), str(dmg))
            attached = True
            visible = sorted(p.name for p in mount.iterdir() if not p.name.startswith('.'))
            if visible != ['Ultralight.app']:
                raise ValueError('DMG must contain exactly Ultralight.app at its root: ' + repr(visible))
            app = mount / 'Ultralight.app'
            if not app.is_dir() or app.is_symlink() or files_in(app) != expected_files:
                raise ValueError('Mounted DMG app does not exactly match the verified release payload.')
            # Full layout/tamper checking was done before packaging; verify the mounted seal too.
            run('codesign', '--verify', '--strict', str(app))
            if notarized:
                run('xcrun', 'stapler', 'validate', str(app))
            return {'passed': True, 'read_only': True, 'root_entries': visible,
                    'payload_files': len(expected_files), 'signature_mode': mode,
                    'stapled_app_validated': notarized}
        finally:
            if attached or os.path.ismount(mount):
                run('hdiutil', 'detach', str(mount))


def notarize(artifact, profile):
    result = json.loads(run('xcrun', 'notarytool', 'submit', str(artifact), '--wait',
                            '--keychain-profile', profile, '--output-format', 'json'))
    if result.get('status') != 'Accepted':
        raise ValueError('Notarization was not accepted: ' + str(result.get('status')) +
                         '; submission ' + str(result.get('id')))
    return {'id': result.get('id'), 'status': result['status']}


def stage_release(stage, workspace, args, environment):
    # Use a private gate report so concurrent check commands cannot substitute it.
    gates = workspace / 'gates'
    run(sys.executable, str(ROOT / 'Scripts/check.py'), '--output', str(gates))
    verified = json.loads((gates / 'results.json').read_text())
    checked_sources = verified['source_sha256']
    if not verified['passed'] or verified['flags'] != FLAGS or source_hashes() != checked_sources:
        raise ValueError('Source/build policy changed after quality gates; rerun the release.')
    app = stage / 'Ultralight.app'
    contents = app / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    binary = contents / 'MacOS/Ultralight'
    run('xcrun', 'swiftc', '-module-name', 'Ultralight', '-target', TARGET, *FLAGS,
        *[str(p) for p in sorted((ROOT / 'Sources').rglob('*.swift'))], '-o', str(binary))
    info = dict(CFBundleName='Ultralight', CFBundleIdentifier='com.ultralight.player',
                CFBundleExecutable='Ultralight', CFBundlePackageType='APPL',
                CFBundleVersion=version(), CFBundleShortVersionString=version(),
                LSMinimumSystemVersion='14.0', NSHighResolutionCapable=True,
                LSUIElement=False, NSSupportsAutomaticTermination=False)
    icon = release_icon()
    (contents / 'Resources').mkdir()
    shutil.copyfile(icon, contents / 'Resources/AppIcon.icns')
    shutil.copyfile(ROOT / 'LICENSE', contents / 'Resources/LICENSE')
    info['CFBundleIconFile'] = 'AppIcon'
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
    run('strip', '-rSTx', '-N', str(binary))
    mode = 'adhoc' if args.sign_identity == '-' else 'developer-id'
    signing = ['codesign', '--force', '--sign', args.sign_identity]
    if mode == 'adhoc':
        signing += ['--signature-size', str(SIGNATURE_CMS_RESERVE_BYTES), '--timestamp=none']
    else:
        signing += ['--options', 'runtime', '--timestamp']
    run(*signing, str(app))
    signature_gate = json.loads(run(sys.executable, str(ROOT / 'Tests/signing/verify.py'), str(app), '--mode', mode))
    notary = {}
    if args.notary_profile:
        archive = workspace / 'notarization.zip'
        run('ditto', '-c', '-k', '--keepParent', str(app), str(archive))
        notary['app'] = notarize(archive, args.notary_profile)
        run('xcrun', 'stapler', 'staple', str(app))
        run('xcrun', 'stapler', 'validate', str(app))
        signature_gate = json.loads(run(sys.executable, str(ROOT / 'Tests/signing/verify.py'), str(app), '--mode', mode))
    files = files_in(app)
    report = {'binary_bytes': binary.stat().st_size, 'app_bytes': sum(v['bytes'] for v in files.values()),
              'architecture': run('lipo', '-archs', str(binary)), 'toolchain': environment['toolchain'],
              'environment': environment, 'version': info['CFBundleVersion'], 'git_head': git_head(),
              'source_sha256': checked_sources, 'flags': FLAGS,
              'signature_cms_reserve_bytes': SIGNATURE_CMS_RESERVE_BYTES if mode == 'adhoc' else None,
              'signature_gate': signature_gate, 'files': files,
              'signature': 'ad-hoc; not Developer ID signed or notarized' if mode == 'adhoc' else
                          'Developer ID; notarized' if args.notary_profile else 'Developer ID; not notarized'}
    if report['architecture'] != 'arm64':
        raise ValueError('Release must contain exactly the verified arm64 architecture.')
    enforce_budgets(report)
    if args.dmg:
        image_root = workspace / 'image-root'
        image_root.mkdir()
        run('ditto', str(app), str(image_root / 'Ultralight.app'))
        dmg = stage / 'Ultralight.dmg'
        command = ['hdiutil', 'create', '-volname', 'Ultralight', '-srcfolder', str(image_root), '-format', args.dmg]
        if args.dmg == 'UDZO':
            command += ['-imagekey', 'zlib-level=9']
        run(*command, str(dmg))
        if mode == 'developer-id':
            run('codesign', '--force', '--sign', args.sign_identity, '--timestamp', str(dmg))
        if args.notary_profile:
            notary['dmg'] = notarize(dmg, args.notary_profile)
            run('xcrun', 'stapler', 'staple', str(dmg))
            run('xcrun', 'stapler', 'validate', str(dmg))
        report['dmg_gate'] = verify_dmg(dmg, files, mode, bool(args.notary_profile))
        report.update(dmg_bytes=dmg.stat().st_size, dmg_format=args.dmg,
                      dmg_sha256=hashlib.sha256(dmg.read_bytes()).hexdigest())
        enforce_budgets(report)
    if notary:
        report['notarization'] = notary
    if source_hashes() != checked_sources:
        raise ValueError('Source changed during release staging; previous release preserved.')
    shutil.copytree(gates, stage / 'gates')
    (stage / 'size.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'artifacts/release')
    parser.add_argument('--dmg', choices=['UDZO', 'UDBZ', 'ULFO'])
    parser.add_argument('--sign-identity', default='-', help='Developer ID Application identity; default is local ad-hoc signing')
    parser.add_argument('--notary-profile', help='Explicit opt-in to Apple notarization using a stored keychain profile; requires Developer ID and --dmg')
    args = parser.parse_args(argv)
    if args.notary_profile and (args.sign_identity == '-' or not args.dmg):
        parser.error('--notary-profile requires --sign-identity and --dmg')
    output = args.output.absolute()
    if output.is_symlink() or output.exists() and not output.is_dir():
        parser.error('--output must be a directory, not a file or symlink')
    output = output.resolve()
    if output == ROOT or output in ROOT.parents:
        parser.error('--output must not replace the source directory or its parents')
    if output.exists() and any(output.iterdir()) and not (
            (output / 'size.json').is_file() and (output / 'Ultralight.app').is_dir()):
        parser.error('--output is not empty and is not a previous Ultralight release')
    release_icon()
    environment = preflight()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.' + output.name + '-staging-', dir=output.parent) as directory:
        workspace = pathlib.Path(directory)
        stage = workspace / 'release'
        stage.mkdir()
        try:
            report = stage_release(stage, workspace, args, environment)
            promote(stage, output)
        except BaseException as error:
            failed = preserve_failure(workspace, error)
            print('Previous release preserved; failure evidence: ' + str(failed), file=sys.stderr)
            raise
    print(json.dumps({k: v for k, v in report.items() if k not in ('source_sha256', 'files')}, indent=2))
    print(output / 'Ultralight.app')
    return report


if __name__ == '__main__':
    main()
