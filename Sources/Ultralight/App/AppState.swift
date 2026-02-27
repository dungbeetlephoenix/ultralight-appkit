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

    let audioEngine = AudioEngine()
    private var timeTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

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
            DispatchQueue.main.async { self?.playNext() }
        }
    }

    private func setupObservers() {
        $volume.sink { [weak self] v in self?.audioEngine.setVolume(v) }.store(in: &cancellables)
        $eqProfile.sink { [weak self] p in self?.audioEngine.applyEQ(p) }.store(in: &cancellables)
        $eqBypassed.sink { [weak self] b in self?.audioEngine.setEQBypassed(b) }.store(in: &cancellables)
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
        tracks.removeAll { $0.path.hasPrefix(path) }
        saveConfig()
    }

    func scanFolders() {
        Task {
            let scanned = await FolderScanner.scan(folders: folders)
            self.tracks = scanned
        }
    }

    func loadEQForCurrentTrack() {
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
        Task {
            guard let result = await AudioAnalyzer.analyze(path: trackPath) else { return }
            AnalysisStore.save(result: result, for: trackId)
            if let idx = tracks.firstIndex(where: { $0.id == trackId }) {
                tracks[idx].analyzed = true
            }
            if currentTrack?.id == trackId && eqProfile.isFlat {
                eqProfile = result.suggestedEQ
            }
        }
    }

    func saveEQForCurrentTrack() {
        guard let track = currentTrack else { return }
        EQStore.save(profile: eqProfile, for: track.id)
    }

    func play(track: Track) {
        do {
            try audioEngine.loadAndPlay(path: track.path)
            currentTrack = track
            isPlaying = true
            duration = audioEngine.duration
            loadEQForCurrentTrack()
            startTimeUpdates()
        } catch {
            print("Failed to play \(track.path): \(error)")
        }
    }

    func togglePlay() {
        if isPlaying {
            audioEngine.pause()
            isPlaying = false
            stopTimeUpdates()
        } else if currentTrack != nil {
            audioEngine.resume()
            isPlaying = true
            startTimeUpdates()
        } else if let first = tracks.first {
            play(track: first)
        }
    }

    func stop() {
        audioEngine.stop()
        isPlaying = false
        currentTime = 0
        duration = 0
        stopTimeUpdates()
    }

    func playNext() {
        if let next = nextTrack() { play(track: next) } else { stop() }
    }

    func playPrevious() {
        if currentTime > 3 { seek(to: 0); return }
        if let prev = previousTrack() { play(track: prev) }
    }

    func seek(to time: Double) {
        audioEngine.seek(to: time)
        currentTime = time
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
        return tracks.firstIndex(where: { $0.id == current.id })
    }

    func nextTrack() -> Track? {
        guard let idx = currentTrackIndex else { return tracks.first }
        if shuffle { return tracks.randomElement() }
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
