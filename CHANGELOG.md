# Changelog

## 2.2.0 — Unreleased

### Playback and analysis

- Correct queued playback and pause/seek timing, and prevent stale background work from changing a newer playback session.
- Analyze stereo channels correctly, include waveform tails, and apply EQ bypass consistently.
- Reuse FFT storage and share native UI construction to reduce code and allocation overhead while retaining the player’s features.

### Interface

- Add keyboard and accessibility support to custom controls, including descriptive labels, values, actions, and tooltips.
- Update the Settings folder list as folders change and make menu-bar actions target the player window explicitly.
- Add an application icon with a reproducible generation script.

### Build and verification

- Enforce a 200,000-byte limit for both the signed executable and complete Apple-silicon app, plus a 120,000-byte disk-image limit.
- Stage releases in isolation, preserve previous output on failure, and verify the packaged app by mounting the disk image read-only.
- Add an optional Developer ID signing and notarization flow with the same verification and size limits.
- Add source, runtime-compatibility, and desktop-release workflows, together with public measurement evidence and build documentation.

### Release status

The recorded build is ad-hoc signed and verified for local use. Hosted build and tooling checks pass, along with the native compatibility fixture on macOS 14 and 26. Developer ID signing, Apple notarization, and launch after download remain unverified for this release. See the [verification record](docs/evidence/README.md) for completed checks and their scope, and [BUILDING.md](BUILDING.md) for reproduction commands.

## Version policy

`VERSION` is the source of truth for the bundle version. Tag releases with an annotated `vMAJOR.MINOR.PATCH` tag on the reviewed commit.

Add the release date and remove “Unreleased” when the matching app, disk image, checksums, and verification evidence are ready. Rebuild and remeasure after any resource, metadata, or signing change. A release tag must always identify the same source and artifacts.
