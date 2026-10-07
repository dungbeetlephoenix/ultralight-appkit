"""Release policy shared by the shipping build and executable quality gates."""
import hashlib
import pathlib
import platform

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGET = platform.machine() + '-apple-macosx14.0'
SIGNATURE_CMS_RESERVE_BYTES = 8
# Selector references are fixed up at load time, then kept read-only by dyld.
# Packing them in DATA_CONST also avoids an otherwise mostly empty DATA page.
FLAGS = ['-swift-version', '5', '-Osize', '-whole-module-optimization', '-gnone',
         '-lto=llvm-full',
         '-Xfrontend', '-disable-reflection-names',
         '-Xlinker', '-const_selrefs',
         '-Xlinker', '-objc_stubs_small',
         '-Xlinker', '-mllvm', '-Xlinker', '-enable-linkonceodr-outlining',
         '-Xlinker', '-mllvm', '-Xlinker', '-machine-outliner-reruns=1',
         '-Xlinker', '-dead_strip', '-Xlinker', '-x']
# Pack immutable literals and relative Objective-C method lists into constant
# data, protected after fixups. Keep all
# runtime-discovered Swift sections, executable code, and unwind tables in TEXT.
for original, packed in [('__const', '__text_const'), ('__cstring', '__cstring'),
                         ('__objc_classname', '__objc_classname'),
                         ('__objc_methlist', '__objc_methlist')]:
    for argument in ['-rename_section', '__TEXT', original, '__DATA_CONST', packed]:
        FLAGS += ['-Xlinker', argument]


def source_hashes():
    files = [ROOT / 'Package.swift', *sorted((ROOT / 'Sources').rglob('*.swift')),
             *sorted((ROOT / 'Scripts').glob('*.py'))]
    files += [p for p in sorted((ROOT / 'Tests').rglob('*')) if p.is_file()
              and 'runs' not in p.parts and p.suffix in ('.swift', '.c', '.py', '.json', '.png')]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
