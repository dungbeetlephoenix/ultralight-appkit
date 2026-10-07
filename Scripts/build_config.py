"""Release policy shared by the shipping build and executable quality gates."""
import hashlib
import pathlib
import platform

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGET = platform.machine() + '-apple-macosx14.0'
FLAGS = ['-swift-version', '5', '-Osize', '-whole-module-optimization', '-gnone',
         '-Xfrontend', '-disable-reflection-names',
         '-Xlinker', '-dead_strip', '-Xlinker', '-x']


def source_hashes():
    files = [ROOT / 'Package.swift', *sorted((ROOT / 'Sources').rglob('*.swift')),
             *sorted((ROOT / 'Scripts').glob('*.py'))]
    files += [p for p in sorted((ROOT / 'Tests').rglob('*')) if p.is_file()
              and 'runs' not in p.parts and p.suffix in ('.swift', '.c', '.py', '.json', '.png')]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
