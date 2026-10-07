"""Portable negative tests for release tooling; no compiler, audio, or UI required."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Scripts'))
import build_config
import check
import release


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


compare = load('ui_compare', 'Tests/ui/compare.py')
signing = load('signing_verify', 'Tests/signing/verify.py')
observation = load('observation_runner', 'Tests/observation/run.py')


class ToolingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='ultralight-tooling-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def write(self, path, value='fixture'):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        return path

    def renders(self, path):
        path.mkdir()
        for image in compare.EXPECTED_IMAGES:
            (path / image).write_bytes(b'\x89PNG\r\n\x1a\nfixture')
        self.write(path / 'results.json', json.dumps({'checks': [{'name': 'original', 'pass': True}],
                                                     'layouts': {}, 'observations': []}))
        return path

    def test_complete_frozen_images_pass(self):
        a, b = self.renders(self.root / 'a'), self.renders(self.root / 'b')
        report, code = compare.compare(a, b)
        self.assertEqual(code, 0)
        self.assertEqual(len(report['renders']), 3)

    def test_empty_baseline_cannot_pass_vacuously(self):
        a, b = self.renders(self.root / 'a'), self.renders(self.root / 'b')
        for image in a.glob('*.png'):
            image.unlink()
        with self.assertRaisesRegex(ValueError, 'exactly the three'):
            compare.compare(a, b)

    def test_one_missing_baseline_is_rejected(self):
        a, b = self.renders(self.root / 'a'), self.renders(self.root / 'b')
        (a / 'eq-hidden.png').unlink()
        with self.assertRaisesRegex(ValueError, 'eq-hidden.png'):
            compare.compare(a, b)

    def test_missing_candidate_is_rejected(self):
        a, b = self.renders(self.root / 'a'), self.renders(self.root / 'b')
        (b / 'compact-600x400.png').unlink()
        with self.assertRaisesRegex(ValueError, 'candidate'):
            compare.compare(a, b)

    def test_unexpected_render_is_rejected(self):
        a, b = self.renders(self.root / 'a'), self.renders(self.root / 'b')
        self.write(b / 'new.png')
        with self.assertRaisesRegex(ValueError, 'unexpected'):
            compare.compare(a, b)

    def test_changed_image_requires_review(self):
        a, b = self.renders(self.root / 'a'), self.renders(self.root / 'b')
        self.write(b / 'eq-hidden.png', 'changed')
        self.assertEqual(compare.compare(a, b)[1], 2)

    def test_changed_assertion_still_fails(self):
        a, b = self.renders(self.root / 'a'), self.renders(self.root / 'b')
        result = json.loads((b / 'results.json').read_text())
        result['checks'][0]['pass'] = False
        self.write(b / 'results.json', json.dumps(result))
        self.assertEqual(compare.compare(a, b)[1], 1)

    def observation_fixture(self):
        harness = (ROOT / 'Tests/observation/ObservationAudit.swift').read_text()
        import re
        names = re.findall(r'exercise\("(\w+)"', harness)
        source = 'let objectWillChange = ObservableObjectPublisher()\n' + '\n'.join(
            '@Published var ' + name + ': Int = 0 { willSet { objectWillChange.send() } }' for name in names)
        return source, harness

    def test_every_observed_property_is_statically_covered(self):
        source, harness = self.observation_fixture()
        self.assertEqual(len(observation.validate_coverage(source, harness, ['-disable-reflection-metadata'])), 15)

    def test_future_published_property_requires_its_own_semantics_fixture(self):
        source, harness = self.observation_fixture()
        source += '\n@Published var futureField: Int = 0 { willSet { objectWillChange.send() } }'
        with self.assertRaisesRegex(ValueError, 'exhaustive observation fixture'):
            observation.validate_coverage(source, harness, [])

    def test_new_observable_type_requires_its_own_contract_audit(self):
        self.write(self.root / 'Sources/Other.swift', 'final class Other: ObservableObject {\n @Published var value = 0\n}')
        with self.assertRaisesRegex(ValueError, 'new observable type'):
            observation.validate_inventory(self.root)

    def test_missing_manual_notification_is_rejected(self):
        source, harness = self.observation_fixture()
        source = source.replace('willSet { objectWillChange.send() }', '', 1)
        with self.assertRaisesRegex(ValueError, 'exactly once'):
            observation.validate_coverage(source, harness, ['-disable-reflection-metadata'])

    def test_duplicate_manual_notification_is_rejected(self):
        source, harness = self.observation_fixture()
        source += '\nfunc extra() { objectWillChange.send() }'
        with self.assertRaisesRegex(ValueError, 'Unexpected duplicate'):
            observation.validate_coverage(source, harness, [])

    def run_checks(self, scheduled, **options):
        with patch.object(check, 'ROOT', self.root), patch.object(check, 'jobs', return_value=scheduled), \
             patch.object(check, 'preflight', **options), \
             patch.object(check, 'source_hashes', return_value={'source': 'same'}), contextlib.redirect_stdout(io.StringIO()):
            return check.run_checks(self.root / 'gates')

    def test_ui_failure_has_no_secondary_missing_log_error(self):
        self.write(self.root / 'gates/results.json', '{"passed":true}')
        self.write(self.root / 'gates/ui-comparison.log', 'stale successful comparison')
        report = self.run_checks([('ui', ['-c', 'import sys; print("actual failure"); sys.exit(7)'])], return_value={})
        self.assertFalse(report['passed'])
        self.assertEqual(report['suites'], {'ui': 7})
        self.assertNotIn('error', report)
        self.assertFalse((self.root / 'gates/ui-comparison.log').exists())
        self.assertIn('actual failure', (self.root / 'gates/ui.log').read_text())
        self.assertFalse(json.loads((self.root / 'gates/results.json').read_text())['passed'])

    def test_preflight_exception_invalidates_old_success(self):
        self.write(self.root / 'gates/results.json', '{"passed":true}')
        report = self.run_checks([], side_effect=RuntimeError('wrong architecture'))
        self.assertFalse(report['passed'])
        self.assertIn('wrong architecture', report['error'])
        self.assertFalse(json.loads((self.root / 'gates/results.json').read_text())['passed'])

    def test_malformed_ui_report_cannot_leave_success(self):
        self.write(self.root / 'gates/results.json', '{"passed":true}')
        report = self.run_checks([('ui', ['-c', 'print("not JSON")'])], return_value={})
        self.assertFalse(report['passed'])
        self.assertIn('JSONDecodeError', report['error'])

    def test_timeout_is_recorded_and_owned_process_is_killed(self):
        with patch.object(check, 'ROOT', self.root):
            result = check.run_gate(['-c', 'import time; time.sleep(5)'], self.root / 'timeout.log', os.environ.copy(), .05)
        self.assertEqual(result, 124)
        self.assertIn('timed out', (self.root / 'timeout.log').read_text())

    def test_timeout_report_replaces_old_success(self):
        self.write(self.root / 'gates/results.json', '{"passed":true}')
        with patch.object(check, 'run_gate', return_value=124):
            report = self.run_checks([('audio', ['unused'])], return_value={})
        self.assertFalse(report['passed'])
        self.assertEqual(report['suites'], {'audio': 124})

    def test_source_mutation_fails_even_after_all_jobs_pass(self):
        with patch.object(check, 'ROOT', self.root), patch.object(check, 'jobs', return_value=[('audio', [])]), \
             patch.object(check, 'preflight', return_value={}), patch.object(check, 'run_gate', return_value=0), \
             patch.object(check, 'source_hashes', side_effect=[{'a': 'before'}, {'a': 'after'}]), \
             contextlib.redirect_stdout(io.StringIO()):
            report = check.run_checks(self.root / 'gates')
        self.assertFalse(report['passed'])
        self.assertFalse(report['source_stable'])

    def old_release(self):
        output = self.root / 'release'
        binary = self.write(output / 'Ultralight.app/Contents/MacOS/Ultralight', 'previous executable')
        self.write(output / 'size.json', '{"previous":true}')
        return output, binary, binary.stat().st_ino

    def icon(self):
        icon = self.root / 'Resources/AppIcon.icns'
        icon.parent.mkdir(parents=True, exist_ok=True)
        icon.write_bytes(b'icns\0\0\0\x08')
        return icon

    def test_failed_build_preserves_previous_path_contents_and_inode(self):
        output, binary, inode = self.old_release()
        self.icon()
        def fail(stage, *_):
            self.write(stage / 'partial', 'new incomplete build')
            self.write(stage.parent / 'gates/results.json', '{"passed":false}')
            self.write(stage.parent / 'gates/audio.log', 'specific failing assertion')
            raise ValueError('test compile failure')
        with patch.object(release, 'ROOT', self.root), patch.object(release, 'preflight', return_value={}), \
             patch.object(release, 'stage_release', side_effect=fail), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaisesRegex(ValueError, 'compile failure'):
                release.main(['--output', str(output)])
        self.assertEqual(binary.stat().st_ino, inode)
        self.assertEqual(binary.read_text(), 'previous executable')
        self.assertEqual(json.loads((output / 'size.json').read_text()), {'previous': True})
        self.assertFalse(list(self.root.glob('.release-staging-*')))
        failures = list((self.root / 'artifacts/release-failures').iterdir())
        self.assertEqual(len(failures), 1)
        self.assertEqual({p.name for p in failures[0].iterdir()}, {'failure.json', 'results.json', 'audio.log'})
        self.assertIn('specific failing assertion', (failures[0] / 'audio.log').read_text())

    def test_successful_promotion_uses_only_fresh_staging_files(self):
        output, _, old_inode = self.old_release()
        self.write(output / 'stale-resource', 'do not retain')
        staged = self.root / 'staged'
        new = self.write(staged / 'Ultralight.app/Contents/MacOS/Ultralight', 'verified')
        inode = new.stat().st_ino
        with contextlib.redirect_stderr(io.StringIO()):
            previous = release.promote(staged, output)
        self.assertEqual((output / 'Ultralight.app/Contents/MacOS/Ultralight').stat().st_ino, inode)
        self.assertFalse((output / 'stale-resource').exists())
        self.assertEqual((previous / 'Ultralight.app/Contents/MacOS/Ultralight').stat().st_ino, old_inode)
        self.assertEqual((previous / 'stale-resource').read_text(), 'do not retain')

    def test_missing_icon_fails_before_build(self):
        with patch.object(release, 'ROOT', self.root), patch.object(release, 'preflight') as preflight:
            with self.assertRaisesRegex(ValueError, 'Required release icon'):
                release.main(['--output', str(self.root / 'release')])
        preflight.assert_not_called()
        self.assertFalse((self.root / 'release').exists())

    def test_invalid_icon_is_rejected(self):
        self.write(self.root / 'Resources/AppIcon.icns', 'not an icon')
        with patch.object(release, 'ROOT', self.root):
            with self.assertRaisesRegex(ValueError, 'valid ICNS'):
                release.release_icon()

    def test_failure_archive_is_bounded_and_excludes_binaries(self):
        workspace = self.root / 'workspace'
        self.write(workspace / 'gates/compiler.log', 'x' * (2 * 1024 * 1024))
        self.write(workspace / 'gates/program', 'binary')
        self.write(workspace / 'release/Ultralight.app/Contents/MacOS/Ultralight', 'binary')
        failure = subprocess.CalledProcessError(1, ['compiler'], output='stdout', stderr='specific error')
        with patch.object(release, 'ROOT', self.root):
            saved = release.preserve_failure(workspace, failure)
        self.assertEqual({p.name for p in saved.iterdir()}, {'failure.json', 'compiler.log.tail.log', 'command.log'})
        self.assertEqual((saved / 'compiler.log.tail.log').stat().st_size, 1024 * 1024)
        self.assertIn('specific error', (saved / 'command.log').read_text())

    def test_failed_promotion_restores_same_previous_inode(self):
        output, binary, inode = self.old_release()
        staged = self.root / 'staged'; staged.mkdir()
        rename = Path.rename
        def fail_new(path, target):
            if path == staged:
                raise OSError('test rename failure')
            return rename(path, target)
        with patch.object(Path, 'rename', fail_new):
            with self.assertRaisesRegex(OSError, 'rename failure'):
                release.promote(staged, output)
        self.assertEqual(binary.stat().st_ino, inode)
        self.assertEqual(binary.read_text(), 'previous executable')

    def test_failed_rollback_retains_recoverable_previous_directory(self):
        output, _, inode = self.old_release()
        staged = self.root / 'staged'; staged.mkdir()
        rename = Path.rename
        def fail_new_and_restore(path, target):
            if path == staged or path.name.startswith('.release-previous-'):
                raise OSError('test filesystem failure')
            return rename(path, target)
        with patch.object(Path, 'rename', fail_new_and_restore):
            with self.assertRaisesRegex(RuntimeError, 'previous release is preserved'):
                release.promote(staged, output)
        saved = list(self.root.glob('.release-previous-*'))
        self.assertEqual(len(saved), 1)
        self.assertEqual((saved[0] / 'Ultralight.app/Contents/MacOS/Ultralight').stat().st_ino, inode)

    def test_unrelated_output_directory_is_never_replaced(self):
        output = self.root / 'unrelated'
        self.write(output / 'user-file', 'keep')
        with patch.object(release, 'preflight') as preflight, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                release.main(['--output', str(output)])
        preflight.assert_not_called()
        self.assertEqual((output / 'user-file').read_text(), 'keep')

    def test_notarization_requires_explicit_signing_and_dmg(self):
        for options in [[], ['--sign-identity', 'Developer ID Application: Test']]:
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                release.main(['--notary-profile', 'test-keychain-profile', *options])

    def test_all_budget_limits_remain_hard_in_public_signing_mode(self):
        for key in ['binary_bytes', 'app_bytes', 'dmg_bytes']:
            report = {'binary_bytes': 200000, 'app_bytes': 200000, 'dmg_bytes': 120000, 'signature': 'Developer ID'}
            report[key] += 1
            with self.subTest(key=key), self.assertRaises(ValueError):
                release.enforce_budgets(report)

    def test_source_zip_without_git_has_null_commit(self):
        with patch.object(release.subprocess, 'run', side_effect=FileNotFoundError('git')):
            self.assertIsNone(release.git_head())

    def test_source_zip_nested_in_another_repository_has_null_commit(self):
        result = subprocess.CompletedProcess([], 0, stdout=str(self.root))
        with patch.object(release.subprocess, 'run', return_value=result):
            self.assertIsNone(release.git_head())

    def test_version_format_is_validated(self):
        with patch.object(release, 'ROOT', self.root):
            self.write(self.root / 'VERSION', '2.2.0\n')
            self.assertEqual(release.version(), '2.2.0')
            self.write(self.root / 'VERSION', '2.2.0-rc1')
            with self.assertRaises(ValueError):
                release.version()

    def staged_build(self, *, invalid_gates=False, changing_source=False):
        self.write(self.root / 'VERSION', '2.2.0\n')
        self.write(self.root / 'Sources/main.swift', '// fixture')
        self.icon()
        workspace = self.root / 'workspace'; workspace.mkdir()
        stage = workspace / 'release'; stage.mkdir()
        snapshot = {'fixture': 'verified'}
        calls = []
        def command(*args):
            calls.append(args)
            if args[0] == sys.executable and args[1].endswith('/Scripts/check.py'):
                self.write(workspace / 'gates/results.json', json.dumps({
                    'passed': not invalid_gates, 'source_sha256': snapshot, 'flags': release.FLAGS}))
                self.write(workspace / 'gates/audio.log', 'all actual source gates passed')
            elif args[:2] == ('xcrun', 'swiftc'):
                self.write(Path(args[args.index('-o') + 1]), 'compiled test double')
            elif args[0] == sys.executable and args[1].endswith('/Tests/signing/verify.py'):
                return '{"passed":true}'
            elif args[0] == 'lipo':
                return 'arm64'
            return ''
        hashes = [snapshot, {'fixture': 'changed'}] if changing_source else [snapshot, snapshot]
        with patch.object(release, 'ROOT', self.root), patch.object(release, 'run', side_effect=command), \
             patch.object(release, 'source_hashes', side_effect=hashes), patch.object(release, 'git_head', return_value=None):
            report = release.stage_release(stage, workspace,
                SimpleNamespace(sign_identity='-', notary_profile=None, dmg=None), {'toolchain': 'test fixture'})
        return stage, report, calls

    def test_staged_bundle_records_version_icon_and_source_zip_provenance(self):
        stage, report, calls = self.staged_build()
        import plistlib
        info = plistlib.loads((stage / 'Ultralight.app/Contents/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleVersion'], '2.2.0')
        self.assertEqual(info['CFBundleShortVersionString'], '2.2.0')
        self.assertEqual(info['CFBundleIconFile'], 'AppIcon')
        self.assertIn('Contents/Resources/AppIcon.icns', report['files'])
        self.assertIsNone(report['git_head'])
        self.assertTrue((stage / 'gates/results.json').exists())
        self.assertEqual(report['app_bytes'], sum(item['bytes'] for item in report['files'].values()))
        self.assertTrue(any(args[0] == 'codesign' and '--signature-size' in args and '8' in args for args in calls))

    def test_failed_gate_report_prevents_compilation(self):
        with self.assertRaisesRegex(ValueError, 'after quality gates'):
            self.staged_build(invalid_gates=True)
        self.assertFalse((self.root / 'workspace/release/Ultralight.app').exists())

    def test_late_source_change_prevents_final_release_manifest(self):
        with self.assertRaisesRegex(ValueError, 'during release staging'):
            self.staged_build(changing_source=True)
        self.assertFalse((self.root / 'workspace/release/size.json').exists())

    def test_version_icon_generator_workflow_and_tooling_inputs_are_hashed(self):
        names = ['VERSION', 'Package.swift', 'Sources/test.swift', 'Scripts/icon.swift',
                 'Resources/AppIcon.icns', 'Tests/tooling/fixture.txt', '.github/workflows/check.yml']
        for name in names:
            self.write(self.root / name)
        self.write(self.root / 'Tests/tooling/__pycache__/ignored.pyc')
        with patch.object(build_config, 'ROOT', self.root):
            before = build_config.source_hashes()
            self.assertEqual(set(before), set(names))
            self.write(self.root / 'Resources/AppIcon.icns', 'new icon')
            self.assertNotEqual(before['Resources/AppIcon.icns'], build_config.source_hashes()['Resources/AppIcon.icns'])

    def test_preflight_rejects_unverified_architecture(self):
        with patch.object(build_config.platform, 'system', return_value='Darwin'), \
             patch.object(build_config.platform, 'machine', return_value='x86_64'):
            with self.assertRaisesRegex(RuntimeError, 'arm64'):
                build_config.preflight()

    def test_preflight_rejects_unverified_swift(self):
        result = subprocess.CompletedProcess([], 0, stdout='Apple Swift version 6.2.0')
        with patch.object(build_config.platform, 'system', return_value='Darwin'), \
             patch.object(build_config.platform, 'machine', return_value='arm64'), \
             patch.object(build_config.subprocess, 'run', return_value=result):
            with self.assertRaisesRegex(RuntimeError, '6.3.3'):
                build_config.preflight()

    def test_developer_id_mode_rejects_adhoc_identity(self):
        result = subprocess.CompletedProcess([], 0, stdout='', stderr='Signature=adhoc')
        with patch.object(signing.subprocess, 'run', return_value=result):
            with self.assertRaisesRegex(SystemExit, 'Developer ID'):
                signing.signing_policy(self.root, 'developer-id')

    def test_developer_id_mode_requires_hardened_runtime_and_timestamp(self):
        result = subprocess.CompletedProcess([], 0, stdout='', stderr='Authority=Developer ID Application: Test')
        with patch.object(signing.subprocess, 'run', return_value=result):
            with self.assertRaisesRegex(SystemExit, 'hardened runtime'):
                signing.signing_policy(self.root, 'developer-id')

    def test_rejected_notarization_cannot_be_promoted(self):
        with patch.object(release, 'run', return_value='{"status":"Invalid","id":"fixture"}'):
            with self.assertRaisesRegex(ValueError, 'not accepted'):
                release.notarize(self.root / 'app.zip', 'test-keychain-profile')

    def test_mounted_dmg_wrong_root_is_rejected_and_detached(self):
        calls = []
        def command(*args):
            calls.append(args)
            if args[:2] == ('hdiutil', 'attach'):
                mount = Path(args[args.index('-mountpoint') + 1])
                (mount / 'Contents').mkdir()
            return ''
        with patch.object(release, 'run', side_effect=command):
            with self.assertRaisesRegex(ValueError, 'at its root'):
                release.verify_dmg(self.root / 'fixture.dmg', {}, 'adhoc')
        self.assertEqual(calls[-1][:2], ('hdiutil', 'detach'))
        self.assertIn('-readonly', calls[1])
        self.assertIn('-noautoopen', calls[1])

    def test_mounted_dmg_changed_file_is_rejected_and_detached(self):
        calls = []
        expected_app = self.root / 'expected.app'
        self.write(expected_app / 'Contents/MacOS/Ultralight', 'expected')
        def command(*args):
            calls.append(args)
            if args[:2] == ('hdiutil', 'attach'):
                mount = Path(args[args.index('-mountpoint') + 1])
                self.write(mount / 'Ultralight.app/Contents/MacOS/Ultralight', 'wrong')
            return ''
        with patch.object(release, 'run', side_effect=command):
            with self.assertRaisesRegex(ValueError, 'exactly match'):
                release.verify_dmg(self.root / 'fixture.dmg', release.files_in(expected_app), 'adhoc')
        self.assertEqual(calls[-1][:2], ('hdiutil', 'detach'))


if __name__ == '__main__':
    unittest.main()
