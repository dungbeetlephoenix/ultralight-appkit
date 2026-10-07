# AppKit filesize hillclimb — 2026-10-06

Two measured passes make the executable 17.18% smaller while repairing the existing gapless and waveform implementations. The second pass removes another 16,896 executable bytes and 5,942 download bytes from the first result. All production features remain. The original checkout and installed applications were preserved; this work lives on `codex/hillclimb-2026-10-06`.

## Measured result

Apple silicon, Apple Swift 6.3.3, macOS 14 deployment target. These are logical file bytes, not filesystem allocation or RAM usage.

| Artifact | Starting version | First pass | Second pass | Total reduction |
| --- | ---: | ---: | ---: | ---: |
| Signed executable | 325,664 | 286,608 | 269,712 | 17.18% |
| Signed app payload | 328,232 | 289,176 | 272,280 | 17.05% |
| UDZO download | 127,671 | 122,172 | 116,230 | 8.96% |

The starting source is commit `b960fa0`, which preserves all six pre-existing modified files from the original checkout. Both measurements use the current compiler, identical app metadata, ad-hoc signing, and identical maximum-zlib UDZO packaging. The starting executable uses its original SwiftPM release/strip recipe; the candidate includes the build-process improvements below. The old README's 285 KB claim was not used as a benchmark.

Exact source/build/file hashes are recorded in `artifacts/release/size.json` for code commit `ac96513`; baseline measurements are in `artifacts/baseline/size.json` and the first-pass artifact is preserved in `artifacts/round1`. Compressed image size can vary slightly with image metadata. The first-pass app was launched and inspected; the second-pass release passed the native rendering/action harness. Its existing listening session was left running rather than interrupted for a restart. No installed app was replaced.

## Engineering changes retained

- Compile the complete dependency-free app in one invocation so LLVM sees a single module. A fresh SwiftPM experiment with `-enable-single-module-llvm-emission` independently confirmed the same improvement. Development remains available through SwiftPM. No source files or features are omitted.
- Remove unused Track Codable/Hashable/Identifiable and model Hashable conformances. Persisted EQ, analysis, and configuration formats retain Codable.
- Share the deferred main-runloop subscription implementation behind `@inline(never)`. Deferral remains essential because `@Published` emits before storing its new value.
- Remove reflection names while retaining type metadata and functioning ObservableObject notifications. Strip the nlist/string tables with Apple's documented `strip -N`, then sign and verify the actual result.
- Share a reusable FFT plan between offline analysis and the live spectrum. Its first-pass isolated cost was 144 bytes. The second pass caught a remaining copy-on-write allocation: passing the power array as both input and inout output copied it per FFT. One scoped mutable-buffer borrow fixes this while retaining managed arrays. Short and non-power-of-two input buffers are handled explicitly; channel power is combined without stereo phase cancellation.
- Store waveform peaks with bounded 16,384-frame reads across all channels, including short clips and final remainder frames.
- Use played-back completion callbacks and generation checks for queued audio. Preserve the player sample timeline across pause and queued transitions, carry seek offsets correctly, and reject stale callbacks after switches/stops.
- Keep the selected upcoming track consistent through shuffle, repeat, seeking, format fallback, rescanning, and folder removal. Cancel stale scan/analysis/waveform work before publishing results.
- Bypass the complete EQ unit, including preamp. Preserve saved manual EQ settings when background analysis completes.
- Deduplicate overlapping library roots, preserve remaining nested roots, and distinguish tracks by their paths while retaining shared content hashes for EQ migration.

The second pass also retains:

- Shared AppKit construction for repeated constraints, controls, fonts, layers, and stack layouts. This removes 6,656 bytes of actual text content in the isolated experiment. Original constraint attributes, action wiring, and appearance remain intact.
- One string-backed CodingKey implementation shared across persisted models. Standard Codable still performs typed encoding/decoding; field names and required-field behavior remain unchanged. This removes roughly 3.5 KB of repeated code. Literal fixtures independently verify compatibility with the original synthesized Codable.
- Direct property observers for volume, EQ, and queue policy, replacing AppState's subscriptions to itself. Nested EQ edits still publish and reach the engine. AppState mutations remain on the main thread. Reassigning unchanged shuffle/repeat values preserves the scheduled audio.
- Idempotent explicit media play/pause commands. A repeated pause can no longer resume playback.
- Correct ownership of CoreAudio device-name results with Unmanaged and takeRetainedValue. The SDK explicitly assigns the returned CFString to the caller. Device IDs/names matched over 100 repeated silent scans, and the unsafe-pointer warning is eliminated.

Isolated size savings are not additive: Mach-O segments move in 16 KB steps, and optimizations interact. We kept the shared FFT despite its small isolated growth because it improves correctness and allocation behavior.

## Quality gates

The final release runs 350 assertions with zero failures, plus the calibrated allocation gate:

