"""Release policy shared by the shipping build and executable quality gates."""
import hashlib
import pathlib
import platform
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGET = 'arm64-apple-macosx14.0'
VERIFIED_SWIFT = '6.3.3'
SIGNATURE_CMS_RESERVE_BYTES = 8
# Selector references are fixed up at load time, then kept read-only by dyld.
# Packing them in DATA_CONST also avoids an otherwise mostly empty DATA page.
FLAGS = ['-swift-version', '5', '-Osize', '-whole-module-optimization', '-gnone',
         '-lto=llvm-full',
         '-Xfrontend', '-disable-reflection-metadata',
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
    files = [ROOT / 'Package.swift', ROOT / 'VERSION', ROOT / 'LICENSE',
             *sorted((ROOT / 'Sources').rglob('*.swift')),
             *[p for p in sorted((ROOT / 'Scripts').rglob('*'))
               if p.is_file() and '__pycache__' not in p.parts]]
    files += [p for p in sorted((ROOT / 'Tests').rglob('*')) if p.is_file()
              and 'runs' not in p.parts and '__pycache__' not in p.parts
              and (p.suffix in ('.swift', '.c', '.py', '.json', '.png')
                   or 'tooling' in p.relative_to(ROOT / 'Tests').parts)]
    icon = ROOT / 'Resources/AppIcon.icns'
    if icon.is_file():
        files.append(icon)
    workflows = ROOT / '.github/workflows'
    if workflows.is_dir():
        files += [p for p in sorted(workflows.rglob('*')) if p.is_file()]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}


def preflight():
    """The compact release policy is verified only for this native toolchain."""
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise RuntimeError('Release verification requires native Apple-silicon macOS (arm64); '
                           'Intel/Rosetta and other operating systems are not validated.')
    result = subprocess.run(['xcrun', 'swiftc', '--version'], capture_output=True, text=True, check=True)
    version = re.search(r'Apple Swift version (\d+\.\d+\.\d+)\b', result.stdout)
    if not version or version.group(1) != VERIFIED_SWIFT:
        raise RuntimeError('Release verification requires Apple Swift ' + VERIFIED_SWIFT +
                           '; select the verified Xcode with DEVELOPER_DIR or xcode-select. Found: ' +
                           result.stdout.strip())
    return {'toolchain': result.stdout.strip(), 'architecture': 'arm64',
            'macos': platform.mac_ver()[0], 'target': TARGET}
