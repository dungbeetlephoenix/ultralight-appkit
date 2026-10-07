# Build measurements and verification

This directory records the measured 2.2.0 build at source commit [`dbd42ad`](https://github.com/dungbeetlephoenix/ultralight-appkit/commit/dbd42ad2d873ab2ca0aa219466ef106cdbb05129). The complete app is **192,812 bytes** with an ad-hoc signature. Documentation changes after that commit do not alter the measured build inputs. A subsequent hosted run at `f8efb00` verifies the same inputs on additional macOS versions.

## Recorded results

| Check | Result |
| --- | --- |
| Native behavior | 779 assertions passed across audio, UI, playback, continuity, state, observation, binding, and drop fixtures |
| Release tooling | 53 tests passed, including failure paths and rollback |
| Allocation | Reusable FFT workspace meets the allocation gate |
| Visual comparison | Three reference screenshots match byte-for-byte |
| App integrity | Native signature, tamper checks, and executable-layout checks passed |
| Disk image | Mounted read-only; packaged app files and hashes match the verified bundle |
| SwiftPM | Fresh development and full-LTO release builds passed |
| Hosted CI | [All four jobs passed](https://github.com/dungbeetlephoenix/ultralight-appkit/actions/runs/37575656934): tooling, fresh build, and compatibility on macOS 14.8.9 and 26.6.2 |
| macOS 26.7 runtime | [11 compatibility checks passed](compatibility-macos-26.json) with the same source hashes as the measured release |

These results cover generated audio fixtures and the exercised interface and state paths. They are not a complete certification of codec support, audio hardware, or accessibility workflows.

## Distribution and compatibility status

The recorded build targets arm64 macOS 14.0. The identical signed compatibility fixture passed all 11 checks on both arm64 macOS 14.8.9 and 26.6.2. Developer ID signing, notarization, and a downloaded-app launch remain outstanding release checks. The measured artifact is intended for local use.

Hosted automation is tracked separately in [GitHub Actions](https://github.com/dungbeetlephoenix/ultralight-appkit/actions). The recorded hosted run uses the same source hashes as the measured release; its identical fixture-manifest hash on both OS versions is recorded in [compatibility-hosted.json](compatibility-hosted.json). The full release workflow requires a trusted desktop runner with audio output and a logged-in graphical session; it does not skip those gates when the environment is unavailable.

## Evidence files

| File | Contents |
| --- | --- |
| [release.json](release.json) | Exact sizes, app-file hashes, source/test/build input hashes, compiler flags, signature details, and gate outcomes |
| [history.json](history.json) | Earlier size measurements and available artifact hashes |
| [compatibility-hosted.json](compatibility-hosted.json) | Hosted run, compiler, common fixture hash, and macOS 14/26 runtime results |
| [compatibility-macos-26.json](compatibility-macos-26.json) | Runtime environment and individual compatibility results |
| [observation-comparison.json](observation-comparison.json) | Comparison of automatic and explicit Combine notifications: 343 assertions per implementation and 97 identical event traces |

The observation-comparison candidate differs from the measured `AppState` only by three explanatory comment lines. The release reruns the same observation contract as a mandatory gate.

## Reproducing the record

Follow [BUILDING.md](../../BUILDING.md) to produce a verified release, then export its public summary:

```sh
python3 Scripts/evidence.py
```

The exporter verifies current source hashes, the complete app inventory, and the disk-image hash before writing `release.json`. Full logs remain in the generated release directory. The app budget includes all resources and signature overhead; the disk-image budget includes the signed and stapled image when the public signing flow is used.