| Suite | Assertions | Evidence |
| --- | ---: | --- |
| Analysis, FFT, waveform, persistence, file hashes, scanner | 180 | `artifacts/gates/audio.log` |
| Native UI actions, bindings, layouts | 67 | `artifacts/gates/ui.log` |
| Actual audio-engine playback/queue state | 54 | `artifacts/gates/playback.log` |
| Offline sample continuity and complete EQ bypass | 8 | `artifacts/gates/continuity.log` |
| Delayed asynchronous state transitions and controls | 27 | `artifacts/gates/state.log` |
| Deferred binding order, cancellation, threading, lifetime | 14 | `artifacts/gates/binding.log` |
| Calibrated kernel/live allocation limits | Separate gate | `artifacts/gates/allocation.log` |

All executable gates are compiled with the release optimization policy, stripped with `-N`, and ad-hoc signed before execution. Tests use isolated settings and generated audio. Realtime transport checks set output volume to zero. Offline continuity renders at unity gain without connecting playback to hardware.

The continuity fixture renders exactly 22,050 stereo frames at +0.25, followed by 26,460 frames at -0.25, followed by silence: zero wrong samples, zero inserted silent frames, zero extra tail samples. It also verifies that a nonflat EQ and +6 dB preamp remain fully bypassed.

The second pass adds 85 schema checks, including exact key/value fixtures for every persisted field, seven distinct analysis-flag patterns, missing/wrong-type rejection, unknown-field tolerance, and saved dictionary compatibility. All 85 also pass against untouched first-pass models. This avoids relying only on a candidate encoder and decoder agreeing with each other.

After warmup, 10,000 FFT transforms perform zero intercepted allocation calls, down from 10,000. The actual stereo spectrum callback performs 10,000 allocations across 10,000 calls, down from 30,000; one output array remains per callback. The guard calibrates interception, requires positive finite power and all output callbacks, and demonstrably rejects the old implementation. It counts malloc/calloc/realloc/posix_memalign on the calling thread; it does not prove the absence of locks or allocations through unrelated APIs.

A dedicated regression blocks the main runloop across a queued boundary, pauses before the completion is delivered, then verifies that the paused clock belongs to the new track. Delayed-service tests exercise A→B→A waveform races, cancellation on stop, queue policy changes, and removed-folder scans.

Three UI renderings compare byte-for-byte against the original source at a fixed 2× bitmap scale. The expected images were regenerated from `b960fa0` with the deterministic capture harness, never from the candidate. Provenance is in `Tests/ui/baseline/provenance.json`.

The release command verifies that the source and test hashes match the successful gate report before and after compilation. Size budgets are enforced after stripping/signing: executable 272,000 bytes, app payload 275,000 bytes, compressed download 120,000 bytes. A normal SwiftPM development build also passed.

## Experiments rejected

- Removing all reflection metadata: broke real AppState `objectWillChange` notifications even though direct property publishers still passed. Rejected on a failing gate.
- Full/thin LTO, CMO variants, array-based cancellables, type-erased subscription helpers, and alternative sorting: no useful additional size win in matched experiments.
- Additional LLVM outlining briefly saved a 16 KB page with the model changes alone. After combining all source improvements, the ordinary compiler policy produced a 269,680-byte bare signed executable versus 269,968 with those flags. The final bundled executable is 269,712 bytes because bundle signing differs. Extra LLVM flags were rejected.
- Custom Track copy-on-write storage: no additional artifact saving after the other improvements; ordinary struct semantics retained.
- Reimplementing Combine delivery with a RunLoop helper: passed 14 differential semantics checks but added about 2.7 KB of text/metadata. Original Combine helper retained.
- Raw FFT workspace, C hashing, and consolidated scanner/analyzer rewrites: negligible artifact savings for additional complexity. Safe arrays and the minimal FFT fix won.
- Packed layout tables: little or no further saving and less readable than shared construction functions.
- Handwritten Foundation JSON persistence: only about 1.7 KB saved for roughly 100 extra lines of schema logic. Codable retained.
- `-num-threads 0` with SwiftPM: a fresh build fails on missing per-source objects. Reused build folders can conceal this with stale objects. Rejected.
- UDBZ and ULFO disk images: larger than maximum-zlib UDZO for this app. No custom loader, executable compression stub, or runtime unpacking was added.
- No unchecked optimization or removal of bounds checks, unwind information, Objective-C selectors, or runtime safety checks.

## Scope and limits

The tests cover synthetic PCM and the exercised state/UI paths on this Mac. They do not establish listening-test results, every compressed codec's priming behavior, Bluetooth/device-switch behavior, or operation on every supported macOS version. Gapless scheduling is supported for matching decoded sample rates and channel counts; mismatched formats use normal next-track playback.

The existing UI still reserves the EQ column when hidden; this was deliberately retained and recorded in the visual baseline. This pass targets compactness and audio/state correctness, not a redesign. The app is ad-hoc signed for local use and is not notarized.

This is the smallest candidate found in this measured search, not a claim of a theoretical minimum. The gates and byte budgets make the next iteration measurable. Supporting second-pass measurements and before/after allocation logs are preserved in `artifacts/round2-evidence`.
