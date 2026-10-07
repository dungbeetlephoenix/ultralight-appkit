import AppKit
import Combine

func makeEQPanelView(frame: NSRect = .zero) -> NSView {
    let labels = ["60", "170", "310", "600", "1K", "3K", "6K", "12K"]
    let preampBar = ProgressBarView()
    let preampLabel = uiLabel("+0")
    let reasonLabel = uiLabel("")
    let badgeContainer = NSStackView()
    let statsLabel = uiLabel("")
    var cancellables = [AnyCancellable]()
    let panel = uiContainer(border: .minX, frame: frame)
    uiBackground(panel, 0x0e0e0e)

    // Header
    let headerBg = NSView()
    uiBackground(headerBg, 0x111111)

    let eqLabel = uiLabel("EQ")
    uiStyleLabel(eqLabel, 10, .bold, 0xcccccc)

    let autoBtn = makeEQButton("AUTO") { AppState.shared.eqBypassed.toggle() }
    autoBtn.contentTintColor = NSColor(hex: 0x4a9eff)
    autoBtn.layer?.borderColor = NSColor(hex: 0x4a9eff).cgColor
    let rstBtn = makeEQButton("RST") { AppState.shared.eqProfile = .flat }
    let saveBtn = makeEQButton("SAVE") { AppState.shared.saveEQForCurrentTrack() }
    let btnStack = uiStack([autoBtn, rstBtn, saveBtn], .horizontal, 4)

    let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let headerStack = NSStackView(views: [eqLabel, spacer, btnStack])
    headerStack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

    // Sliders
    let sliderStack = NSStackView()
    sliderStack.orientation = .horizontal
    sliderStack.distribution = .fillEqually
    sliderStack.spacing = 1

    let sliders = labels.enumerated().map { EQSliderView(label: $0.element, index: $0.offset) }
    for slider in sliders { sliderStack.addArrangedSubview(slider) }

    // Preamp
    preampBar.color = NSColor(hex: 0x4a9eff)
    preampBar.onClick = { pct in
        AppState.shared.eqProfile.preamp = Float(pct) * 24 - 12
    }

    let preLabel = uiLabel("PRE")
    uiStyleLabel(preLabel, 7, .regular, 0x333333)

    uiStyleLabel(preampLabel, 7, .regular, 0x333333)

    let preStack = uiStack([preLabel, preampBar, preampLabel], .horizontal, 4)
    preStack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    uiConstrain(preampBar, .width, nil, .notAnAttribute, .greaterThanOrEqual, 50)
    uiDimension(preampBar, .height, 4)

    // Analysis
    uiStyleLabel(reasonLabel, 9, .medium, 0xcccccc)
    reasonLabel.lineBreakMode = .byWordWrapping
    reasonLabel.maximumNumberOfLines = 2

    badgeContainer.orientation = .horizontal
    badgeContainer.spacing = 3
    badgeContainer.alignment = .centerY

    uiStyleLabel(statsLabel, 7, .regular, 0x333333)

    let analysisStack = NSStackView(views: [reasonLabel, badgeContainer, statsLabel])
    analysisStack.orientation = .vertical
    analysisStack.alignment = .leading
    analysisStack.spacing = 2
    analysisStack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

    // Main layout
    let mainStack = uiStack([headerBg, sliderStack, preStack, analysisStack], .vertical, 0)
    mainStack.translatesAutoresizingMaskIntoConstraints = false
    panel.addSubview(mainStack)

    headerBg.translatesAutoresizingMaskIntoConstraints = false
    headerStack.translatesAutoresizingMaskIntoConstraints = false
    headerBg.addSubview(headerStack)

    uiAlign(mainStack, .top, to: panel)
    uiAlign(mainStack, .leading, to: panel)
    uiAlign(mainStack, .trailing, to: panel)
    uiDimension(headerBg, .height, 28)
    uiFill(headerStack, in: headerBg)
    uiDimension(sliderStack, .height, 110)

    let state = AppState.shared

    state.$eqProfile.sinkOnMain { [weak panel] profile in
        guard panel != nil else { return }
        for (i, slider) in sliders.enumerated() where i < profile.bands.count {
            slider.value = profile.bands[i].gain
        }
        preampBar.progress = Double((profile.preamp + 12) / 24)
        preampLabel.stringValue = String(format: "%+.0f", profile.preamp)
    }.store(in: &cancellables)

    Publishers.CombineLatest(state.$currentTrack, state.$eqProfile)
        .sinkOnMain { [weak panel] track, _ in guard panel != nil else { return }; updateAnalysis(track: track, reasonLabel: reasonLabel, badgeContainer: badgeContainer, statsLabel: statsLabel) }
        .store(in: &cancellables)

    uiRetain(cancellables, on: panel)
    return panel
}

