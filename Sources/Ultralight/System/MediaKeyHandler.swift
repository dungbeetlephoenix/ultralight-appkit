import MediaPlayer

final class MediaKeyHandler {
    private weak var state: AppState?

    func setup(state: AppState) {
        self.state = state

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.state?.togglePlay()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.state?.togglePlay()
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.state?.togglePlay()
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.state?.playNext()
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.state?.playPrevious()
            return .success
        }

        center.stopCommand.addTarget { [weak self] _ in
            self?.state?.stop()
            return .success
        }
    }

    func updateNowPlaying(track: Track, currentTime: Double, isPlaying: Bool) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = track.displayTitle
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyAlbumTitle] = track.album
        info[MPMediaItemPropertyPlaybackDuration] = track.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
