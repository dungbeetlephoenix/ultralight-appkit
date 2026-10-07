# Changes

## 2.2.0 — unreleased

- A 200,000-byte budget for the complete signed Apple-silicon app, enforced by the release build.
- Corrected queued playback, pause/seek timing, stale background work, stereo analysis, waveform tails, and EQ bypass.
- Shared native UI construction and FFT storage, with no third-party runtime or decoder.
- Keyboard and accessibility support for the custom controls; descriptive control labels and tooltips.
- Live folder updates in Settings and explicit targeting of the player window from the menu bar.
- A small application icon and a repeatable icon-generation script.
- Isolated release staging, failure-safe checks, mounted-image verification, and optional Developer ID signing/notarization.
- Source, runtime-compatibility, and desktop-release workflows; published measurement evidence and separate user/build documentation.

The current artifact is ad-hoc signed for local use. Public signing and the minimum-OS runtime check remain release prerequisites until their results are recorded.

## Version policy

`VERSION` is the single source for the bundle version. Releases use an annotated `vMAJOR.MINOR.PATCH` Git tag on the reviewed commit. Add the release date and remove “unreleased” only when the matching app, disk image, checksums, and verification evidence are ready. Rebuild and remeasure after any resource, metadata, or signing change. Never reuse a tag for different bytes.
