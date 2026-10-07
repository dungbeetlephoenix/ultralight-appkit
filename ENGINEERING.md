# Engineering Ultralight

Ultralight explores how much functionality a small native application can retain within a strict size budget. The complete app must fit within 200,000 bytes, including the executable, icon, license, bundle metadata, and code signature. Audio correctness, usable controls, and reproducible checks are part of that constraint.

## Results

| Artifact | Baseline | Current measured build |
| --- | ---: | ---: |
| Signed executable | 325,664 bytes | **183,600 bytes** |
| Complete app bundle | 328,232 bytes | **192,812 bytes** |
| Compressed disk image | 127,671 bytes | **106,770 bytes** |

The app bundle is 41% smaller than the baseline, with 7,188 bytes remaining under its limit. It includes a 5,063-byte icon and native keyboard and accessibility support. The [measurement history](docs/evidence/history.json) records the intermediate builds.

These figures describe logical file sizes for an Apple silicon build with Apple Swift 6.3.3. They are not measurements of memory use or disk allocation. The recorded signature is ad-hoc; Developer ID certificates and notarization tickets must be included in any future public-release measurement.

## Architecture

Ultralight uses system frameworks for its major responsibilities:

| Component | Implementation |
| --- | --- |
| Interface | AppKit views, Auto Layout, and custom drawing |
| Playback and equalization | AVFoundation audio engine and an eight-band equalizer |
| Spectrum and offline analysis | Accelerate FFT routines with shared workspace |
| State updates | Combine publishers and subscriptions owned by view lifetimes |
| Library and persistence | Foundation enumeration and Codable; AVFoundation metadata loading |

The source follows those boundaries:

```text
Sources/Ultralight/
├── App/       Application lifecycle, state, and bindings
├── Audio/     Playback, analysis, FFT, and track identification
├── Models/    Track, EQ, and analysis data
├── Scanner/   Folder enumeration and metadata loading
├── Storage/   Preferences, EQ profiles, and analysis cache
├── System/    Media keys and menu-bar integration
└── Views/     Player, library, equalizer, and settings
```

## Reducing duplication

Repeated view construction is handled by small functions for constraints, labels, buttons, and panels. Call sites still express the relationships they create. Views that needed only layout became ordinary AppKit views, with subscription storage retained for the lifetime of each view.

Persisted models share a string-backed coding key and primitive container helpers. Standard Codable continues to parse and validate the data. Independent schema fixtures cover required fields, Unicode keys, and Float rounding so a smaller implementation cannot silently change existing files.

The scanner uses native file enumeration, canonical paths, and natural sorting. A single checked-continuation bridge handles AVFoundation's asynchronous metadata loader, reading each value only after its load succeeds. The underlying key-value-loading API is deprecated in Swift; retaining this small bridge is an explicit compatibility and maintenance tradeoff. Cancellation stops subsequent work and discards late results, but does not abort an in-flight AVFoundation request.

## Audio work and allocation

The live spectrum and offline analyzer share an FFT implementation and reusable workspace. A scoped mutable-buffer borrow removes an accidental copy on every transform. After warmup, the allocation fixture observes zero intercepted allocation calls across 10,000 transforms. The live callback still allocates its returned spectrum array once per result.

Stereo channels contribute power separately, preventing opposing phases from cancelling the display. Waveform analysis includes every channel, short clips, and the final partial read. EQ bypass also bypasses the preamp.

Playback uses played-back completion events and retains its timeline across pause and seek. Stale completions cannot advance a newer playback session. Shuffle, repeat, rescans, and folder removal update the queued selection. Background analysis preserves non-flat EQ adjustments and saved per-track profiles.

Continuous scheduling requires matching decoded sample rates and channel counts. The continuity fixture compares every sample across two queued stereo signals and the silence after them. This verifies the scheduling path; it does not establish gapless priming behavior for every compressed codec.

## Compiler and executable layout

The release build uses size optimization, whole-module optimization, full link-time optimization, compact Objective-C stubs, and LLVM outlining. The complete flags and compiler version are recorded in [release.json](docs/evidence/release.json).

Mach-O segments advance in 16 KiB pages in this build. Several small reductions can therefore be necessary before the executable loses a full page. File size is measured after linking, stripping, signing, and bundling.

Apple's linker places selected immutable literals and relative Objective-C method lists in constant-data space that dyld protects after fixups. Runtime type metadata, executable instructions, and unwind records remain in their expected sections. A layout check verifies section relationships, segment permissions, relative method-list encoding, diagnostic records, and the read-only-after-fixup flag. This verifies the file's loader contract; it does not measure live virtual-memory permissions.

The ad-hoc signature uses a minimal certificate reservation because it contains no certificate chain. Apple's signer still produces the hashes and resource seal. Developer ID builds use ordinary certificate reservation, the hardened runtime, and a timestamp. Both paths are subject to the same final byte budget.

## Explicit observation

Omitting reflection descriptors initially broke Combine's automatic object-change notifications. The accepted implementation gives `AppState` an explicit publisher and sends a pre-mutation notification for each of its fifteen published properties. This recovered one file page while retaining native Combine delivery.

The automatic and explicit implementations each passed 343 assertions and produced 97 identical event traces. Coverage includes subscription order, unchanged assignments, nested mutations, cancellation, lifetime, and reentrant updates. A mandatory coverage check rejects a new published property without its notification and fixture.

This approach adds maintenance responsibility. The comparison record and coverage guard make that responsibility explicit; see [observation-comparison.json](docs/evidence/observation-comparison.json).

## Approaches rejected

Handwritten JSON reduced some code, but decimal midpoint fixtures exposed different Float rounding through NSNumber, and native dictionary keys behaved differently for Unicode equality. Typed Codable was retained.

Custom copy-on-write storage for tracks reduced snapshot-copy cost but added an allocation per track and increased retained library memory in the measured fixture. The size target was achievable with an ordinary struct. Binary-table rewriting, custom event delivery, and denser layout tables likewise offered too little benefit for their maintenance cost.

## Verification and release integrity

The recorded build passes 779 native assertions and 53 tooling tests, plus allocation, signature, executable-layout, and mounted-image checks. Three screenshots preserved from the baseline remain the visual reference. Candidate renders cannot replace them during verification.

The runner invalidates old success reports before starting. Missing fixtures fail the run; timed-out test processes are stopped and leave diagnostics. Each release uses a private gate report tied to its source hashes, builds in a fresh staging directory, and replaces the previous output only after all checks pass. The disk image is mounted read-only and its app is compared with the verified bundle.

The [verification record](docs/evidence/README.md) separates local results from outstanding checks. The macOS 14 deployment target still requires a successful runtime check on that OS. Public signing, notarization, and a downloaded-app launch also require their own recorded results. Device changes, Bluetooth behavior, and codec-specific edge cases extend beyond the current fixtures.

See [BUILDING.md](BUILDING.md) to reproduce the build and its checks.
