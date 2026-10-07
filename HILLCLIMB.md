# Small by construction

Ultralight is a native music player with a strict constraint: the complete signed app must fit within 200,000 bytes. That includes the executable, icon, license, bundle metadata, and signature. The constraint is useful because it forces each abstraction and resource to earn its place.

The starting executable measured 325,664 bytes. Four optimization passes brought it to 183,280 bytes, with a 185,848-byte app bundle. The finishing pass adds keyboard and accessibility support, an icon, and release safeguards. Its measured result and exact build inputs are recorded in the [public evidence](docs/evidence/README.md).

| Artifact | Starting build | Before finishing | Finished local build |
| --- | ---: | ---: | ---: |
| Signed executable | 325,664 B | 183,280 B | **183,600 B** |
| Complete signed app | 328,232 B | 185,848 B | **192,812 B** |
| Compressed disk image | 127,671 B | 99,400 B | **106,770 B** |

The finished app has 7,188 bytes of headroom under its limit. The icon accounts for 5,063 bytes; the executable grew by 320 bytes while gaining the finishing changes.

These are logical file sizes on Apple silicon. They do not describe RAM use or filesystem allocation. The compressed download is measured separately, and a public signing certificate or notarization ticket counts toward the same app budget.

## Share the work

Most savings came from ordinary structure. Repeated AppKit construction now goes through a few small functions for constraints, labels, buttons, and panels. Each call still names the relationship it creates. Layout-only subclasses became plain views, with their subscriptions owned by the view's lifetime.

Persisted models share a string-backed coding key and primitive container helpers. Standard Codable remains responsible for parsing and type checking. The saved schema is unchanged, including required fields, Unicode keys, and Float rounding.

The scanner uses Foundation's native enumeration, canonical paths, and natural sorting. Metadata loading has one checked-continuation bridge to AVFoundation's asynchronous loader. It reads a property only after that property's load succeeds. The underlying KVL API is deprecated for Swift; the small bridge is deliberate and tested, and cancellation prevents further work and discards late results. It does not abort an in-flight AVFoundation request.

The spectrum and offline analyzer share an FFT implementation and reusable workspace. A scoped mutable-buffer borrow eliminated an accidental copy per transform. After warmup, 10,000 transforms perform zero intercepted allocation calls. The live callback retains one allocation for its returned spectrum array. Stereo channels contribute power separately, so opposing phases do not cancel the display.

## Respect the file layout

A smaller function does not always produce a smaller executable. Mach-O segments advance in 16 KiB pages on this build. A useful optimization may appear to save nothing until several changes cross the next boundary together.

The release uses full link-time optimization, compact native Objective-C stubs, and LLVM outlining to share repeated instructions. Apple's linker places selected immutable literals and relative method lists in constant-data space that dyld protects after fixups. Runtime type metadata, instructions, and unwind records stay in their expected sections. AppState sends object-change notifications explicitly, allowing release builds to omit reflection descriptors. Each of its fifteen published properties has a pre-mutation notification; adding a property without matching coverage fails the observation gate.

The layout guard verifies those section relationships, segment permissions, immutable method-list encoding, diagnostic records, and the read-only-after-fixup flag. This checks the file's loader contract; it is not a measurement of live VM-region permissions. Runtime smoke tests exercise the compiled result on each recorded OS.

Ad-hoc signatures contain no certificate chain. Asking Apple's signer for a minimal certificate reservation removes unused padding while retaining its native hashes and seals. Developer ID builds use ordinary certificate reservation, hardened runtime, and a timestamp, then face the same final size limit. There is no executable packer, custom Mach-O rewriter, or runtime unpacking step.

## Keep the player correct

The size work also exposed audio and state bugs. Queued tracks now use played-back completion events, preserve the playback timeline across pause and seek, and reject stale completions. Shuffle, repeat, rescanning, and removed folders keep the selected next track consistent. Background analysis cannot overwrite a later manual EQ change.

Waveforms include every channel, short clips, and the final partial read. Bypassing EQ also bypasses its preamp. The continuity fixture checks every sample across two queued stereo signals and the silence after them; it catches inserted gaps and extra tails.

The finishing pass gives controls native keyboard and accessibility behavior, keeps the Settings folder list current, and makes menu commands target the player explicitly. These are part of the product's quality budget, alongside file size.

## Make failure visible

Release checks cover audio, persistence, scanner behavior, state transitions, bindings, native drops, UI actions, allocation limits, and code signatures. Literal schema fixtures test compatibility independently of a matching encoder and decoder. Three renders from the preserved starting source remain the visual reference; candidate screenshots never replace those goldens.

The test runner invalidates old success reports before doing work. Missing image fixtures fail, timed-out test processes are stopped, and failed runs leave diagnostics. The builder uses a private gate report tied to the exact source hashes, stages a fresh app, and promotes it only after every gate passes. It mounts the disk image read-only and compares its payload to the verified app.

The repository includes a compact [measurement and gate record](docs/evidence/release.json). Full local logs are generated with each release. [BUILDING.md](BUILDING.md) explains how to reproduce the checks and which ones need a desktop session.

## Cuts that were not worth keeping

Simply removing reflection descriptors broke Combine's ObservableObject notifications. Explicit notifications initially saved too little to justify the added bookkeeping. After accessibility was added, that same change recovered a full file page. It was accepted only after the automatic and explicit implementations passed 343 assertions each and produced 97 identical event traces, including subscription order, nested edits, unchanged assignments, cancellation, and reentrant updates. This is a deliberate maintenance tradeoff; the property-coverage guard makes it visible.

Handwritten JSON initially looked attractive. Decimal midpoint fixtures exposed different Float rounding through NSNumber, and native dictionary keys had different Unicode equality behavior. Typed Codable stayed.

Custom Track copy-on-write storage reduced snapshot-copy cost but added an allocation per track and increased retained library memory in the measured fixture. It was unnecessary for the fourth-pass result. Other experiments—binary-table rewriting, custom event delivery, and denser layout tables—offered too little benefit for their maintenance cost.

## What the evidence establishes

The current results cover generated audio fixtures and the exercised UI and state paths on the recorded host. They do not prove every codec's gapless priming behavior, every Bluetooth or device-change sequence, or operation on an OS that has not run the compatibility fixture. Matching decoded sample rates and channel counts are required for continuous scheduling; other transitions use normal next-track playback.

The deployment target is macOS 14. That setting alone is not a successful macOS 14 runtime test. Public signing, notarization, and a downloaded-app launch are likewise separate from local ad-hoc verification. Their current status is explicit in the evidence record.

The result is the smallest acceptable build found by this search. Future changes must meet the same behavior checks and the same byte budget.
