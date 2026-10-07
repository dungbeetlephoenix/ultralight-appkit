"""Evidence export must reject payload/size drift, without native tool calls."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'Scripts'))
spec = importlib.util.spec_from_file_location('release_evidence_audit', ROOT / 'Scripts/evidence.py')
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='ultralight-evidence-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.release = self.root / 'release'
        self.app = self.release / 'Ultralight.app'
        code = self.app / 'Contents/MacOS/Ultralight'
        code.parent.mkdir(parents=True)
        code.write_bytes(b'verified-code')
        (self.app / 'Contents/Info.plist').write_bytes(b'fixture-plist')
        (self.release / 'gates').mkdir()
        self.sources = {'input.swift': 'verified-input'}
        self.report = {'source_sha256': self.sources, 'files': evidence.files_in(self.app),
                       'binary_bytes': code.stat().st_size,
                       'app_bytes': sum(p.stat().st_size for p in self.app.rglob('*') if p.is_file()),
                       'version': '2.2.0', 'private_profile': 'must not escape', 'local_directory': '/private/fixture'}
        gates = {'passed': True, 'source_stable': True, 'source_sha256': self.sources, 'suites': {'audio': 0}}
        (self.release / 'gates/results.json').write_text(json.dumps(gates))
        (self.release / 'gates/audio.log').write_text('RESULT 186 passed; 0 failed\nprivate scratch directory\n')
        self.output = self.root / 'public.json'

    def export(self):
        (self.release / 'size.json').write_text(json.dumps(self.report))
        with patch.object(sys, 'argv', ['evidence.py', '--release', str(self.release), '--output', str(self.output)]), \
             patch.object(evidence, 'source_hashes', return_value=self.sources), contextlib.redirect_stdout(io.StringIO()):
            evidence.main()

    def test_valid_evidence_contains_only_selected_public_fields(self):
        self.export()
        exported = json.loads(self.output.read_text())
        self.assertEqual(exported['files'], self.report['files'])
        self.assertEqual(exported['assertion_summaries']['audio'], ['RESULT 186 passed; 0 failed'])
        self.assertNotIn('private_profile', exported)
        self.assertNotIn('local_directory', exported)

    def test_unrecorded_bundle_file_is_rejected(self):
        (self.app / 'Contents/unrecorded-resource').write_bytes(b'extra')
        with self.assertRaisesRegex(SystemExit, 'inventory or file content'):
            self.export()
        self.assertFalse(self.output.exists())

    def test_same_size_modified_executable_is_rejected(self):
        (self.app / 'Contents/MacOS/Ultralight').write_bytes(b'altered-code!')
        with self.assertRaisesRegex(SystemExit, 'inventory or file content'):
            self.export()

    def test_wrong_total_app_size_is_rejected(self):
        self.report['app_bytes'] += 1
        with self.assertRaisesRegex(SystemExit, 'app size'):
            self.export()

    def test_wrong_executable_size_is_rejected(self):
        self.report['binary_bytes'] += 1
        with self.assertRaisesRegex(SystemExit, 'executable size'):
            self.export()

    def test_dmg_size_must_match_even_if_hash_is_unchanged(self):
        data = b'disk image fixture'
        (self.release / 'Ultralight.dmg').write_bytes(data)
        self.report.update(dmg_sha256=hashlib.sha256(data).hexdigest(), dmg_bytes=len(data) + 1)
        with self.assertRaisesRegex(SystemExit, 'disk image changed'):
            self.export()
