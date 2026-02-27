# ULTRALIGHT

### A music player that fits in a cache line budget

---

![Ultralight](screenshot.png)

---

**285 KB** stripped binary. **134 KB** compressed DMG. Zero dependencies beyond macOS itself.

Pure AppKit. No SwiftUI. No Electron. No frameworks. No package managers. Just `swift build` and a single executable that links against what ships with every Mac.

---

## Abstract

Ultralight is a native macOS music player built on the thesis that audio software has no business being large. It implements real-time FFT spectrum analysis, 8-band parametric equalization with per-track persistence, and automatic tonal profiling — all within a binary smaller than most JPEG images.

The architecture is deliberately minimal: one process, one window, one render path. State flows through Combine publishers. Audio flows through an `AVAudioEngine` graph. Everything else is `NSView` subclasses drawing into dirty rects.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    AppDelegate                       │
│                        │                             │
│                    MainWindow                        │
│         ┌──────────────┼──────────────┐              │
│    HeaderView    TrackListView    EQPanelView        │
│         └──────────────┼──────────────┘              │
│                  PlaybackBarView                     │
│                   SpectrumView                       │
│                        │                             │
│                    AppState ←── Combine ──→ Views    │
│                        │                             │
│                   AudioEngine                        │
│            ┌───────────┼───────────┐                 │
│     AVAudioPlayerNode  AVAudioUnitEQ  AVAudioMixerNode│
│                        │                             │
│                  AudioAnalyzer                       │
│              (vDSP FFT · Accelerate)                 │
└─────────────────────────────────────────────────────┘
```

## Features

| Feature | Implementation |
|---|---|
| **Playback** | `AVAudioEngine` graph: player → 8-band parametric EQ → mixer → output |
| **Spectrum** | Real-time 1024-sample FFT via `vDSP_fft_zrip`, Hann-windowed, 32-band logarithmic binning |
| **Auto-EQ** | Offline spectral analysis computes bass/mid/treble energy distribution, spectral centroid, crest factor, peak level; generates corrective EQ curve per track |
| **Detection** | Classifies tracks as bass-heavy, bright, muddy, thin, compressed, dynamic, or clipping based on spectral statistics |
| **Persistence** | Per-track EQ profiles keyed by partial MD5 hash (first 64KB + last 64KB + file size), matching the Electron version's format |
| **Formats** | FLAC, MP3, WAV, AAC, M4A, OGG, OPUS, AIFF, WMA, ALAC — anything `AVFoundation` decodes |
| **System** | Media key integration via `MPRemoteCommandCenter`, menu bar status item, drag-and-drop folder import |

## Size Comparison

```
Application                    Binary      Installer/DMG
─────────────────────────────────────────────────────────
Ultralight (AppKit)            285 KB         134 KB
μTorrent 1.6 (2006)          ~290 KB            —
Ultralight (SwiftUI)           400 KB         201 KB
foobar2000                       —           4.6 MB
Spotify                          —          ~150 MB
Electron (original)              —           104 MB
```

## Build

Requires macOS 14+ and Swift 5.9+.

```sh
swift build -c release
strip -rSTx .build/release/Ultralight
```

The binary is at `.build/release/Ultralight`. To create an `.app` bundle:

```sh
mkdir -p Ultralight.app/Contents/MacOS
cp .build/release/Ultralight Ultralight.app/Contents/MacOS/
```

Add an `Info.plist` to `Ultralight.app/Contents/` with `CFBundleExecutable` set to `Ultralight`.

## Design Decisions

**Why not SwiftUI?** We built a SwiftUI version first. It worked. The binary was 400 KB. Removing the SwiftUI dependency and writing pure `NSView` subclasses saved 115 KB (29%) and eliminated the SwiftUI runtime overhead. At this scale, every framework import is a line item.

**Why Combine without SwiftUI?** Combine ships with macOS and costs nothing to link. `@Published` properties with `.sink` subscriptions give us reactive state propagation without pulling in SwiftUI's view diffing machinery.

**Why MD5?** The hash format matches the Electron version's database for migration compatibility. It hashes a partial fingerprint (head + tail + size), not the full file — fast enough to scan thousands of tracks at startup.

**Why `-Osize`?** At this binary size, `-O` (speed) vs `-Osize` saves 16 KB with no measurable playback latency impact. The hot path is `vDSP` and `AVAudioEngine`, both of which run in Apple's own optimized frameworks.

## File Structure

```
Sources/Ultralight/
├── App/
│   ├── main.swift              # NSApplication.shared.run()
│   ├── AppDelegate.swift       # Window + system component init
│   └── AppState.swift          # Central state, Combine publishers
├── Audio/
│   ├── AudioEngine.swift       # AVAudioEngine graph + spectrum tap
│   ├── AudioAnalyzer.swift     # Offline FFT analysis + auto-EQ
│   └── FileHasher.swift        # Partial MD5 track fingerprinting
├── Models/
│   ├── Track.swift
│   ├── EQProfile.swift
│   └── AnalysisResult.swift
├── Scanner/
│   └── FolderScanner.swift     # Recursive scan + AVAsset metadata
├── Storage/
│   ├── ConfigStore.swift       # Folder list persistence
│   ├── EQStore.swift           # Per-track EQ profiles
│   └── AnalysisStore.swift     # Analysis cache
├── System/
│   ├── MenuBarManager.swift    # NSStatusItem
│   └── MediaKeyHandler.swift   # MPRemoteCommandCenter
└── Views/
    ├── MainWindow.swift        # NSWindow + Auto Layout + drag-drop
    ├── HeaderView.swift        # Logo, now-playing, format badge
    ├── TrackListView.swift     # NSTableView + custom cells
    ├── PlaybackBarView.swift   # Transport, progress, volume
    ├── SpectrumView.swift      # Real-time FFT visualization
    ├── EQPanelView.swift       # 8-band EQ + detection badges
    └── SettingsWindow.swift    # Folder management
```

24 files. 2,244 lines. That's the whole thing.

## License

MIT
