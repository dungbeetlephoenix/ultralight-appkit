import AVFoundation
import Accelerate
import Foundation
@_silgen_name("reset_allocations") func resetAllocations()
@_silgen_name("stop_allocations") func stopAllocations() -> UInt
@_silgen_name("use_pointer") func usePointer(_ p: UnsafeMutableRawPointer)

@main struct AllocationAudit {
    static func main() throws {
        let iterations = 10_000
        let plan = PowerSpectrum(log2Size: 10)!
        let input = (0..<1024).map { sin(Float($0) * 0.17) }
        var power = [Float](repeating: 0, count: 513)
        var kernelAllocations: UInt = 0
        input.withUnsafeBufferPointer { data in
            for _ in 0..<100 { plan.add(data.baseAddress!, to: &power) }
            resetAllocations()
            for i in 0..<iterations {
                plan.fit(frameCount: i % 2 == 0 ? 512 : 1024)
                vDSP_vclr(&power, 1, 513)
                plan.add(data.baseAddress!, to: &power)
            }
            kernelAllocations = stopAllocations()
        }

        let engine = AudioEngine()
        var visiblePower: Float = 0
        var callbacks = 0
        engine.onSpectrumData = { visiblePower += $0[0]; callbacks += 1 }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        for i in 0..<1024 {
            buffer.floatChannelData![0][i] = input[i]
            buffer.floatChannelData![1][i] = -input[i]
        }
        for _ in 0..<100 { engine.allocationSpectrum(buffer) }
        callbacks = 0
        resetAllocations()
        for _ in 0..<iterations { engine.allocationSpectrum(buffer) }
        let liveAllocations = stopAllocations()

        // Prove interception is active; unused allocations could otherwise give a false pass.
        resetAllocations()
        let probe = UnsafeMutableRawPointer.allocate(byteCount: 1024, alignment: 16)
        usePointer(probe)
        let calibrationAllocations = stopAllocations()
        probe.deallocate()
        let kernelPower = power.reduce(0, +)
        let passed = calibrationAllocations > 0 && kernelAllocations == 0 &&
            kernelPower.isFinite && kernelPower > 0 &&
            liveAllocations <= iterations && callbacks == iterations && visiblePower.isFinite && visiblePower > 0
        let report: [String: Any] = ["passed": passed, "iterations": iterations,
            "calibration_allocations": calibrationAllocations, "kernel_allocations": kernelAllocations,
            "live_allocations": liveAllocations, "live_output_allocation_budget": iterations,
            "callbacks": callbacks, "kernel_power": kernelPower,
            "allocation_scope": "calling_thread", "audible_playback": false]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
        exit(passed ? 0 : 1)
    }
}
