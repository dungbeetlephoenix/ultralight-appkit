import AVFoundation
import Accelerate

enum AudioAnalyzer {
    /// Analyze the first ~2 seconds of an audio file for spectral characteristics.
    static func analyze(path: String) async -> AnalysisResult? {
        let url = URL(fileURLWithPath: path)
        guard let file = try? AVAudioFile(forReading: url) else { return nil }

        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let fftSize = 4096
        let framesToRead = AVAudioFrameCount(min(Double(file.length), sampleRate * 2))
        guard framesToRead >= fftSize,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else { return nil }
        do { try file.read(into: buffer, frameCount: framesToRead) } catch { return nil }
        guard let channels = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        guard frameCount >= fftSize, channelCount > 0 else { return nil }

        guard let spectrum = PowerSpectrum(log2Size: 12) else { return nil }
        let halfSize = fftSize / 2
        var energies = [Float](repeating: 0, count: halfSize + 1)
        var peak: Float = 0
        var meanSquare: Float = 0

        // Sum channel power separately so stereo phase cancellation cannot erase the spectrum.
        for channel in 0..<channelCount {
            let data = channels[channel]
            var channelPeak: Float = 0
            var channelMeanSquare: Float = 0
            vDSP_maxmgv(data, 1, &channelPeak, vDSP_Length(frameCount))
            vDSP_measqv(data, 1, &channelMeanSquare, vDSP_Length(frameCount))
            peak = max(peak, channelPeak)
            meanSquare += channelMeanSquare

            for offset in stride(from: 0, through: frameCount - fftSize, by: halfSize) {
                if Task.isCancelled { return nil }
                spectrum.add(data + offset, to: &energies)
            }
        }

        let binHz = Float(sampleRate) / Float(fftSize)
        let bassEnd = min(Int(250 / binHz), energies.count)
        let midEnd = min(Int(4000 / binHz), energies.count)
        let bassEnergy = energies[..<bassEnd].reduce(0, +)
        let midEnergy = energies[bassEnd..<midEnd].reduce(0, +)
        let trebleEnergy = energies[midEnd...].reduce(0, +)
        let totalEnergy = bassEnergy + midEnergy + trebleEnergy
        guard totalEnergy > 0, totalEnergy.isFinite else { return nil }

        let normBass = bassEnergy / totalEnergy
        let normMid = midEnergy / totalEnergy
        let normTreble = trebleEnergy / totalEnergy
        var centroid: Float = 0
        for i in energies.indices { centroid += Float(i) * binHz * energies[i] }
        centroid /= totalEnergy
        let peakDB = 20 * log10(max(peak, 1e-10))
        let rms = sqrt(meanSquare / Float(channelCount))
        let dynamicRange = 20 * log10(max(peak / max(rms, 1e-10), 1e-10))

        // Detection flags (matching Electron app's analysis)
        let crestFactor = peak / max(rms, 1e-10)
        let isBassHeavy = normBass > 0.45
        let isBright = centroid > 3000 || normTreble > 0.35
        let isCompressed = crestFactor < 4
        let isClipping = peak > 0.99
        let isDynamic = crestFactor > 8
        let isThin = normBass < 0.2
        let isMuddy = normMid > 0.5

        // Generate suggested EQ
        let suggestedEQ = generateAutoEQ(bass: normBass, mid: normMid, treble: normTreble, centroid: centroid)

        return AnalysisResult(
            bassEnergy: normBass,
            midEnergy: normMid,
            trebleEnergy: normTreble,
            spectralCentroid: centroid,
            dynamicRange: dynamicRange,
            peakLevel: peakDB,
            suggestedEQ: suggestedEQ,
            isBassHeavy: isBassHeavy,
            isBright: isBright,
            isCompressed: isCompressed,
            isClipping: isClipping,
            isDynamic: isDynamic,
            isThin: isThin,
            isMuddy: isMuddy
        )
    }

    static func computeWaveform(path: String, resolution: Int = 200) async -> [Float]? {
        guard resolution > 0,
              let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)),
              file.length > 0 else { return nil }
        let totalFrames = Int(file.length)
        let binCount = min(resolution, totalFrames)
        let framesPerBin = totalFrames / binCount
        let extraFrames = totalFrames % binCount
        let capacity = AVAudioFrameCount(min(16384, framesPerBin + 1))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else { return nil }
        var peaks = [Float](repeating: 0, count: binCount)

        // Read sequentially in bounded chunks, including every channel and the final frames.
        for i in peaks.indices {
            var remaining = framesPerBin + (i < extraFrames ? 1 : 0)
            while remaining > 0 {
                if Task.isCancelled { return nil }
                do { try file.read(into: buffer, frameCount: AVAudioFrameCount(min(remaining, Int(capacity)))) }
                catch { return nil }
                guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { return nil }
                for channel in 0..<Int(buffer.format.channelCount) {
                    var peak: Float = 0
                    vDSP_maxmgv(channels[channel], 1, &peak, vDSP_Length(buffer.frameLength))
                    peaks[i] = max(peaks[i], peak)
                }
                remaining -= Int(buffer.frameLength)
            }
        }
        var maxPeak: Float = 0
        vDSP_maxv(peaks, 1, &maxPeak, vDSP_Length(binCount))
        if maxPeak > 0 {
            vDSP_vsdiv(peaks, 1, &maxPeak, &peaks, 1, vDSP_Length(binCount))
        }
        return peaks
    }

    private static func generateAutoEQ(bass: Float, mid: Float, treble: Float, centroid: Float) -> EQProfile {
        var bands = EQBand.defaultBands

        // If bass-heavy, reduce low end slightly and open up highs
        if bass > 0.45 {
            bands[0].gain = -3
            bands[1].gain = -2
            bands[6].gain = 1.5
            bands[7].gain = 2
        }

        // If treble-heavy / bright, warm it up
        if treble > 0.35 || centroid > 5000 {
            bands[0].gain += 2
            bands[1].gain += 1.5
            bands[6].gain -= 2
            bands[7].gain -= 3
        }

        // If thin / lacking bass
        if bass < 0.2 {
            bands[0].gain += 3
            bands[1].gain += 2
            bands[2].gain += 1
        }

        // If muddy mids
        if mid > 0.5 {
            bands[3].gain -= 2
            bands[4].gain -= 1.5
        }

        // Clamp all gains
        for i in 0..<bands.count {
            bands[i].gain = max(-12, min(12, bands[i].gain))
        }

        return EQProfile(bands: bands, preamp: 0)
    }
}
