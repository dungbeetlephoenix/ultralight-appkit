import AppKit
import AVFoundation
import Combine

@main
struct CompatibilitySmoke {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ULTRALIGHT_COMPAT_DATA"]!)
        var checks: [[String: Any]] = []
        func check(_ name: String, _ pass: Bool) {
            checks.append(["name": name, "pass": pass])
            print("\(pass ? "PASS" : "FAIL") \(name)")
        }
        _ = NSApplication.shared
        let state = AppState.shared
        check("fresh isolated settings", state.folders.isEmpty)
        let window = MainWindow()
        window.contentView?.layoutSubtreeIfNeeded()
        check("AppKit window construction", window.contentView?.subviews.isEmpty == false)
        check("player remains silent", !state.isPlaying)
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let controls = descendants(window.contentView!).compactMap { $0 as? NSControl }
        if let volume = controls.first(where: { $0.cell?.accessibilityLabel() == "Volume, percent" }),
           let element = NSAccessibility.unignoredDescendant(of: volume) as? NSCell {
            check("native slider accessibility", element.accessibilityRole() == .slider
                  && element.accessibilityActionNames().contains(.increment))
            let previous = state.volume
            element.accessibilityPerformAction(.increment)
            check("accessible adjustment reaches model", state.volume > previous)
        } else { check("native slider accessibility", false) }
        var observed = false
        let token = state.objectWillChange.sink { observed = true }
        state.showEQ.toggle()
        check("Combine reflection and delivery", observed)
        withExtendedLifetime(token) {}
        if let view = window.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            check("native drawing", bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        } else { check("native drawing", false) }
        let icon = NSImage(contentsOfFile: CommandLine.arguments[1])
        check("application icon decodes", icon?.isValid == true)
        let fixtures = root.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        let path = fixtures.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        for i in 0..<1024 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * .pi / 8) * 0.1) }
        do {
            let file = try AVAudioFile(forWriting: path, settings: format.settings)
            try file.write(from: buffer)
        }
        let decodedFile = try AVAudioFile(forReading: path)
        let decoded = AVAudioPCMBuffer(pcmFormat: decodedFile.processingFormat, frameCapacity: 1024)!
        try decodedFile.read(into: decoded)
        check("native audio samples decode", decoded.frameLength == 1024 && (0..<1024).allSatisfy {
            abs(decoded.floatChannelData![0][$0] - buffer.floatChannelData![0][$0]) < 0.000001
        })
        let tracks = await FolderScanner.scan(folders: [fixtures.path])
        check("asynchronous native metadata", tracks.count == 1 && abs((tracks.first?.duration ?? 0) - 0.064) < 0.001)
        check("native scanner canonical path", tracks.first?.path == path.resolvingSymlinksInPath().path)
        let report: [String: Any] = ["passed": checks.allSatisfy { $0["pass"] as? Bool == true }, "checks": checks]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("results.json"))
        if report["passed"] as? Bool != true { exit(1) }
    }
}
