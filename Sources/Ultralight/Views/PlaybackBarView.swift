import AppKit
import Combine

func makePlaybackBarView(frame: NSRect = .zero) -> NSView {
    let spectrumView = SpectrumView()
    let progressBar = ProgressBarView()
    let timeLabel = uiLabel("0:00")
    let durationLabel = uiLabel("0:00")
    let playBtn = uiButton("▶")
    let prevBtn = uiButton("⏮")
    let nextBtn = uiButton("⏭")
    let shfBtn = uiButton("⤮")
    let rptBtn = uiButton("↻")
    let eqBtn2 = uiButton("EQ")
    let volBar = ProgressBarView()
    let volPctLabel = uiLabel("80%")
    var cancellables = [AnyCancellable]()
    let panel = uiContainer(border: .maxY, frame: frame)
    uiBackground(panel, 0x0e0e0e)

    for lbl in [timeLabel, durationLabel] {
        uiStyleLabel(lbl, 10, .regular, 0x555555)
    }

    for btn in [prevBtn, nextBtn, shfBtn, rptBtn] {
        uiStyleButton(btn, 14, .regular, false, 0x555555)
    }

    uiStyleButton(playBtn, 14, .regular, false, 0xe0e0e0)
    uiBorder(playBtn, 0x333333)

    uiAction(playBtn) { AppState.shared.togglePlay() }
    uiAction(prevBtn) { AppState.shared.playPrevious() }
    uiAction(nextBtn) { AppState.shared.playNext() }
    uiAction(shfBtn) { AppState.shared.shuffle.toggle() }
    uiAction(rptBtn) { AppState.shared.repeatMode.toggle() }

    uiStyleButton(eqBtn2, 10, .medium, true, 0x4a9eff)
    uiAction(eqBtn2) { AppState.shared.showEQ.toggle() }

    volBar.color = NSColor(hex: 0x4a9eff)
    volBar.progress = 0.8
    volBar.onClick = { [weak volPctLabel] pct in
        AppState.shared.volume = Float(pct)
        volPctLabel?.stringValue = "\(Int(pct * 100))%"
    }

    uiStyleLabel(volPctLabel, 9, .regular, 0x555555)

    progressBar.color = NSColor(hex: 0x4a9eff)
    progressBar.onClick = { pct in
        AppState.shared.seek(to: AppState.shared.duration * pct)
    }

    // Layout
    spectrumView.translatesAutoresizingMaskIntoConstraints = false
    panel.addSubview(spectrumView)

    let progressStack = uiStack([timeLabel, progressBar, durationLabel], .horizontal, 6)

    let transportStack = uiStack([prevBtn, playBtn, nextBtn], .horizontal, 6)

    let volStack = uiStack([volBar, volPctLabel], .horizontal, 6)

    let spacer1 = NSView(); spacer1.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let spacer2 = NSView(); spacer2.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let controlsStack = uiStack([shfBtn, rptBtn, spacer1, transportStack, eqBtn2, spacer2, volStack], .horizontal, 8)

    let mainStack = uiStack([progressStack, controlsStack], .vertical, 4)
    mainStack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 6, right: 10)
    mainStack.translatesAutoresizingMaskIntoConstraints = false
    panel.addSubview(mainStack)

    uiAlign(spectrumView, .top, to: panel, offset: 4)
    uiAlign(spectrumView, .leading, to: panel, offset: 10)
    uiAlign(spectrumView, .trailing, to: panel, offset: -10)
    uiDimension(spectrumView, .height, 28)

    uiConstrain(mainStack, .top, spectrumView, .bottom, .equal, 4)
    uiAlign(mainStack, .leading, to: panel)
    uiAlign(mainStack, .trailing, to: panel)
    uiAlign(mainStack, .bottom, to: panel)

    uiDimension(progressBar, .height, 16)
    uiSize(playBtn, width: 32, height: 32)
    uiSize(volBar, width: 60, height: 4)
    // Keep transport beside EQ and volume; only the leading spacer expands.
    uiDimension(spacer2, .width, 0)

    let state = AppState.shared

    state.$currentTime.sinkOnMain { [weak panel] t in
        guard panel != nil else { return }
        timeLabel.stringValue = formatPlaybackTime(t)
        let dur = AppState.shared.duration
        progressBar.progress = dur > 0 ? t / dur : 0
    }.store(in: &cancellables)

    state.$duration.sinkOnMain { [weak panel] d in
        guard panel != nil else { return }
        durationLabel.stringValue = formatPlaybackTime(d)
    }.store(in: &cancellables)

    state.$isPlaying.sinkOnMain { [weak panel] p in
        guard panel != nil else { return }
        playBtn.title = p ? "⏸" : "▶"
    }.store(in: &cancellables)

    state.$shuffle.sinkOnMain { [weak panel] s in
        guard panel != nil else { return }
        shfBtn.contentTintColor = s ? NSColor(hex: 0x4a9eff) : NSColor(hex: 0x444444)
    }.store(in: &cancellables)

    state.$repeatMode.sinkOnMain { [weak panel] r in
        guard panel != nil else { return }
        rptBtn.contentTintColor = r ? NSColor(hex: 0x4a9eff) : NSColor(hex: 0x444444)
    }.store(in: &cancellables)

    state.$volume.sinkOnMain { [weak panel] v in
        guard panel != nil else { return }
        volBar.progress = Double(v)
        volPctLabel.stringValue = "\(Int(v * 100))%"
    }.store(in: &cancellables)

    state.$waveformData.sinkOnMain { [weak panel] w in
        guard panel != nil else { return }
        progressBar.waveformData = w
    }.store(in: &cancellables)

    uiRetain(cancellables, on: panel)
    return panel
}

private func formatPlaybackTime(_ s: Double) -> String {

    String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)

}

// Clickable progress/volume bar with optional waveform
final class ProgressBarView: NSView {
    var progress: Double = 0 { didSet { needsDisplay = true } }
    var color: NSColor = NSColor(hex: 0x4a9eff)
    var waveformData: [Float] = [] { didSet { needsDisplay = true } }
    var onClick: ((Double) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSColor(hex: 0x1a1a1a)
        bg.setFill()
        bounds.fill()

        if !waveformData.isEmpty {
            let barWidth = bounds.width / CGFloat(waveformData.count)
            let progressX = bounds.width * CGFloat(progress)
            let dim = NSColor(hex: 0x222222)

            for (i, peak) in waveformData.enumerated() {
                let x = CGFloat(i) * barWidth
                let h = max(1, bounds.height * CGFloat(peak))
                let y = (bounds.height - h) / 2
                let rect = NSRect(x: x, y: y, width: max(1, barWidth - 0.5), height: h)

                if x < progressX {
                    color.withAlphaComponent(0.6).setFill()
                } else {
                    dim.setFill()
                }
                rect.fill()
            }

            // Playhead line
            if progress > 0 {
                color.setFill()
                NSRect(x: progressX - 0.5, y: 0, width: 1, height: bounds.height).fill()
            }
        } else {
            // Flat bar fallback
            color.setFill()
            NSRect(x: 0, y: 0, width: bounds.width * CGFloat(progress), height: bounds.height).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let pct = max(0, min(1, Double(pt.x / bounds.width)))
        onClick?(pct)
    }

    override func mouseDragged(with event: NSEvent) {
        mouseDown(with: event)
    }
}
