# Ultralight

A small native music player for the Mac. Your library, an equalizer, and the music.

![Ultralight with demo tracks](screenshot.png)

Ultralight uses AppKit and the audio frameworks already on your Mac. There are no third-party dependencies or bundled runtimes. The release build enforces a **200,000-byte limit for the complete signed app**. The verified local build is **192,812 bytes**, including its icon, license, and signature; the disk image is **106,770 bytes**. [Exact measurements](docs/evidence/release.json).

It includes an eight-band equalizer with per-track settings, spectral analysis with suggested EQ, a live spectrum, waveform seeking, shuffle, repeat, media keys, and menu-bar controls. Tracks with matching decoded sample rates and channel counts can play continuously; other transitions use normal next-track playback. Codec support comes from macOS.

## Get started

The release target is Apple silicon and macOS 14 or later. The current verified environment is macOS 26.7; the macOS 14 runtime check is pending. See [verification status](docs/evidence/README.md) for the exact scope.

To build and run from source with Xcode installed:

```sh
swift run Ultralight
```

Open Settings with the gear button to add music folders, or drop a folder onto the player. Dropping a file adds its containing folder. Ultralight scans subfolders automatically. Your music stays where it is. Double-click a track to play it.

| Control | Action |
| --- | --- |
| Space | Play or pause |
| Left / Right | Seek five seconds |
| Command–Left / Command–Right | Previous or next track |
| Up / Down | Adjust volume |
| EQ | Show or hide the equalizer |

Player shortcuts yield to focused controls. Sliders use the arrow keys to adjust their own values. Controls also expose names, values, and actions to VoiceOver. Tab navigation follows your macOS keyboard-navigation settings.

Closing the player window keeps the app available in the menu bar. Choose **Show Player** to reopen it or **Quit** to exit. Folder preferences, saved EQ, and cached analysis live in `~/Library/Application Support/ultralight/`.

## Build and verify

```sh
python3 Scripts/release.py --dmg UDZO
```

This runs the quality gates, builds and signs the app, checks its size, and verifies the contents of the disk image. A failed run leaves the previous release intact. The output is written to `artifacts/release/`.

The default artifact is ad-hoc signed for local use. Public distribution requires its own Developer ID signing and notarization run. Build prerequisites, verification commands, and that signing flow are in [BUILDING.md](BUILDING.md).

Read [the engineering report](HILLCLIMB.md) for the size work and its tradeoffs, or [the changelog](CHANGELOG.md) for this release. The code is available under the [MIT license](LICENSE).
