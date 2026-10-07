import AVFoundation
import Foundation

@main struct ContinuityAudit {
    static var checks: [[String: Any]] = []
    static let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ULTRALIGHT_PLAYBACK_AUDIT_OUTPUT"]!)
    static func check(_ name: String, _ pass: Bool, _ detail: String = "") { checks.append(["name": name, "pass": pass, "detail": detail]); print("\(pass ? "PASS" : "FAIL") \(name) \(detail)"); fflush(stdout) }
    static func main() {
        var metrics: [String: Any] = [:]
        do {
            let audio = AudioEngine()
            try audio.auditEnableContinuityRender()
            check("true offline render mode before playback", audio.auditContinuityMode)
            check("whole EQ bypass retains plus6 preamp and nonflat band", audio.auditBypassRetainsProfile)
            try audio.loadAndPlay(path: output.appendingPathComponent("positive.wav").path)
            check("prequeue matching second track", audio.queueNext(path: output.appendingPathComponent("negative.wav").path))
            let firstCount = 22050
            let secondCount = 26460
            let total = firstCount + secondCount
            let pcm = try audio.auditCaptureFrames(total + 2048)
            check("two output channels and exact rendered frame count", pcm.count == 2 && pcm.allSatisfy { $0.count == total + 2048 })
            var maxError: Float = 0
            var wrongFrames = 0
            var silentPayloadFrames = 0
            for channel in pcm {
                for (i, sample) in channel.enumerated() {
                    let expected: Float = i < firstCount ? 0.25 : (i < total ? -0.25 : 0)
                    let error = abs(sample - expected)
                    maxError = max(maxError, error)
                    if error > 0.000001 { wrongFrames += 1 }
                    if i < total && abs(sample) < 0.000001 { silentPayloadFrames += 1 }
                }
            }
            check("no silence inside either track or join", silentPayloadFrames == 0, "silent channel-frames=\(silentPayloadFrames)")
            check("sample-exact A then B then silence", wrongFrames == 0, "wrong channel-frames=\(wrongFrames), max error=\(maxError)")
            check("join occurs at exact scheduled frame", pcm.allSatisfy { abs($0[firstCount - 1] - 0.25) < 0.000001 && abs($0[firstCount] + 0.25) < 0.000001 })
            check("no extra audio frames after final tail", pcm.allSatisfy { $0[total...].allSatisfy { abs($0) < 0.000001 } })
            metrics = ["sample_rate": 44100, "channels": 2, "first_frames": firstCount, "second_frames": secondCount, "join_frame": firstCount, "payload_frames": total, "trailing_frames": 2048, "wrong_channel_frames": wrongFrames, "silent_payload_channel_frames": silentPayloadFrames, "max_absolute_sample_error": maxError, "boundary_left": Array(pcm[0][(firstCount - 4)..<(firstCount + 4)]), "final_tail_left": Array(pcm[0][(total - 4)..<(total + 4)])]
            audio.stop()
        } catch { check("unexpected error", false, String(describing: error)) }
        let failed = checks.filter { ($0["pass"] as? Bool) != true }.count
        let report: [String: Any] = ["passed": checks.count - failed, "failed": failed, "checks": checks, "metrics": metrics, "mode": "true offline manual rendering, master volume 1, EQ bypass, no hardware audio"]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output.appendingPathComponent("results.json")) }
        print("RESULT \(checks.count - failed)/\(checks.count) checks passed")
        exit(failed == 0 ? 0 : 1)
    }
}
