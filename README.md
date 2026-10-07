# ULTRALIGHT

![Ultralight](screenshot.png)

A 269.7 KB native macOS music player (272.3 KB signed app; 116.2 KB download in the verified Apple-silicon build). AppKit, AVFoundation, Accelerate, and Combine; no third-party dependencies or bundled runtime.

- Local music library with recursive folder scanning and metadata.
- Eight-band EQ and preamp, with saved per-track settings.
- Automatic spectral analysis and suggested EQ.
- Gapless scheduling between tracks with matching decoded sample rates and channel counts; normal next-track playback otherwise.
- Stereo-aware waveform seeking and a 32-band live spectrum.
- Shuffle, repeat, media-key commands, menu-bar controls, and output-device selection.

Audio decoding is provided by macOS. A filename extension alone does not guarantee that its codec is supported.

## Build

Requires macOS and the Xcode command-line tools. The verified build uses Apple Swift 6.3.3 on Apple silicon and targets macOS 14 or later.

```sh
# Development, with normal debug information:
swift build

# Verify, compile, strip, sign locally, package, and measure:
python3 Scripts/release.py --dmg UDZO
```

The release is written to `artifacts/release/Ultralight.app`, with a DMG and a `size.json` containing exact sizes, source hashes, build flags, and file hashes. It is ad-hoc signed for local use, not Developer ID signed or notarized. Nothing is installed automatically.

The release script compiles all production source files in one compiler invocation. This permits whole-program LLVM optimization and avoids the additional code produced by split object generation. SwiftPM release builds also enable single-module LLVM emission; use `swift build -c release -debug-info-format none` when comparing them. Do not substitute `-num-threads 0`: clean SwiftPM builds can fail with missing object files.

## Quality and size gates

```sh
python3 Scripts/check.py
```

The release runs every gate before building and verifies that the source has not changed afterward:

- Audio analysis, spectra, waveform edge cases, persistence, and legacy file hashes.
- Native UI bindings/actions and strict comparisons to three renders of the starting version. Rendering uses a fixed 2× scale.
- Real audio-engine transport and queued transitions at zero output volume.
- Offline sample-exact continuity, including complete EQ/preamp bypass.
- Delayed asynchronous completions, idempotent transport commands, and queue/state consistency.
- Literal compatibility fixtures for every persisted field and deferred binding cancellation/order.
- Zero warmed-up FFT allocations and at most one output allocation per live spectrum callback.

Test fixtures and saved settings are isolated from your library. Test code and images are not shipped in the app. The verified Apple-silicon release budgets are 272,000 bytes for the executable, 275,000 bytes for the signed app payload, and 120,000 bytes for the DMG. The current release passes 350 assertions plus the calibrated allocation gate. A failed gate or exceeded budget stops the release.

See [HILLCLIMB.md](HILLCLIMB.md) for measured results, retained optimizations, rejected experiments, and validation limits.
