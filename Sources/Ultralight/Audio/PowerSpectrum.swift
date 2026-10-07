import Accelerate

/// A reusable real FFT. Each instance belongs to one serial analysis/render context.
final class PowerSpectrum {
    private(set) var size: Int
    private let maxLog2Size: vDSP_Length
    private var log2Size: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var magnitudes: [Float]

    init?(log2Size: vDSP_Length) {
        guard let setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2)) else { return nil }
        self.setup = setup
        self.log2Size = log2Size
        self.maxLog2Size = log2Size
        size = 1 << log2Size
        window = [Float](repeating: 0, count: size)
        windowed = window
        real = [Float](repeating: 0, count: size / 2)
        imaginary = [Float](repeating: 0, count: size / 2)
        magnitudes = [Float](repeating: 0, count: size / 2 + 1)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Use the largest complete power-of-two window available, capped at plan capacity.
    func fit(frameCount: Int) {
        let exponent = min(maxLog2Size, vDSP_Length(Int.bitWidth - 1 - frameCount.leadingZeroBitCount))
        if exponent != log2Size {
            log2Size = exponent
            size = 1 << exponent
            vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        }
    }

    /// Add one complete window's power to bins 0...Nyquist; input must contain size samples.
    @inline(never) func add(_ input: UnsafePointer<Float>, to power: inout [Float]) {
        let half = size / 2
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(size))
        real.withUnsafeMutableBufferPointer { r in
            imaginary.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                windowed.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2Size, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        // Real FFT packs Nyquist in imag[0]; endpoints have half the one-sided weight.
        magnitudes[0] = real[0] * real[0] * 0.5
        magnitudes[half] = imaginary[0] * imaginary[0] * 0.5
        // One mutable borrow avoids the copy-on-write allocation caused by
        // passing the same Array as both a value input and an inout output.
        power.withUnsafeMutableBufferPointer {
            vDSP_vadd($0.baseAddress!, 1, magnitudes, 1, $0.baseAddress!, 1, vDSP_Length(half + 1))
        }
    }
}
