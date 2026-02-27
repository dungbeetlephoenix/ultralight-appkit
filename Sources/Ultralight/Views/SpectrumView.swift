import AppKit
import Combine

final class SpectrumView: NSView {
    private var cancellable: AnyCancellable?
    private var data: [Float] = Array(repeating: 0, count: 32)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x0a0a0a).cgColor

        cancellable = AppState.shared.$spectrumData
            .receive(on: RunLoop.main)
            .sink { [weak self] d in
                self?.data = d
                self?.needsDisplay = true
            }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard !data.isEmpty else { return }
        let barCount = data.count
        let barWidth = bounds.width / CGFloat(barCount)
        let gap: CGFloat = 1

        for i in 0..<barCount {
            let value = CGFloat(data[i])
            let barHeight = max(1, value * bounds.height)
            let x = CGFloat(i) * barWidth + gap / 2
            let rect = NSRect(x: x, y: 0, width: max(1, barWidth - gap), height: barHeight)
            let alpha = 0.3 + value * 0.7
            NSColor(hex: 0x4a9eff, alpha: alpha).setFill()
            rect.fill()
        }
    }
}
