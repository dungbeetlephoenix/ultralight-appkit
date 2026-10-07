import AppKit
import Combine

final class EQPanelView: NSView {
    private let labels = ["60", "170", "310", "600", "1K", "3K", "6K", "12K"]
    private var sliders: [EQSliderView] = []
    private let preampBar = ProgressBarView()
    private let preampLabel = uiLabel("+0")
    private let reasonLabel = uiLabel("")
    private let badgeContainer = NSStackView()
    private let statsLabel = uiLabel("")
    private var cancellables = Set<AnyCancellable>()

    override init(frame: NSRect) {
        super.init(frame: frame)
        uiBackground(self, 0x0e0e0e)
        setup()
        bind()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        // Header
        let headerBg = NSView()
        uiBackground(headerBg, 0x111111)

        let eqLabel = uiLabel("EQ")
        uiStyleLabel(eqLabel, 10, .bold, 0xcccccc)

        let autoBtn = makeButton("AUTO") { AppState.shared.eqBypassed.toggle() }
        autoBtn.contentTintColor = NSColor(hex: 0x4a9eff)
        autoBtn.layer?.borderColor = NSColor(hex: 0x4a9eff).cgColor
        let rstBtn = makeButton("RST") { AppState.shared.eqProfile = .flat }
        let saveBtn = makeButton("SAVE") { AppState.shared.saveEQForCurrentTrack() }
        let btnStack = uiStack([autoBtn, rstBtn, saveBtn], .horizontal, 4)

        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let headerStack = NSStackView(views: [eqLabel, spacer, btnStack])
        headerStack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        // Sliders
        let sliderStack = NSStackView()
        sliderStack.orientation = .horizontal
        sliderStack.distribution = .fillEqually
        sliderStack.spacing = 1

        for i in 0..<8 {
            let sv = EQSliderView(label: labels[i], index: i)
            sliders.append(sv)
            sliderStack.addArrangedSubview(sv)
        }

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
        uiConstraint(preampBar, .width, nil, .notAnAttribute, .greaterThanOrEqual, 50).isActive = true
        uiConstraint(preampBar, .height, nil, .notAnAttribute, .equal, 4).isActive = true

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
        addSubview(mainStack)

        headerBg.translatesAutoresizingMaskIntoConstraints = false
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerBg.addSubview(headerStack)

        NSLayoutConstraint.activate([
            uiConstraint(mainStack, .top, self, .top, .equal, 0),
            uiConstraint(mainStack, .leading, self, .leading, .equal, 0),
            uiConstraint(mainStack, .trailing, self, .trailing, .equal, 0),
            uiConstraint(headerBg, .height, nil, .notAnAttribute, .equal, 28),
            uiConstraint(headerStack, .top, headerBg, .top, .equal, 0),
            uiConstraint(headerStack, .bottom, headerBg, .bottom, .equal, 0),
            uiConstraint(headerStack, .leading, headerBg, .leading, .equal, 0),
            uiConstraint(headerStack, .trailing, headerBg, .trailing, .equal, 0),
            uiConstraint(sliderStack, .height, nil, .notAnAttribute, .equal, 110),
        ])
    }

    private func bind() {
        let state = AppState.shared

        state.$eqProfile.sinkOnMain { [weak self] profile in
            guard let self else { return }
            for (i, slider) in sliders.enumerated() where i < profile.bands.count {
                slider.value = profile.bands[i].gain
            }
            preampBar.progress = Double((profile.preamp + 12) / 24)
            preampLabel.stringValue = String(format: "%+.0f", profile.preamp)
        }.store(in: &cancellables)

        Publishers.CombineLatest(state.$currentTrack, state.$eqProfile)
            .sinkOnMain { [weak self] track, _ in self?.updateAnalysis(track: track) }
            .store(in: &cancellables)
    }

    private func updateAnalysis(track: Track?) {
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
            badgeContainer.addArrangedSubview(makeBadge(label, color: color))
            any = true
        }
        if !any {
            badgeContainer.addArrangedSubview(makeBadge("BALANCED", color: 0x4ade80))
        }

        statsLabel.stringValue = "bass \(Int(a.bassEnergy * 100))%  mid \(Int(a.midEnergy * 100))%  treble \(Int(a.trebleEnergy * 100))%  peak \(String(format: "%.0f", a.peakLevel))dB"
    }

    private func makeButton(_ title: String, action: @escaping () -> Void) -> NSButton {
        let btn = uiButton(title)
        uiStyleButton(btn, 8, .regular, true, 0x444444)
        uiBorder(btn, 0x222222)
        let wrapper = ActionWrapper(action: action)
        objc_setAssociatedObject(btn, "action", wrapper, .OBJC_ASSOCIATION_RETAIN)
        btn.action = #selector(ActionWrapper.invoke)
        btn.target = wrapper
        return btn
    }

    private func makeBadge(_ text: String, color: UInt) -> NSView {
        let label = uiLabel(text)
        uiStyleLabel(label, 7, .bold, color)
        uiBackground(label, color, alpha: 0.12)
        label.layer?.borderColor = NSColor(hex: color, alpha: 0.25).cgColor
        label.layer?.borderWidth = 1
        return label
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(hex: 0x1a1a1a).setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }
}

// Action wrapper for closures
private final class ActionWrapper: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func invoke() { action() }
}

// Individual EQ band slider
final class EQSliderView: NSView {
    var value: Float = 0 { didSet { needsDisplay = true; gainLabel.stringValue = String(format: "%+.0f", value) } }
    private let gainLabel = uiLabel("+0")
    private let freqLabel: NSTextField
    private let index: Int

    init(label: String, index: Int) {
        self.index = index
        self.freqLabel = uiLabel(label)
        super.init(frame: .zero)
        wantsLayer = true

        uiStyleLabel(gainLabel, 7, .medium, 0x333333)
        gainLabel.alignment = .center

        uiStyleLabel(freqLabel, 7, .regular, 0x333333)
        freqLabel.alignment = .center

        uiInstall(self, [gainLabel, freqLabel])

        NSLayoutConstraint.activate([
            uiConstraint(gainLabel, .top, self, .top, .equal, 1),
            uiConstraint(gainLabel, .centerX, self, .centerX, .equal, 0),
            uiConstraint(freqLabel, .bottom, self, .bottom, .equal, -1),
            uiConstraint(freqLabel, .centerX, self, .centerX, .equal, 0),
        ])
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
