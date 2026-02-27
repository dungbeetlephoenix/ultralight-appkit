# ULTRALIGHT

![Ultralight](screenshot.png)

A music player in 285 KB.

I got tired of every audio app on my Mac being enormous. Spotify is 150 MB. The Electron version of this same player was 104 MB. I wanted to see how small I could go while keeping the features I actually use — EQ, spectrum, auto-analysis.

This is pure AppKit. No SwiftUI, no Electron, no third-party dependencies. One `swift build`, one binary, done. It links against frameworks that already ship with macOS and nothing else.

The DMG is 134 KB. Smaller than most album art.

## What it does

- Plays FLAC, MP3, WAV, AAC, M4A, OGG, OPUS, AIFF, and anything else AVFoundation can decode
- 8-band parametric EQ that persists per track
- Analyzes each track on first play — computes spectral energy, crest factor, centroid — and generates a corrective EQ curve automatically
- Tags tracks as bass-heavy, bright, muddy, thin, compressed, dynamic, or clipping
- Real-time 32-band FFT spectrum visualizer
- Media key support, menu bar icon, drag-and-drop import
- Scans folders recursively, reads metadata from embedded tags

## How small

```
Ultralight (this)        285 KB binary     134 KB dmg
μTorrent 1.6 (2006)     ~290 KB binary
foobar2000                                 4.6 MB installer
Spotify                                   ~150 MB
```

I started with a SwiftUI version that came out to 400 KB. Rewriting the views as plain NSView subclasses with manual Auto Layout and custom `draw()` calls shaved off 115 KB. The `-Osize` compiler flag and aggressive stripping got it the rest of the way.

The hot path is all Apple frameworks — `vDSP` for FFT, `AVAudioEngine` for the audio graph — so optimizing for size over speed costs nothing audible.

## Build

macOS 14+, Swift 5.9+.

```sh
swift build -c release
strip -rSTx .build/release/Ultralight
```

To make an app bundle:

```sh
mkdir -p Ultralight.app/Contents/MacOS
cp .build/release/Ultralight Ultralight.app/Contents/MacOS/
```

You'll need an `Info.plist` in `Ultralight.app/Contents/` — just set `CFBundleExecutable` to `Ultralight`.

## How it works

Audio runs through an `AVAudioEngine` graph: `AVAudioPlayerNode` → `AVAudioUnitEQ` (8 parametric bands) → `AVAudioMixerNode` → output. A tap on the mixer feeds 1024-sample buffers into a Hann-windowed FFT for the spectrum display.

State management is Combine — `@Published` properties on a central `AppState` singleton, views subscribe with `.sink`. No SwiftUI means no view diffing overhead, just targeted UI updates when values change.

Track identification uses a partial MD5 hash (first 64 KB + last 64 KB + file size) so EQ profiles follow tracks even if they move on disk. The hash format is compatible with the earlier Electron version's database.

The offline analyzer runs a longer FFT pass over the full file, computes energy distribution across bass/mid/treble bands, measures dynamic range via crest factor, and derives a suggested EQ curve that gets applied automatically if no saved profile exists.

## Structure

```
Sources/Ultralight/
├── App/          main.swift, AppDelegate, AppState
├── Audio/        AudioEngine, AudioAnalyzer, FileHasher
├── Models/       Track, EQProfile, AnalysisResult
├── Scanner/      FolderScanner
├── Storage/      ConfigStore, EQStore, AnalysisStore
├── System/       MenuBarManager, MediaKeyHandler
└── Views/        MainWindow, HeaderView, TrackListView,
                  PlaybackBarView, SpectrumView,
                  EQPanelView, SettingsWindow
```

24 files, ~2200 lines.

## License

MIT