private func updateAnalysis(track: Track?, reasonLabel: NSTextField, badgeContainer: NSStackView, statsLabel: NSTextField) {

    guard let track, let a = AnalysisStore.result(for: track.id) else {
        reasonLabel.stringValue = ""
        badgeContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statsLabel.stringValue = ""
        return
    }

    reasonLabel.stringValue = a.reason

    badgeContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let flags: [(Bool, String, UInt)] = [
        (a.isBassHeavy, "BASS-HEAVY", 0xf59e0b),
        (a.isThin, "THIN", 0x8b5cf6),
        (a.isMuddy, "MUDDY", 0xef4444),
        (a.isBright, "BRIGHT", 0x06b6d4),
        (a.isCompressed, "COMPRESSED", 0xf97316),
        (a.isDynamic, "DYNAMIC", 0x4ade80),
        (a.isClipping, "CLIPPING", 0xef4444),
    ]
    var any = false
    for (flag, label, color) in flags where flag {
        badgeContainer.addArrangedSubview(makeEQBadge(label, color: color))
        any = true
    }
    if !any {
        badgeContainer.addArrangedSubview(makeEQBadge("BALANCED", color: 0x4ade80))
    }

    statsLabel.stringValue = "bass \(Int(a.bassEnergy * 100))%  mid \(Int(a.midEnergy * 100))%  treble \(Int(a.trebleEnergy * 100))%  peak \(String(format: "%.0f", a.peakLevel))dB"

}

private func makeEQButton(_ title: String, action: @escaping () -> Void) -> NSButton {

    let btn = uiButton(title)
    uiStyleButton(btn, 8, .regular, true, 0x444444)
    uiBorder(btn, 0x222222)
    uiAction(btn, action)
    return btn

}

private func makeEQBadge(_ text: String, color: UInt) -> NSView {

    let label = uiLabel(text)
    uiStyleLabel(label, 7, .bold, color)
    uiBackground(label, color, alpha: 0.12)
    label.layer?.borderColor = NSColor(hex: color, alpha: 0.25).cgColor
    label.layer?.borderWidth = 1
    return label

}

// Individual EQ band slider
final class EQSliderView: NSView {
    var value: Float = 0 { didSet { needsDisplay = true; gainLabel.stringValue = String(format: "%+.0f", value) } }
    private let gainLabel = uiLabel("+0")
    private let index: Int

    init(label: String, index: Int) {
        self.index = index
        let freqLabel = uiLabel(label)
        super.init(frame: .zero)
        wantsLayer = true

        uiStyleLabel(gainLabel, 7, .medium, 0x333333)
        gainLabel.alignment = .center

        uiStyleLabel(freqLabel, 7, .regular, 0x333333)
        freqLabel.alignment = .center

        uiInstall(self, [gainLabel, freqLabel])

        uiAlign(gainLabel, .top, to: self, offset: 1)
        uiAlign(gainLabel, .centerX, to: self)
        uiAlign(freqLabel, .bottom, to: self, offset: -1)
        uiAlign(freqLabel, .centerX, to: self)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let sliderArea = NSRect(x: 0, y: 12, width: bounds.width, height: bounds.height - 24)
        let centerX = bounds.width / 2
        let centerY = sliderArea.midY

        // Track
        NSColor(hex: 0x1a1a1a).setFill()
        NSRect(x: centerX - 1, y: sliderArea.minY, width: 2, height: sliderArea.height).fill()

        // Zero line
        NSColor(hex: 0x282828).setFill()
        NSRect(x: centerX - 4, y: centerY - 0.5, width: 8, height: 1).fill()

        // Thumb position
        let normalized = CGFloat((value + 12) / 24)
        let thumbY = sliderArea.minY + sliderArea.height * normalized

        // Fill from center
        NSColor(hex: 0x4a9eff, alpha: 0.35).setFill()
        let fillTop = min(thumbY, centerY)
        let fillH = abs(thumbY - centerY)
        NSRect(x: centerX - 1, y: fillTop, width: 2, height: fillH).fill()

        // Thumb
        NSColor(hex: 0x4a9eff).setFill()
        NSRect(x: centerX - 3, y: thumbY - 2, width: 6, height: 4).fill()
    }

    override func mouseDown(with event: NSEvent) { drag(event) }
    override func mouseDragged(with event: NSEvent) { drag(event) }

    private func drag(_ event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let sliderArea = NSRect(x: 0, y: 12, width: bounds.width, height: bounds.height - 24)
        let pct = Float(max(0, min(1, (pt.y - sliderArea.minY) / sliderArea.height)))
        let newValue = -12 + pct * 24
        value = newValue
        AppState.shared.eqProfile.bands[index].gain = newValue
    }
}
