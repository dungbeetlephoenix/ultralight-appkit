// Appended only to the temporary AudioEngine source copy; never ships.
extension AudioEngine {
    func auditEnableOffline() throws {
        if ProcessInfo.processInfo.environment["ULTRALIGHT_PLAYBACK_AUDIT_MODE"] == "offline" {
            try engine.enableManualRenderingMode(.offline, format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!, maximumFrameCount: 512)
        }
        setVolume(0)
    }
    var auditManualMode: Bool { engine.isInManualRenderingMode }
    var auditVolume: Float { engine.mainMixerNode.outputVolume }
    var auditQueuedPath: String? { queuedPath }
    var auditPath: String? { audioFile?.url.path }
    @discardableResult func auditRender(_ seconds: Double) throws -> Double {
        if !engine.isInManualRenderingMode {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
            guard auditVolume == 0 else { throw NSError(domain: "PlaybackAuditUnexpectedVolume", code: 5) }
            return seconds
        }
        let rate = engine.manualRenderingFormat.sampleRate
        let target = Int64(seconds * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)!
        var done: Int64 = 0
        var retries = 0
        while done < target {
            let count = AVAudioFrameCount(min(512, target - done))
            let status = try engine.renderOffline(count, to: buffer)
            switch status {
            case .success, .insufficientDataFromInputNode:
                done += Int64(buffer.frameLength)
                retries = 0
                if let channels = buffer.floatChannelData {
                    for channel in 0..<Int(buffer.format.channelCount) {
                        for i in 0..<Int(buffer.frameLength) where channels[channel][i] != 0 {
                            throw NSError(domain: "PlaybackAuditUnexpectedOutput", code: 1)
                        }
                    }
                }
            case .cannotDoInCurrentContext: retries += 1
            case .error: throw NSError(domain: "PlaybackAuditRender", code: 2)
            @unknown default: throw NSError(domain: "PlaybackAuditRender", code: 3)
            }
            if retries > 100 { throw NSError(domain: "PlaybackAuditRenderRetries", code: 4) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        return Double(done) / rate
    }
}
