"""Portable failure probes for signed compatibility fixtures; no native execution."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('compatibility_audit_runner', ROOT / 'Tests/compatibility/run.py')
compatibility = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compatibility)


class CompatibilityTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='ultralight-compat-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bundle = self.root / 'bundle'; self.bundle.mkdir()
        for name in ['smoke', 'AppIcon.icns']:
            (self.bundle / name).write_bytes(name.encode())
        manifest = {'files': {name: compatibility.digest(self.bundle / name) for name in ['smoke', 'AppIcon.icns']}}
        (self.bundle / 'manifest.json').write_text(json.dumps(manifest))
        self.output = self.root / 'runtime'

    def fake_runtime(self, checks=None, exit_code=0):
        def run(command, **kwargs):
            if command[0] == str(self.bundle / 'smoke') and checks is not None:
                (self.output / 'results.json').write_text(json.dumps(checks))
            return subprocess.CompletedProcess(command, exit_code if command[0] == str(self.bundle / 'smoke') else 0)
        with patch.object(compatibility.subprocess, 'run', side_effect=run), \
             patch.object(compatibility.platform, 'mac_ver', return_value=('14.8', ('', '', ''), '')), \
             patch.object(compatibility.platform, 'machine', return_value='arm64'), contextlib.redirect_stdout(io.StringIO()):
            compatibility.run(self.bundle, self.output, '14')

    def test_zero_exit_without_result_report_is_failure(self):
        with self.assertRaisesRegex(SystemExit, 'smoke failed'):
            self.fake_runtime()
        report = json.loads((self.output / 'runtime.json').read_text())
        self.assertEqual(report['exit_code'], 0)
        self.assertFalse(report['passed'])

    def test_zero_exit_with_empty_checks_is_failure(self):
        with self.assertRaisesRegex(SystemExit, 'smoke failed'):
            self.fake_runtime({'passed': True, 'checks': []})
        self.assertFalse(json.loads((self.output / 'runtime.json').read_text())['passed'])

    def test_zero_exit_with_failed_check_is_failure(self):
        with self.assertRaisesRegex(SystemExit, 'smoke failed'):
            self.fake_runtime({'passed': True, 'checks': [{'name': 'fixture', 'pass': False}]})

    def test_success_requires_exit_and_actual_passing_checks(self):
        self.fake_runtime({'passed': True, 'checks': [{'name': 'fixture', 'pass': True}]})
        self.assertTrue(json.loads((self.output / 'runtime.json').read_text())['passed'])

    def test_source_change_during_compilation_prevents_manifest(self):
        source = self.root / 'source'
        config = source / 'Sources/Ultralight/Storage/ConfigStore.swift'
        config.parent.mkdir(parents=True)
        config.write_text('let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!')
        (source / 'Resources').mkdir()
        (source / 'Resources/AppIcon.icns').write_bytes(b'fixture icon')
        output = self.root / 'new-bundle'
        def command(args, **kwargs):
            if args[:2] == ['xcrun', 'swiftc']:
                Path(args[args.index('-o') + 1]).write_bytes(b'compiled fixture')
            return subprocess.CompletedProcess(args, 0)
        with patch.object(compatibility, 'ROOT', source), \
             patch.object(compatibility, 'source_hashes', side_effect=[{'input': 'before'}, {'input': 'after'}]), \
             patch.object(compatibility.subprocess, 'run', side_effect=command):
            with self.assertRaisesRegex(SystemExit, 'Source changed'):
                compatibility.build(output)
        self.assertFalse((output / 'manifest.json').exists())
