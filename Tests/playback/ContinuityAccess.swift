// Test-only same-file access; source copy is never shipped.
extension AudioEngine {
    func auditEnableContinuityRender() throws {
        try engine.enableManualRenderingMode(.offline, format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!, maximumFrameCount: 512)
        setVolume(1)
        var nonflat = EQProfile.flat
        nonflat.preamp = 6
        nonflat.bands[0].gain = 8
        applyEQ(nonflat)
        setEQBypassed(true)
    }
    var auditContinuityMode: Bool { engine.isInManualRenderingMode && engine.manualRenderingMode == .offline }
    var auditBypassRetainsProfile: Bool { eq.bypass && eq.globalGain == 6 && eq.bands[0].gain == 8 }
    func auditCaptureFrames(_ count: Int) throws -> [[Float]] {
        precondition(auditContinuityMode)
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)!
        var output = [[Float]](repeating: [], count: Int(buffer.format.channelCount))
        var done = 0
        var retries = 0
        while done < count {
            let status = try engine.renderOffline(AVAudioFrameCount(min(512, count - done)), to: buffer)
            switch status {
            case .success, .insufficientDataFromInputNode:
                guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { throw NSError(domain: "ContinuityNoPCM", code: 1) }
                for channel in output.indices { output[channel].append(contentsOf: UnsafeBufferPointer(start: channels[channel], count: Int(buffer.frameLength))) }
                done += Int(buffer.frameLength)
                retries = 0
            case .cannotDoInCurrentContext: retries += 1
            case .error: throw NSError(domain: "ContinuityRenderError", code: 2)
            @unknown default: throw NSError(domain: "ContinuityUnknownStatus", code: 3)
            }
            if retries > 100 { throw NSError(domain: "ContinuityRetries", code: 4) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        return output
    }
}
