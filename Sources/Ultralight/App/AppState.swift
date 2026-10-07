import AppKit
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var tracks: [Track] = []
    @Published var folders: [String] = []
    @Published var searchQuery: String = ""

    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 0.8
    @Published var shuffle: Bool = false
    @Published var repeatMode: Bool = false

    @Published var eqProfile: EQProfile = .flat
    @Published var eqBypassed: Bool = false
    @Published var showEQ: Bool = true

    @Published var spectrumData: [Float] = Array(repeating: 0, count: 32)
    @Published var waveformData: [Float] = []

    let audioEngine = AudioEngine()
    private var timeTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var scanTask: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var upcomingTrack: Track?
    var onPlaybackError: ((Error) -> Void)?

    init() {
        setupEngine()
        setupObservers()
        loadConfig()
    }

    private func setupEngine() {
        audioEngine.onSpectrumData = { [weak self] data in
            DispatchQueue.main.async { self?.spectrumData = data }
        }
        audioEngine.onTrackFinished = { [weak self] in
            self?.playNext()
        }
        audioEngine.onTrackAdvanced = { [weak self] path in
            self?.handleTrackAdvanced(path: path)
        }
    }

    private func setupObservers() {
        $volume.sink { [weak self] v in self?.audioEngine.setVolume(v) }.store(in: &cancellables)
        $eqProfile.sink { [weak self] p in self?.audioEngine.applyEQ(p) }.store(in: &cancellables)
        $eqBypassed.sink { [weak self] b in self?.audioEngine.setEQBypassed(b) }.store(in: &cancellables)
        $shuffle.combineLatest($repeatMode).dropFirst().sinkOnMain { [weak self] _ in self?.queueNextTrack() }.store(in: &cancellables)
    }

    private func loadConfig() {
        let config = ConfigStore.load()
        folders = config.folders
        if !folders.isEmpty { scanFolders() }
    }

    func saveConfig() {
        var config = ConfigStore.Config()
        config.folders = folders
        ConfigStore.save(config)
    }

    func addFolder(_ path: String) {
        guard !folders.contains(path) else { return }
        folders.append(path)
        saveConfig()
        scanFolders()
    }

    func removeFolder(_ path: String) {
        folders.removeAll { $0 == path }
        let roots = folders.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        tracks.removeAll { track in
            !roots.contains { track.path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }
        queueNextTrack()
        saveConfig()
        scanFolders()
    }

    func scanFolders() {
        scanTask?.cancel()
        let roots = folders
        scanTask = Task { @MainActor in
            let scanned = await FolderScanner.scan(folders: roots)
            guard !Task.isCancelled else { return }
            self.tracks = scanned
            self.queueNextTrack()
        }
    }

    func loadEQForCurrentTrack() {
        analysisTask?.cancel()
        guard let track = currentTrack else { return }
        if let saved = EQStore.profile(for: track.id) {
            eqProfile = saved
        } else if let analysis = AnalysisStore.result(for: track.id) {
            eqProfile = analysis.suggestedEQ
        } else {
            eqProfile = .flat
            analyzeCurrentTrack()
        }
    }

    private func analyzeCurrentTrack() {
        guard let track = currentTrack, !track.analyzed else { return }
        let trackId = track.id
        let trackPath = track.path
        analysisTask = Task { @MainActor in
            guard let result = await AudioAnalyzer.analyze(path: trackPath) else { return }
            guard !Task.isCancelled else { return }
            AnalysisStore.save(result: result, for: trackId)
            if let idx = tracks.firstIndex(where: { $0.id == trackId }) {
                tracks[idx].analyzed = true
            }
            if currentTrack?.id == trackId && eqProfile.isFlat && EQStore.profile(for: trackId) == nil {
                eqProfile = result.suggestedEQ
            }
        }
    }

    func saveEQForCurrentTrack() {
        guard let track = currentTrack else { return }
        EQStore.save(profile: eqProfile, for: track.id)
    }

    @discardableResult
    func play(track: Track) -> Bool {
        do {
            try audioEngine.loadAndPlay(path: track.path)
            currentTrack = track
            isPlaying = true
            currentTime = 0
            duration = audioEngine.duration
            loadEQForCurrentTrack()
            startTimeUpdates()
            queueNextTrack()
            computeWaveform(for: track)
            return true
        } catch {
            isPlaying = audioEngine.isPlaying
            if !isPlaying { stopTimeUpdates() }
            onPlaybackError?(error)
            return false
        }
    }

    private func handleTrackAdvanced(path: String) {
        guard let track = tracks.first(where: { $0.path == path }) else { return }
        currentTrack = track
        currentTime = audioEngine.currentTime
        duration = audioEngine.duration
        loadEQForCurrentTrack()
        queueNextTrack()
        computeWaveform(for: track)
    }

    private func queueNextTrack() {
        upcomingTrack = nextTrack()
        guard let next = upcomingTrack else { audioEngine.clearQueuedTrack(); return }
        _ = audioEngine.queueNext(path: next.path)
    }

    private func computeWaveform(for track: Track) {
        waveformData = []
        waveformTask?.cancel()
        let path = track.path
        waveformTask = Task { @MainActor in
            if let waveform = await AudioAnalyzer.computeWaveform(path: path),
               !Task.isCancelled, self.currentTrack?.path == path {
                self.waveformData = waveform
            }
        }
    }

    func togglePlay() {
        if isPlaying {
            audioEngine.pause()
            isPlaying = false
            stopTimeUpdates()
        } else if let track = currentTrack {
            if audioEngine.duration == 0 { play(track: track); return }
            do {
                try audioEngine.resume()
                isPlaying = audioEngine.isPlaying
                startTimeUpdates()
            } catch { onPlaybackError?(error) }
        } else if let first = tracks.first {
            play(track: first)
        }
    }

    func stop() {
        audioEngine.stop()
        isPlaying = false
        currentTime = 0
        duration = 0
        upcomingTrack = nil
        waveformTask?.cancel()
        analysisTask?.cancel()
        spectrumData = Array(repeating: 0, count: 32)
        stopTimeUpdates()
    }

    func playNext() {
        if let next = upcomingTrack ?? nextTrack(), play(track: next) { return }
        stop()
    }

    func playPrevious() {
        if currentTime > 3 { seek(to: 0); return }
        if let prev = previousTrack() { play(track: prev) }
    }

    func seek(to time: Double) {
        audioEngine.seek(to: time)
        currentTime = audioEngine.currentTime
        if let next = upcomingTrack { _ = audioEngine.queueNext(path: next.path) }
    }

    private func startTimeUpdates() {
        stopTimeUpdates()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.currentTime = self?.audioEngine.currentTime ?? 0
        }
    }

    private func stopTimeUpdates() {
        timeTimer?.invalidate()
        timeTimer = nil
    }

    var filteredTracks: [Track] {
        if searchQuery.isEmpty { return tracks }
        let q = searchQuery.lowercased()
        return tracks.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            $0.album.lowercased().contains(q)
        }
    }

    var currentTrackIndex: Int? {
        guard let current = currentTrack else { return nil }
        return tracks.firstIndex(where: { $0.path == current.path })
    }

    func nextTrack() -> Track? {
        guard let idx = currentTrackIndex else { return tracks.first }
        if shuffle { return tracks.filter { $0.path != currentTrack?.path }.randomElement() ?? (repeatMode ? tracks.first : nil) }
        let next = idx + 1
        if next < tracks.count { return tracks[next] }
        return repeatMode ? tracks.first : nil
    }

    func previousTrack() -> Track? {
        guard let idx = currentTrackIndex else { return tracks.last }
        if idx > 0 { return tracks[idx - 1] }
        return repeatMode ? tracks.last : nil
    }
}
