import AppKit
import Combine

// Deterministic service doubles isolate actual AppState task guards and queue logic.
final class AudioEngine {
    var onSpectrumData: (([Float]) -> Void)?
    var onTrackFinished: (() -> Void)?
    var onTrackAdvanced: ((String) -> Void)?
    var isPlaying = false
    var duration: Double = 0
    var currentTime: Double = 0
    var loaded: String?
    var queued: String?
    var queueHistory: [String?] = []
    func setVolume(_ value: Float) {}
    func applyEQ(_ value: EQProfile) {}
    func setEQBypassed(_ value: Bool) {}
    func loadAndPlay(path: String) throws { loaded = path; currentTime = 0; duration = 10; isPlaying = true; queued = nil }
    func queueNext(path: String) -> Bool { queued = duration > 0 ? path : nil; queueHistory.append(queued); return queued != nil }
    func clearQueuedTrack() { queued = nil; queueHistory.append(nil) }
    func pause() { isPlaying = false }
    func resume() throws { isPlaying = duration > 0 }
    func stop() { isPlaying = false; duration = 0; currentTime = 0; queued = nil }
    func seek(to time: Double) { currentTime = time; queued = nil }
}
enum ConfigStore {
    struct Config { var folders: [String] = []; var theme = "dark" }
    static func load() -> Config { Config() }
    static func save(_ config: Config) {}
}
enum EQStore {
    static var values: [String: EQProfile] = [:]
    static func profile(for key: String) -> EQProfile? { values[key] }
    static func save(profile: EQProfile, for key: String) { values[key] = profile }
}
enum AnalysisStore {
    static var values: [String: AnalysisResult] = [:]
    static func result(for key: String) -> AnalysisResult? { values[key] }
    static func save(result: AnalysisResult, for key: String) { values[key] = result }
}
@MainActor enum Deferred {
    static var waves: [String: [CheckedContinuation<[Float]?, Never>]] = [:]
    static var scans: [String: [CheckedContinuation<[Track], Never>]] = [:]
    static func resolveWave(_ path: String, _ result: [Float], index: Int = 0) {
        guard var pending = waves[path], pending.indices.contains(index) else { StateAudit.check("wave request exists", false, path); return }
        let continuation = pending.remove(at: index); waves[path] = pending; continuation.resume(returning: result)
    }
    static func resolveScan(_ roots: [String], _ result: [Track]) {
        let key = roots.joined(separator: "|")
        guard var pending = scans[key], !pending.isEmpty else { StateAudit.check("scan request exists", false, key); return }
        let continuation = pending.removeFirst(); scans[key] = pending; continuation.resume(returning: result)
    }
}
enum AudioAnalyzer {
    static func analyze(path: String) async -> AnalysisResult? { nil }
    @MainActor static func computeWaveform(path: String) async -> [Float]? {
        await withCheckedContinuation { Deferred.waves[path, default: []].append($0) }
    }
}
enum FolderScanner {
    @MainActor static func scan(folders: [String]) async -> [Track] {
        await withCheckedContinuation { Deferred.scans[folders.joined(separator: "|"), default: []].append($0) }
    }
}

@main @MainActor struct StateAudit {
    static var checks: [[String: Any]] = []
    static func check(_ name: String, _ condition: Bool, _ detail: String = "") { checks.append(["name": name, "pass": condition, "detail": detail]); print("\(condition ? "PASS" : "FAIL") \(name) \(detail)") }
    static func pump() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.035)) }
    static func track(_ name: String, folder: String = "/tmp/audit/music") -> Track { Track(id: name, path: folder + "/" + name + ".wav", title: name, artist: "", album: "", duration: 10, analyzed: true) }
    static func main() {
        let a = track("a"), b = track("b"), c = track("c", folder: "/tmp/audit/other")
        let state = AppState()
        state.tracks = [a,b,c]
        state.play(track: a); pump()
        check("initial sequential queue", state.audioEngine.queued == b.path)
        state.play(track: b); pump()
        Deferred.resolveWave(b.path, [0.2]); pump()
        check("current waveform completes", state.waveformData == [0.2])
        Deferred.resolveWave(a.path, [0.1]); pump()
        check("late old waveform rejected", state.waveformData == [0.2])
        state.play(track: a); pump()
        state.play(track: b); pump()
        state.play(track: a); pump()
        Deferred.resolveWave(a.path, [0.3], index: 1); pump()
        Deferred.resolveWave(a.path, [0.9]); pump()
        check("A B A rejects oldest A waveform", state.waveformData == [0.3])
        Deferred.resolveWave(b.path, [0.8]); pump()
        check("A B A rejects intermediate B waveform", state.waveformData == [0.3])

        state.play(track: a); pump()
        state.stop()
        Deferred.resolveWave(a.path, [0.7]); pump()
        check("stop rejects pending waveform", state.waveformData.isEmpty)
        state.tracks = [a,b]
        state.play(track: b); pump()
        check("end of library no queue", state.audioEngine.queued == nil)
        state.repeatMode = true; pump()
        check("repeat on refreshes queue", state.audioEngine.queued == a.path)
        state.repeatMode = false; pump()
        check("repeat off clears queue", state.audioEngine.queued == nil)
        state.shuffle = true; pump()
        check("shuffle refreshes noncurrent queue", state.audioEngine.queued == a.path)
        state.seek(to: 4)
        check("seek preserves chosen upcoming path", state.audioEngine.queued == a.path && state.currentTime == 4)
        state.playNext(); pump()
        check("manual next uses chosen upcoming path", state.audioEngine.loaded == a.path)
        state.shuffle = false; pump()
        check("shuffle off returns sequential queue", state.audioEngine.queued == b.path)
        state.stop()

        state.folders = ["/tmp/audit/music", "/tmp/audit/other"]
        state.tracks = [a,b,c]
        state.play(track: a); pump()
        state.scanFolders(); pump()
        state.removeFolder("/tmp/audit/music"); pump()
        check("remove folder prunes synchronously", state.tracks.map(\.path) == [c.path])
        check("remove folder immediately replaces obsolete queue", state.audioEngine.queued == c.path)
        Deferred.resolveScan(["/tmp/audit/other"], [c]); pump()
        Deferred.resolveScan(["/tmp/audit/music", "/tmp/audit/other"], [a,b,c]); pump()
        check("late cancelled scan cannot restore removed tracks", state.tracks.map(\.path) == [c.path] && state.audioEngine.queued == c.path)
        state.stop()

        let nested = track("nested", folder: "/tmp/audit/music/nested")
        let unrelatedPrefix = track("outside", folder: "/tmp/audit/music-other")
        state.folders = ["/tmp/audit/music", "/tmp/audit/music/nested", "/tmp/audit/music-other"]
        state.tracks = [a,nested,unrelatedPrefix]
        state.removeFolder("/tmp/audit/music"); pump()
        check("nested root and neighboring prefix preserved", state.tracks.map(\.path) == [nested.path, unrelatedPrefix.path])
        Deferred.resolveScan(["/tmp/audit/music/nested", "/tmp/audit/music-other"], [nested,unrelatedPrefix]); pump()
        let failed = checks.filter { ($0["pass"] as? Bool) != true }.count
        let report: [String: Any] = ["passed": checks.count-failed, "failed": failed, "checks": checks, "scope": "Actual production AppState with deterministic fake audio, scanner, analyzer and stores. Tests task cancellation and queue decisions, not actual audio rendering."]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("results.json")) }
        print("RESULT \(checks.count-failed)/\(checks.count) checks passed")
        exit(failed == 0 ? 0 : 1)
    }
}
