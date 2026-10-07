import AVFoundation
import Accelerate
import CoreAudio

struct OutputDevice {
    let id: AudioDeviceID
    let name: String
}

final class AudioEngine: ObservableObject {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 8)
    private let mixer = AVAudioMixerNode()

    private var audioFile: AVAudioFile?
    private var spectrumTap: Bool = false
    private var queuedFile: AVAudioFile?
    private var queuedPath: String?
    private var sampleOffset: AVAudioFramePosition = 0

    private var isSwitchingTracks = false

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
            guard let self = self else { return }
            self.processSpectrum(buffer: buffer)
        }
        spectrumTap = true
    }

    private func processSpectrum(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let log2n = vDSP_Length(log2(Float(frameCount)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let halfCount = frameCount / 2

        var windowed = [Float](repeating: 0, count: frameCount)
        var window = [Float](repeating: 0, count: frameCount)
        vDSP_hann_window(&window, vDSP_Length(frameCount), Int32(vDSP_HANN_NORM))
        vDSP_vmul(channelData, 1, window, 1, &windowed, 1, vDSP_Length(frameCount))

        var realPart = [Float](repeating: 0, count: halfCount)
        var imagPart = [Float](repeating: 0, count: halfCount)
        var magnitudes = [Float](repeating: 0, count: halfCount)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                windowed.withUnsafeBufferPointer { windPtr in
                    windPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfCount) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfCount))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfCount))
            }
        }

        let bandCount = 32
        var bands = [Float](repeating: 0, count: bandCount)

        magnitudes.withUnsafeBufferPointer { magPtr in
            let base = magPtr.baseAddress!
            for i in 0..<bandCount {
                let start = i * halfCount / bandCount
                let end = (i + 1) * halfCount / bandCount
                guard end > start else { continue }
                var sum: Float = 0
                vDSP_sve(base + start, 1, &sum, vDSP_Length(end - start))
                let avg = sum / Float(end - start)
                let db = 10 * log10(max(avg, 1e-10))
                bands[i] = max(0, min(1, (db + 60) / 60))
            }
        }

        onSpectrumData?(bands)
    }

    // MARK: - Playback

    func loadAndPlay(path: String) throws {
        isSwitchingTracks = true
        playerNode.stop()
        queuedFile = nil
        queuedPath = nil
        sampleOffset = 0

        let url = URL(fileURLWithPath: path)
        audioFile = try AVAudioFile(forReading: url)
        guard let file = audioFile else { return }

        let processingFormat = file.processingFormat
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(eq)
        engine.disconnectNodeOutput(mixer)
        engine.connect(playerNode, to: eq, format: processingFormat)
        engine.connect(eq, to: mixer, format: processingFormat)
        engine.connect(mixer, to: engine.mainMixerNode, format: processingFormat)

        if !engine.isRunning {
            try engine.start()
        }

        isSwitchingTracks = false

        playerNode.scheduleFile(file, at: nil) { [weak self] in
            guard let self = self, !self.isSwitchingTracks else { return }
            if let qf = self.queuedFile, let qp = self.queuedPath {
                self.sampleOffset += file.length
                self.audioFile = qf
                self.queuedFile = nil
                self.queuedPath = nil
                DispatchQueue.main.async { self.onTrackAdvanced?(qp) }
            } else {
                DispatchQueue.main.async { self.onTrackFinished?() }
            }
        }
        playerNode.play()
    }

    func pause() {
        playerNode.pause()
    }

    func resume() {
        playerNode.play()
    }

    func stop() {
        isSwitchingTracks = true
        playerNode.stop()
        audioFile = nil
        queuedFile = nil
        queuedPath = nil
        sampleOffset = 0
    }

    func seek(to time: Double) {
        guard let file = audioFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        let targetFrame = AVAudioFramePosition(time * sampleRate)
        let totalFrames = file.length
        guard targetFrame < totalFrames else { return }

        isSwitchingTracks = true
        playerNode.stop()
        queuedFile = nil
        queuedPath = nil
        sampleOffset = 0
        isSwitchingTracks = false

        let remainingFrames = AVAudioFrameCount(totalFrames - targetFrame)
        playerNode.scheduleSegment(file, startingFrame: targetFrame, frameCount: remainingFrames, at: nil) { [weak self] in
            guard let self = self, !self.isSwitchingTracks else { return }
            DispatchQueue.main.async { self.onTrackFinished?() }
        }
        playerNode.play()
    }

    var isPlaying: Bool {
        playerNode.isPlaying
    }

    var currentTime: Double {
        guard audioFile != nil,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return 0 }
        return Double(playerTime.sampleTime - sampleOffset) / playerTime.sampleRate
    }

    var duration: Double {
        guard let file = audioFile else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    // MARK: - Gapless

    func queueNext(path: String) -> Bool {
        guard let currentFile = audioFile else { return false }
        guard let nextFile = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return false }
        guard nextFile.processingFormat.sampleRate == currentFile.processingFormat.sampleRate,
              nextFile.processingFormat.channelCount == currentFile.processingFormat.channelCount else { return false }

        queuedFile = nextFile
        queuedPath = path

        playerNode.scheduleFile(nextFile, at: nil) { [weak self] in
            guard let self = self, !self.isSwitchingTracks else { return }
            if let qf = self.queuedFile, let qp = self.queuedPath {
                self.sampleOffset += nextFile.length
                self.audioFile = qf
                self.queuedFile = nil
                self.queuedPath = nil
                DispatchQueue.main.async { self.onTrackAdvanced?(qp) }
            } else {
                DispatchQueue.main.async { self.onTrackFinished?() }
            }
        }
        return true
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
        for band in eq.bands {
            band.bypass = bypassed
        }
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
