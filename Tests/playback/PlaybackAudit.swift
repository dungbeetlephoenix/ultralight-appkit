import AVFoundation
import Foundation

@main
struct PlaybackAudit {
    static var checks: [[String: Any]] = []
    static var events: [[String: Any]] = []
    static let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ULTRALIGHT_PLAYBACK_AUDIT_OUTPUT"]!)
    static func path(_ name: String) -> String { output.appendingPathComponent(name + ".wav").path }
    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        checks.append(["name": name, "pass": condition, "detail": detail])
        print("\(condition ? "PASS" : "FAIL") \(name) \(detail)"); fflush(stdout)
    }
    static func close(_ value: Double, _ expected: Double, _ tolerance: Double = 0.035) -> Bool { abs(value - expected) <= tolerance }
    static func pump() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03)) }
    static func fresh() throws -> AudioEngine {
        let audio = AudioEngine()
        try audio.auditEnableOffline()
        check("master volume zero", audio.auditVolume == 0, "offline=\(audio.auditManualMode)")
        return audio
    }
    static func main() {
        do {
            let audio = try fresh()
            check("initial stopped", !audio.isPlaying && audio.duration == 0 && audio.currentTime == 0)
            try audio.loadAndPlay(path: path("long"))
            check("load/play starts and duration", audio.isPlaying && close(audio.duration, 3, 0.0001))
            try audio.auditRender(0.25)
            check("playing clock advances", close(audio.currentTime, 0.25), "time=\(audio.currentTime)")
            let beforePause = audio.currentTime
            audio.pause()
            let paused = audio.currentTime
            check("pause preserves position", close(paused, beforePause), "before=\(beforePause) after=\(paused)")
            try audio.auditRender(0.15)
            check("pause holds clock", !audio.isPlaying && close(audio.currentTime, paused, 0.0001), "before=\(paused) after=\(audio.currentTime)")
            try audio.resume()
            try audio.auditRender(0.12)
            check("resume without seek preserves elapsed position", audio.isPlaying && close(audio.currentTime, beforePause + 0.12), "time=\(audio.currentTime) expected=\(beforePause + 0.12)")
            audio.pause()
            audio.seek(to: 1.25)
            check("paused seek preserves pause and time", !audio.isPlaying && close(audio.currentTime, 1.25, 0.0001), "time=\(audio.currentTime)")
            try audio.auditRender(0.1)
            check("paused seek stays stationary", !audio.isPlaying && close(audio.currentTime, 1.25, 0.0001))
            try audio.resume()
            try audio.auditRender(0.2)
            check("resume advances from seek", audio.isPlaying && close(audio.currentTime, 1.45), "time=\(audio.currentTime)")
            audio.seek(to: 0.7)
            check("running seek preserves playback", audio.isPlaying && close(audio.currentTime, 0.7), "time=\(audio.currentTime)")
            try audio.auditRender(0.2)
            check("running seek clock", close(audio.currentTime, 0.9), "time=\(audio.currentTime)")
            audio.seek(to: -.infinity)
            check("nonfinite seek ignored", close(audio.currentTime, 0.9))
            audio.pause()
            audio.seek(to: -5)
            check("negative seek clamps zero", !audio.isPlaying && close(audio.currentTime, 0, 0.0001))
            audio.seek(to: 50)
            check("seek beyond tail clamps", !audio.isPlaying && close(audio.currentTime, 3 - 1.0 / 44100, 0.00001))
            audio.stop()
            pump()
            check("stop resets playback", !audio.isPlaying && audio.currentTime == 0 && audio.duration == 0 && audio.auditQueuedPath == nil)

            try gapless()
            try delayedBoundaryPause()
            try staleCallbacks()
            try queueReplacement()
            try formatFallback()
        } catch { check("unexpected thrown error", false, String(describing: error)) }
        let failed = checks.filter { ($0["pass"] as? Bool) != true }.count
        let report: [String: Any] = ["passed": checks.count - failed, "failed": failed, "checks": checks, "events": events, "mode": ProcessInfo.processInfo.environment["ULTRALIGHT_PLAYBACK_AUDIT_MODE"] ?? "realtime", "master_volume": 0]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output.appendingPathComponent("results.json")) }
        print("RESULT \(checks.count - failed)/\(checks.count) checks passed"); fflush(stdout)
        exit(failed == 0 ? 0 : 1)
    }

    static func gapless() throws {
        let audio = try fresh()
        var advanced: [String] = []
        var finished = 0
        audio.onTrackAdvanced = { value in
            advanced.append(URL(fileURLWithPath: value).lastPathComponent)
            events.append(["scenario": "gapless", "event": "advanced", "path": value, "time": audio.currentTime, "duration": audio.duration])
            if value == path("b") { check("queue third track from callback", audio.queueNext(path: path("c"))) }
        }
        audio.onTrackFinished = { finished += 1; events.append(["scenario": "gapless", "event": "finished", "time": audio.currentTime, "duration": audio.duration]) }
        try audio.loadAndPlay(path: path("a"))
        check("queue second track", audio.queueNext(path: path("b")))
        try audio.auditRender(0.7)
        check("first transition identity and duration", advanced == ["b.wav"] && audio.auditPath == path("b") && close(audio.duration, 0.6, 0.0001), "advanced=\(advanced)")
        check("second-track clock is relative", close(audio.currentTime, 0.2), "time=\(audio.currentTime)")
        try audio.auditRender(0.6)
        check("third-track transition order and duration", advanced == ["b.wav", "c.wav"] && audio.auditPath == path("c") && close(audio.duration, 0.7, 0.0001), "advanced=\(advanced)")
        check("third-track clock is relative", close(audio.currentTime, 0.2), "time=\(audio.currentTime)")
        try audio.auditRender(0.7)
        pump()
        check("chain has one terminal callback", finished == 1 && advanced == ["b.wav", "c.wav"], "finished=\(finished) advanced=\(advanced)")
        audio.stop()
    }

    static func delayedBoundaryPause() throws {
        let audio = try fresh()
        // This race needs audio rendering independently while the main queue is
        // blocked. The optional offline runner advances only when auditRender runs.
        guard !audio.auditManualMode else { return }
        var advanced: [String] = []
        audio.onTrackAdvanced = { advanced.append($0) }
        try audio.loadAndPlay(path: path("a"))
        check("delayed boundary queues second track", audio.queueNext(path: path("b")))

        // A lasts 0.5 seconds. B is already rendering at zero master volume, but
        // its identity callback cannot run until we explicitly drain the main queue.
        Thread.sleep(forTimeInterval: 0.72)
        check("delayed boundary callback waits for main queue", advanced.isEmpty)
        audio.pause()
        check("delayed boundary pauses before callback", !audio.isPlaying && advanced.isEmpty)
        pump()

        let paused = audio.currentTime
        check("delayed boundary callback delivered once", advanced == [path("b")] && audio.auditPath == path("b"), "advanced=\(advanced)")
        check("delayed boundary pause uses new track clock", !audio.isPlaying && paused >= 0.1 && paused < 0.4,
              "time=\(paused), expected B near 0.22 seconds, not A's 0.5-second end")
        try audio.auditRender(0.1)
        check("delayed boundary paused clock stays fixed", !audio.isPlaying && close(audio.currentTime, paused, 0.0001),
              "before=\(paused) after=\(audio.currentTime)")
        audio.stop()
    }

    static func staleCallbacks() throws {
        let audio = try fresh()
        var advanced: [String] = []
        var finished = 0
        audio.onTrackAdvanced = { advanced.append($0) }
        audio.onTrackFinished = { finished += 1 }
        try audio.loadAndPlay(path: path("a"))
        check("manual-switch old queue added", audio.queueNext(path: path("b")))
        try audio.auditRender(0.2)
        try audio.loadAndPlay(path: path("long"))
        pump()
        try audio.auditRender(0.8)
        check("manual switch rejects stale callbacks", advanced.isEmpty && finished == 0 && audio.auditPath == path("long"), "advanced=\(advanced) finished=\(finished)")
        check("manual switch resets timeline", close(audio.currentTime, 0.8), "time=\(audio.currentTime)")
        audio.stop()
        pump()
        check("stop rejects callbacks", advanced.isEmpty && finished == 0)
    }

    static func queueReplacement() throws {
        let audio = try fresh()
        var advanced: [String] = []
        var finished = 0
        audio.onTrackAdvanced = { advanced.append(URL(fileURLWithPath: $0).lastPathComponent) }
        audio.onTrackFinished = { finished += 1 }
        try audio.loadAndPlay(path: path("a"))
        check("replacement original queue", audio.queueNext(path: path("b")))
        try audio.auditRender(0.2)
        let before = audio.currentTime
        check("replacement queue succeeds", audio.queueNext(path: path("c")))
        check("replacement preserves playback/time", audio.isPlaying && close(audio.currentTime, before, 0.0001), "before=\(before) after=\(audio.currentTime)")
        try audio.auditRender(0.5)
        check("replacement advances only new track", advanced == ["c.wav"] && audio.auditPath == path("c") && close(audio.currentTime, before), "advanced=\(advanced) time=\(audio.currentTime) expected=\(before)")
        try audio.auditRender(0.7)
        check("replacement finishes once", finished == 1, "finished=\(finished)")
        audio.stop()

        try audio.loadAndPlay(path: path("a"))
        check("paused replacement original queue", audio.queueNext(path: path("b")))
        try audio.auditRender(0.1)
        let beforePause = audio.currentTime
        audio.pause()
        let paused = audio.currentTime
        check("queued playback pause preserves position", close(paused, beforePause), "before=\(beforePause) after=\(paused)")
        check("paused replacement succeeds", audio.queueNext(path: path("c")))
        check("paused replacement stays paused/time", !audio.isPlaying && close(audio.currentTime, paused, 0.0001))
        audio.stop()
    }

    static func formatFallback() throws {
        let audio = try fresh()
        var advanced: [String] = []
        var finished = 0
        audio.onTrackAdvanced = { advanced.append($0) }
        audio.onTrackFinished = { finished += 1 }
        try audio.loadAndPlay(path: path("a"))
        check("format mismatch original queue", audio.queueNext(path: path("b")))
        try audio.auditRender(0.1)
        check("sample rate mismatch rejects gapless", !audio.queueNext(path: path("different-rate")) && audio.auditQueuedPath == nil)
        check("channel mismatch rejects gapless", !audio.queueNext(path: path("mono")) && audio.auditQueuedPath == nil)
        check("missing next file rejects gapless", !audio.queueNext(path: path("missing")))
        try audio.auditRender(0.6)
        check("mismatch leaves current track terminal callback", advanced.isEmpty && finished == 1, "advanced=\(advanced) finished=\(finished)")
        try audio.loadAndPlay(path: path("different-rate"))
        check("mismatched-rate manual fallback starts", audio.isPlaying && close(audio.duration, 0.8, 0.0001))
        try audio.auditRender(0.2)
        check("mismatched-rate fallback clock", close(audio.currentTime, 0.2), "time=\(audio.currentTime)")
        audio.stop()
    }
}
