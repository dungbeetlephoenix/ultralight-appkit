# Building Ultralight

Ultralight has no package dependencies. Development uses SwiftPM; the measured release uses one compiler invocation with the policy in `Scripts/build_config.py`.

## Environments

| Purpose | Environment |
| --- | --- |
| Measured release | Apple silicon, macOS 26.7, Xcode 26.6 (17F113), Apple Swift 6.3.3 |
| Deployment target | macOS 14.0, arm64 |
| Tooling tests | Python 3.9 or later, standard library only |
| Full native gates | A logged-in macOS desktop with an available audio output device |

The UI fixtures fix layout and bitmap scales, but fonts and AppKit still depend on the OS. Exact image comparisons belong on the reference desktop. The audio transport checks use zero output volume; offline continuity checks never route audio to hardware. All test settings and generated music are isolated from your library.

The release script checks the compiler and architecture before building. Choosing another Xcode may change generated code, accepted linker flags, and artifact size. The 200,000-byte limit is enforced on the actual signed result.

## Development

```sh
swift run Ultralight
```

For a clean SwiftPM release comparison:

```sh
swift build -c release -debug-info-format none --experimental-lto-mode full
```

SwiftPM needs its own LTO switch so it expects bitcode correctly. Do not substitute `-num-threads 0` or put only `-lto=llvm-full` in the manifest: both have produced missing-object failures in clean builds.

## Verification and release

```sh
python3 -m unittest discover -s Tests/tooling -v
python3 Scripts/check.py
python3 Scripts/release.py --dmg UDZO
```

`check.py` runs the executable and tooling tests. `release.py` reruns those gates against a snapshot of the source hashes, then builds into a fresh staging directory. It strips and signs the app, checks its seal and memory-layout contract, measures every bundle file, creates the disk image, and mounts it read-only to compare the packaged app. Only a completely verified result replaces the previous release directory. The old directory is preserved so a running executable is not overwritten in place.

The limits are 200,000 bytes for the executable, 200,000 bytes for all regular files in the app bundle, and 120,000 bytes for the disk image. These are logical file sizes, not disk allocation or RAM use. Resources, the bundled MIT notice, metadata, and signature bytes count. Source, tests, and documentation do not ship in the app.

Each release includes `size.json`, source and file hashes, compiler flags, and its own `gates/` reports. Export the public summary after the final source build:

```sh
python3 Scripts/evidence.py
```

A source archive without Git history can still build; its report records no Git commit and retains the complete source hashes. Git checkouts should be clean when preparing a named release.

## Public signing

The default build uses native ad-hoc signing. It is suitable for local development and measurement. The small certificate reservation used in that mode is not used for Developer ID signatures.

With a Developer ID Application identity and a notarization profile already available in your keychain:

```sh
python3 Scripts/release.py --dmg UDZO \
  --sign-identity 'Developer ID Application: YOUR NAME (TEAM ID)' \
  --notary-profile ultralight-notary
```

The public flow uses the hardened runtime, secure timestamp, native signature validation, Apple's notarization service, and stapling. It verifies the finished result and remeasures the overhead under the same byte limits. Do not put signing passwords in source files or command arguments. See [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) for creating the keychain profile.

A development certificate is not a Developer ID Application identity. The current local environment has no Developer ID identity, so the public-signing flow has not been exercised against Apple's service. An ad-hoc signature passing local verification does not establish notarization or a successful downloaded-app launch.

## CI and minimum-OS checks

The source workflow runs Python failure-path tests, performs a fresh SwiftPM build with Xcode 26.6, and compiles a signed native compatibility fixture. That exact fixture is then run on macOS 14 and 26. It checks loading, AppKit drawing, Combine, native accessibility actions, icon decoding, native audio-file decoding, and asynchronous metadata without playing audio. It is a runtime smoke test, not a substitute for the full release gates or listening tests.

To reproduce the fixture locally:

```sh
python3 Tests/compatibility/run.py build --bundle artifacts/compatibility
python3 Tests/compatibility/run.py run --bundle artifacts/compatibility \
  --output artifacts/compatibility-run --expect-os 26
```

Use fresh output directories. Transfer the bundle unchanged to a second Mac and run the same command there with `--expect-os 14`. Each run checks its bundle hashes and signature, and records the actual host OS and architecture.

Exact visual and audio gates have a separate manual workflow for a trusted desktop runner labelled `ultralight-desktop`. It runs only from `main`; public pull requests never execute on that personal runner. Provisioning that runner and executing the hosted workflows are separate from committing their configuration.

GitHub's [macOS runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) supplies the Xcode path. Its [macOS 14 retirement notice](https://github.com/actions/runner-images/issues/13518) schedules removal for November 2, 2026. Replace that hosted runtime job with a maintained macOS 14 machine before retirement; removing the check does not establish compatibility.

## Resources and versioning

`VERSION` supplies the bundle version. Release tags use `vMAJOR.MINOR.PATCH` and refer to the reviewed source commit. Follow the [changelog's release policy](CHANGELOG.md#version-policy).

The original icon is drawn from the vector instructions in `Scripts/icon.swift`. Regenerate its losslessly compressed 32- and 256-pixel representations with:

```sh
python3 Scripts/make_icon.py
```

The icon resource is included in source hashes and the bundle's byte budget. Changing it requires a new release measurement.
