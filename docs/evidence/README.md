# Verification record

`release.json` is a sanitized export of the completed local build. It records every production/test/build input hash, the compiler and flags, each app-file hash, exact sizes, and gate outcomes. Regenerate it with `python3 Scripts/evidence.py` after a successful release. [history.json](history.json) preserves the prior size measurements and available artifact hashes. Earlier engineering reports remain in Git history; reproducing the current build does not require the experimental scratch directories.

[observation-comparison.json](observation-comparison.json) records the independent comparison against automatic Combine notifications: 343 assertions passed on each implementation, with 97 identical event traces. The comparison candidate differs from the final AppState only by three explanatory comment lines. The current release reruns that observation contract as a mandatory gate.

## Scope

| Check | Status |
| --- | --- |
| Full local release gates, signed app, mounted disk-image payload | Passed: 779 native assertions, 53 tooling tests, allocation and signature/layout gates; 192,812-byte app |
| Fresh SwiftPM development and full-LTO builds | Passed in separate empty build directories |
| Native compatibility fixture on macOS 26.7 | [11 checks passed](compatibility-macos-26.json) with the same source hashes as the release |
| Same compiled fixture on macOS 14 | Pending; no local macOS 14 runtime available |
| Hosted CI workflows | Prepared; not run before source push |
| Developer ID signature and Apple notarization | Pending; no Developer ID identity available locally |
| Downloaded-app launch under quarantine | Pending public signing/distribution run |

The source workflow has a macOS 14 runtime job. Its configuration is not evidence that the job passed. The full release workflow needs a trusted desktop runner; it does not substitute skipped tests when audio or a GUI is unavailable.

The app-size limit includes all bundle resources and signature overhead. The download-size limit includes the final signed/stapled disk image when that public flow is used. A build exceeding either limit is rejected.
