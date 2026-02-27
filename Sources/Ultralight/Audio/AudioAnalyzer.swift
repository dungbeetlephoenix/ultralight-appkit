import AVFoundation
import Accelerate

enum AudioAnalyzer {
    /// Analyze the first ~2 seconds of an audio file for spectral characteristics.
    static func analyze(path: String) async -> AnalysisResult? {
        let url = URL(fileURLWithPath: path)
        guard let file = try? AVAudioFile(forReading: url) else { return nil }

        let format = file.processingFormat
        let sampleRate = format.sampleRate
        // Read up to 2 seconds
        let framesToRead = AVAudioFrameCount(min(Double(file.length), sampleRate * 2))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else { return nil }

        do {
            try file.read(into: buffer, frameCount: framesToRead)
        } catch { return nil }

        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(buffer.frameLength)
        guard frameCount >= 1024 else { return nil }

        // FFT
        let fftSize = 4096
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let halfSize = fftSize / 2
        var avgMagnitudes = [Float](repeating: 0, count: halfSize)
        var windowCount = 0

        // Process in overlapping windows
        var offset = 0
        while offset + fftSize <= frameCount {
            var windowed = [Float](repeating: 0, count: fftSize)
            var window = [Float](repeating: 0, count: fftSize)
            vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
            vDSP_vmul(channelData + offset, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

            var realPart = [Float](repeating: 0, count: halfSize)
            var imagPart = [Float](repeating: 0, count: halfSize)
            var magnitudes = [Float](repeating: 0, count: halfSize)

            realPart.withUnsafeMutableBufferPointer { realBuf in
                imagPart.withUnsafeMutableBufferPointer { imagBuf in
                    var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    windowed.withUnsafeBufferPointer { wPtr in
                        wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cPtr in
                            vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfSize))
                        }
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
                }
            }

            // Accumulate
            vDSP_vadd(avgMagnitudes, 1, magnitudes, 1, &avgMagnitudes, 1, vDSP_Length(halfSize))
            windowCount += 1
            offset += fftSize / 2 // 50% overlap
        }

        guard windowCount > 0 else { return nil }

        // Average
        var divisor = Float(windowCount)
        vDSP_vsdiv(avgMagnitudes, 1, &divisor, &avgMagnitudes, 1, vDSP_Length(halfSize))

        // Calculate energy in bands
        let binHz = Float(sampleRate) / Float(fftSize)
        let bassEnd = Int(250 / binHz)
        let midEnd = Int(4000 / binHz)

        let bassEnergy = avgMagnitudes[0..<min(bassEnd, halfSize)].reduce(0, +)
        let midEnergy = avgMagnitudes[min(bassEnd, halfSize)..<min(midEnd, halfSize)].reduce(0, +)
        let trebleEnergy = avgMagnitudes[min(midEnd, halfSize)..<halfSize].reduce(0, +)
        let totalEnergy = bassEnergy + midEnergy + trebleEnergy
        guard totalEnergy > 0 else { return nil }

        let normBass = bassEnergy / totalEnergy
        let normMid = midEnergy / totalEnergy
        let normTreble = trebleEnergy / totalEnergy

        // Spectral centroid
        var centroid: Float = 0
        for i in 0..<halfSize {
            centroid += Float(i) * binHz * avgMagnitudes[i]
        }
        centroid /= totalEnergy

        // Peak level (dB)
        var peak: Float = 0
        vDSP_maxv(channelData, 1, &peak, vDSP_Length(frameCount))
        let peakDB = 20 * log10(max(peak, 1e-10))

        // Dynamic range (rough estimate from RMS vs peak)
        var rmsSquared: Float = 0
        vDSP_measqv(channelData, 1, &rmsSquared, vDSP_Length(frameCount))
        let rms = sqrt(rmsSquared)
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
