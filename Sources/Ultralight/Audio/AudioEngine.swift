import AVFoundation
import Accelerate
import CoreAudio

struct OutputDevice {
    let id: AudioDeviceID
    let name: String
}

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 8)
    private let mixer = AVAudioMixerNode()

    private var audioFile: AVAudioFile?
    private var spectrumTap: Bool = false
    private let spectrum = PowerSpectrum(log2Size: 10)
    private var spectrumPower = [Float](repeating: 0, count: 513)
    private var queuedFile: AVAudioFile?
    private var queuedPath: String?
    private var sampleOffset: AVAudioFramePosition = 0
    private var startFrame: AVAudioFramePosition = 0
    private var pausedSampleTime: AVAudioFramePosition?
    // Completion handlers may arrive after stop(). A generation belongs to one
    // uninterrupted schedule, and is checked on the main thread before mutation.
    private var generation: UInt = 0

    var onSpectrumData: (([Float]) -> Void)?
    var onTrackFinished: (() -> Void)?
    var onTrackAdvanced: ((String) -> Void)?

    private let eqFrequencies: [Float] = [60, 170, 310, 600, 1000, 3000, 6000, 12000]

    init() {
        setupGraph()
    }

    private func setupGraph() {
        engine.attach(playerNode)
        engine.attach(eq)
        engine.attach(mixer)

        for (i, band) in eq.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = eqFrequencies[i]
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.connect(playerNode, to: eq, format: format)
        engine.connect(eq, to: mixer, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: format)

        installSpectrumTap()
    }

    private func installSpectrumTap() {
        let bufferSize: AVAudioFrameCount = 1024
        mixer.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
            guard let self, self.playerNode.isPlaying else { return }
            self.processSpectrum(buffer: buffer)
        }
        spectrumTap = true
    }

    private func processSpectrum(buffer: AVAudioPCMBuffer) {
        guard let spectrum, buffer.frameLength >= 2,
              let channels = buffer.floatChannelData else { return }
        spectrum.fit(frameCount: Int(buffer.frameLength))
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return }
        vDSP_vclr(&spectrumPower, 1, vDSP_Length(spectrumPower.count))
        for channel in 0..<channelCount { spectrum.add(channels[channel], to: &spectrumPower) }

        let halfCount = spectrum.size / 2
        let bandCount = 32
        var bands = [Float](repeating: 0, count: bandCount)
        spectrumPower.withUnsafeBufferPointer { power in
            for i in 0..<bandCount {
                let start = i * halfCount / bandCount
                let end = i == bandCount - 1 ? halfCount + 1 : (i + 1) * halfCount / bandCount
                guard end > start else { continue }
                var sum: Float = 0
                vDSP_sve(power.baseAddress! + start, 1, &sum, vDSP_Length(end - start))
                let avg = sum / Float((end - start) * channelCount)
                let db = 10 * log10(max(avg, 1e-10))
                bands[i] = max(0, min(1, (db + 60) / 60))
            }
        }
        onSpectrumData?(bands)
    }

    // MARK: - Playback

    func loadAndPlay(path: String) throws {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        guard file.length > 0 else { throw CocoaError(.fileReadCorruptFile) }
        generation &+= 1
        playerNode.stop()
        queuedFile = nil
        queuedPath = nil
        sampleOffset = 0
        startFrame = 0
        pausedSampleTime = nil
        audioFile = file

        let processingFormat = file.processingFormat
        if playerNode.outputFormat(forBus: 0) != processingFormat {
            engine.stop()
            if spectrumTap { mixer.removeTap(onBus: 0); spectrumTap = false }
            engine.disconnectNodeOutput(playerNode)
            engine.disconnectNodeOutput(eq)
            engine.disconnectNodeOutput(mixer)
            engine.connect(playerNode, to: eq, format: processingFormat)
            engine.connect(eq, to: mixer, format: processingFormat)
            engine.connect(mixer, to: engine.mainMixerNode, format: processingFormat)
            installSpectrumTap()
        }

        if !engine.isRunning {
            try engine.start()
        }

        schedule(file)
        playerNode.play()
    }

    func pause() {
        pausedSampleTime = pausedSampleTime ?? renderedSampleTime
        playerNode.pause()
    }

    func resume() throws {
        guard audioFile != nil else { return }
        if !engine.isRunning { try engine.start() }
        playerNode.play()
        pausedSampleTime = nil
    }

    func stop() {
        generation &+= 1
        playerNode.stop()
        audioFile = nil
        queuedFile = nil
        queuedPath = nil
        sampleOffset = 0
        startFrame = 0
        pausedSampleTime = nil
        engine.pause()
    }

    func seek(to time: Double) {
        guard let file = audioFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        guard time.isFinite else { return }
        let totalFrames = file.length
        guard totalFrames > 0 else { return }
        let targetFrame = AVAudioFramePosition(min(Double(totalFrames - 1), max(0, time * sampleRate)))
        let wasPlaying = playerNode.isPlaying

        generation &+= 1
        playerNode.stop()
        queuedFile = nil
        queuedPath = nil
        sampleOffset = 0
        startFrame = targetFrame
        pausedSampleTime = wasPlaying ? nil : 0
        schedule(file, from: targetFrame)
        if wasPlaying { playerNode.play() }
    }

    var isPlaying: Bool {
        playerNode.isPlaying
    }

    private var renderedSampleTime: AVAudioFramePosition {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return 0 }
        return playerTime.sampleTime
    }

    var currentTime: Double {
        guard let file = audioFile else { return 0 }
        // Preserve the player timeline while paused. A queued completion can
        // still advance tracks, so only convert to track-relative time here.
        let sampleTime = pausedSampleTime ?? renderedSampleTime
        let frame = startFrame + max(0, sampleTime - sampleOffset)
        return min(duration, Double(frame) / file.processingFormat.sampleRate)
    }

    var duration: Double {
        guard let file = audioFile else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    // MARK: - Gapless

    func queueNext(path: String) -> Bool {
        if queuedPath == path { return true }
        clearQueuedTrack()
        guard let currentFile = audioFile else { return false }
        guard let nextFile = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return false }
        guard nextFile.length > 0 else { return false }
        guard nextFile.processingFormat.sampleRate == currentFile.processingFormat.sampleRate,
              nextFile.processingFormat.channelCount == currentFile.processingFormat.channelCount else { return false }

        queuedFile = nextFile
        queuedPath = path

        schedule(nextFile)
        return true
    }

    func clearQueuedTrack() {
        // AVAudioPlayerNode cannot unschedule just one file. Rebuild the current
        // segment at the same position, preserving pause state.
        if queuedFile != nil { seek(to: currentTime) }
    }

    private func schedule(_ file: AVAudioFile, from frame: AVAudioFramePosition = 0) {
        let token = generation
        let completion: AVAudioPlayerNodeCompletionHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                if let next = self.queuedFile, let path = self.queuedPath {
                    self.sampleOffset += file.length - frame
                    self.startFrame = 0
                    self.audioFile = next
                    self.queuedFile = nil
                    self.queuedPath = nil
                    self.onTrackAdvanced?(path)
                } else {
                    self.onTrackFinished?()
                }
            }
        }
        if frame == 0 {
            playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack, completionHandler: completion)
        } else {
            // Split unusually long recordings without truncating their tail.
            var cursor = frame
            while cursor < file.length {
                let count = AVAudioFrameCount(min(file.length - cursor, Int64(UInt32.max)))
                let last = cursor + Int64(count) == file.length
                playerNode.scheduleSegment(file, startingFrame: cursor, frameCount: count, at: nil,
                    completionCallbackType: .dataPlayedBack, completionHandler: last ? completion : nil)
                cursor += Int64(count)
            }
        }
    }

    // MARK: - EQ

    func applyEQ(_ profile: EQProfile) {
        for (i, band) in profile.bands.enumerated() where i < eq.bands.count {
            eq.bands[i].gain = band.gain
            eq.bands[i].bandwidth = band.bandwidth
        }
        eq.globalGain = profile.preamp
    }

    func setEQBypassed(_ bypassed: Bool) {
        eq.bypass = bypassed
    }

    // MARK: - Volume

    func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
    }

    // MARK: - Output Device

    static func outputDevices() -> [OutputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            let bufSize = Int(streamSize)
            let layout = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { layout.deallocate() }
            guard AudioObjectGetPropertyData(id, &streamAddr, 0, nil, &streamSize, layout) == noErr else { return nil }
            let abl = layout.assumingMemoryBound(to: AudioBufferList.self)
            let channels = UnsafeMutableAudioBufferListPointer(abl).reduce(0) { $0 + Int($1.mNumberChannels) }
            guard channels > 0 else { return nil }

            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &name)
            return OutputDevice(id: id, name: name as String)
        }
    }

    func setOutputDevice(_ deviceID: AudioDeviceID) {
        var id = deviceID
        guard let au = engine.outputNode.audioUnit else { return }
        AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0, &id,
                             UInt32(MemoryLayout<AudioDeviceID>.size))
    }
}
