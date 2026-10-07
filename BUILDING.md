# Building Ultralight

Ultralight uses Swift, AppKit, and the audio frameworks included with macOS. It has no third-party package dependencies. Use SwiftPM for development and the release script for a measured, verified app bundle. The release policy lives in [Scripts/build_config.py](Scripts/build_config.py); [ENGINEERING.md](ENGINEERING.md) explains the size decisions and their tradeoffs.

## Requirements

| Purpose | Requirement |
| --- | --- |
| Release target | Apple silicon (`arm64`), macOS 14.0 or later |
| Reference build environment | macOS 26.7, Xcode 26.6 (17F113), Apple Swift 6.3.3 |
| Python tooling | Python 3.9 or later; standard library only |
| Full native verification | A logged-in macOS desktop with an available audio output device |

The native compatibility fixture has passed on arm64 macOS 14.8.9 and 26.6.2 in hosted CI. The full release gates were run on the reference macOS 26.7 desktop. The [verification record](docs/evidence/README.md) describes each check and its scope.

The release script requires native Apple silicon and Apple Swift 6.3.3. Select the intended Xcode using `DEVELOPER_DIR` or `xcode-select`. A different compiler can change code generation, linker support, and artifact size.

The visual checks use fixed layout and bitmap scales, but rendering also depends on AppKit and system fonts. Run exact image comparisons on the reference desktop. Transport tests use zero output volume; offline continuity tests do not route audio to hardware. Test settings and generated audio are isolated from the music library.

## Development

Run from the repository root:

```sh
swift run Ultralight
```

To build the optimized SwiftPM executable:

```sh
swift build -c release -debug-info-format none --experimental-lto-mode full
```

Use SwiftPM's `--experimental-lto-mode full` option so its build plan handles LLVM bitcode correctly. Adding only `-lto=llvm-full` to the package manifest is not equivalent. The packaged release uses a single compiler invocation and measures the result after stripping and signing.

## Verify and package

Build the app and a compressed disk image:

```sh
python3 Scripts/release.py --dmg UDZO
```

This command runs all release gates, verifies that the source and build policy remain unchanged, then builds in a fresh staging directory. It strips and signs the app, checks the signature and memory layout, and measures the complete bundle. It also mounts the disk image read-only and verifies that every packaged file matches the app that passed validation.

Successful output is written to `artifacts/release/`. A failed run leaves the previous release intact. When a verified build replaces an existing release, the previous directory is retained separately so a running executable is not overwritten.

The release enforces these limits on the finished artifacts:

| Artifact | Maximum size |
| --- | ---: |
| Signed executable | 200,000 bytes |
| Complete app bundle | 200,000 bytes |
| Disk image | 120,000 bytes |

App size is the sum of regular-file lengths, including the icon, MIT license notice, bundle metadata, and signature. These are logical byte counts, not disk allocation or memory use. Source, tests, and documentation are excluded from the app. Developer ID signatures and notarization tickets count toward the same limits.

To run the release gates without packaging:

```sh
python3 Scripts/check.py
```

For the Python tooling tests alone, including failure handling and release rollback:

```sh
python3 -m unittest discover -s Tests/tooling -v
```

Each completed release contains `size.json`, compiler flags, source and artifact hashes, and the gate reports in `gates/`. Export the public evidence after a successful release build:

```sh
python3 Scripts/evidence.py
```

Use a clean Git checkout when preparing a named release. Source archives can also build: reports record no Git commit when repository history is unavailable, while retaining the full source hashes.

## Signing for distribution

The default release is ad-hoc signed for local use. Local signature verification does not establish Apple notarization or successful launch after download. **Developer ID signing, notarization, and launch under download quarantine have not yet been verified for 2.2.0.**

The release script supports that distribution flow. With a Developer ID Application identity and a stored notarization profile in the keychain, run:

```sh
python3 Scripts/release.py --dmg UDZO \
  --sign-identity 'Developer ID Application: YOUR NAME (TEAM ID)' \
  --notary-profile ultralight-notary
```

This path enables the hardened runtime and secure timestamps, submits the app and disk image to Apple's notarization service, staples accepted tickets, and verifies the finished artifacts. It measures the resulting signature and ticket overhead before accepting the release. The compact signature reservation used for ad-hoc builds does not apply to Developer ID signing.

Use a Developer ID Application identity, rather than an Apple Development certificate. Keep credentials in the keychain, not in source files or command arguments. Apple's [notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) covers identity and profile setup.

## CI and runtime compatibility

The [source workflow](.github/workflows/checks.yml) is configured to run the Python tooling tests, build from a fresh SwiftPM directory with Xcode 26.6, and compile a signed native compatibility fixture. Its macOS 14 and 26 jobs run the same compiled fixture, so the comparison does not depend on building with a different compiler on each OS. The [recorded hosted run](https://github.com/dungbeetlephoenix/ultralight-appkit/actions/runs/37575656934) passed all four jobs; its build inputs match the measured release.

The fixture exercises AppKit loading and drawing, Combine notifications, accessibility actions, icon decoding, native audio-file decoding, and asynchronous metadata loading without playing audio. It is a runtime smoke test. It does not replace the full release gates, exact image comparisons, or listening tests.

Build and run it locally with fresh bundle and output directories:

```sh
python3 Tests/compatibility/run.py build --bundle artifacts/compatibility
python3 Tests/compatibility/run.py run --bundle artifacts/compatibility \
  --output artifacts/compatibility-run --expect-os 26
```

To check another Mac, transfer the bundle unchanged and run it there with `--expect-os 14`. Each run validates the bundled file hashes and signature, and records the actual host OS and architecture. A successful run on macOS 26 does not establish macOS 14 compatibility.

The [desktop release workflow](.github/workflows/release-check.yml) provides a separate manual job for a trusted runner labelled `ultralight-desktop`. It requires the reference desktop environment and runs only from `main`; public pull requests do not execute on that runner. Runner provisioning and successful workflow execution must be verified separately from the configuration.

GitHub's [runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) documents the selected Xcode path. Its [macOS 14 retirement notice](https://github.com/actions/runner-images/issues/13518) schedules removal for November 2, 2026. Continued minimum-OS coverage will require a maintained macOS 14 runner after that date.

## Version and resources

[VERSION](VERSION) supplies both bundle version fields. Release tags use `vMAJOR.MINOR.PATCH` and identify the reviewed source commit; see the [version policy](CHANGELOG.md#version-policy).

The application icon is drawn from the vector instructions in [Scripts/icon.swift](Scripts/icon.swift). Regenerate its losslessly compressed 32- and 256-pixel representations with:

```sh
python3 Scripts/make_icon.py
```

The icon is included in source hashes and the app's size budget. Changes to resources, metadata, or signing require a new release build and measurement.
