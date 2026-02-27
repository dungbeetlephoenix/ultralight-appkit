import AppKit
import Combine

final class EQPanelView: NSView {
    private let labels = ["60", "170", "310", "600", "1K", "3K", "6K", "12K"]
    private var sliders: [EQSliderView] = []
    private let preampBar = ProgressBarView()
    private let preampLabel = NSTextField(labelWithString: "+0")
    private let reasonLabel = NSTextField(labelWithString: "")
    private let badgeContainer = NSStackView()
    private let statsLabel = NSTextField(labelWithString: "")
    private var cancellables = Set<AnyCancellable>()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x0e0e0e).cgColor
        setup()
        bind()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        // Header
        let headerBg = NSView()
        headerBg.wantsLayer = true
        headerBg.layer?.backgroundColor = NSColor(hex: 0x111111).cgColor

        let eqLabel = NSTextField(labelWithString: "EQ")
        eqLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        eqLabel.textColor = NSColor(hex: 0xcccccc)

        let autoBtn = makeButton("AUTO") { AppState.shared.eqBypassed.toggle() }
        autoBtn.contentTintColor = NSColor(hex: 0x4a9eff)
        autoBtn.layer?.borderColor = NSColor(hex: 0x4a9eff).cgColor
        let rstBtn = makeButton("RST") { AppState.shared.eqProfile = .flat }
        let saveBtn = makeButton("SAVE") { AppState.shared.saveEQForCurrentTrack() }
        let btnStack = NSStackView(views: [autoBtn, rstBtn, saveBtn])
        btnStack.spacing = 4

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

        let preLabel = NSTextField(labelWithString: "PRE")
        preLabel.font = NSFont.monospacedSystemFont(ofSize: 7, weight: .regular)
        preLabel.textColor = NSColor(hex: 0x333333)

        preampLabel.font = NSFont.monospacedSystemFont(ofSize: 7, weight: .regular)
        preampLabel.textColor = NSColor(hex: 0x333333)

        let preStack = NSStackView(views: [preLabel, preampBar, preampLabel])
        preStack.spacing = 4
        preStack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        preampBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        preampBar.heightAnchor.constraint(equalToConstant: 4).isActive = true

        // Analysis
        reasonLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        reasonLabel.textColor = NSColor(hex: 0xcccccc)
        reasonLabel.lineBreakMode = .byWordWrapping
        reasonLabel.maximumNumberOfLines = 2

        badgeContainer.orientation = .horizontal
        badgeContainer.spacing = 3
        badgeContainer.alignment = .centerY

        statsLabel.font = NSFont.monospacedSystemFont(ofSize: 7, weight: .regular)
        statsLabel.textColor = NSColor(hex: 0x333333)

        let analysisStack = NSStackView(views: [reasonLabel, badgeContainer, statsLabel])
        analysisStack.orientation = .vertical
        analysisStack.alignment = .leading
        analysisStack.spacing = 2
        analysisStack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        // Main layout
        let mainStack = NSStackView(views: [headerBg, sliderStack, preStack, analysisStack])
        mainStack.orientation = .vertical
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        headerBg.translatesAutoresizingMaskIntoConstraints = false
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerBg.addSubview(headerStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBg.heightAnchor.constraint(equalToConstant: 28),
            headerStack.topAnchor.constraint(equalTo: headerBg.topAnchor),
            headerStack.bottomAnchor.constraint(equalTo: headerBg.bottomAnchor),
            headerStack.leadingAnchor.constraint(equalTo: headerBg.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: headerBg.trailingAnchor),
            sliderStack.heightAnchor.constraint(equalToConstant: 110),
        ])
    }

    private func bind() {
        let state = AppState.shared

        state.$eqProfile.receive(on: RunLoop.main).sink { [weak self] profile in
            guard let self else { return }
            for (i, slider) in sliders.enumerated() where i < profile.bands.count {
                slider.value = profile.bands[i].gain
            }
            preampBar.progress = Double((profile.preamp + 12) / 24)
            preampLabel.stringValue = String(format: "%+.0f", profile.preamp)
        }.store(in: &cancellables)

        Publishers.CombineLatest(state.$currentTrack, state.$eqProfile)
            .receive(on: RunLoop.main)
            .sink { [weak self] track, _ in self?.updateAnalysis(track: track) }
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
        let btn = NSButton(title: title, target: nil, action: nil)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        btn.contentTintColor = NSColor(hex: 0x444444)
        btn.wantsLayer = true
        btn.layer?.borderColor = NSColor(hex: 0x222222).cgColor
        btn.layer?.borderWidth = 1
        let wrapper = ActionWrapper(action: action)
        objc_setAssociatedObject(btn, "action", wrapper, .OBJC_ASSOCIATION_RETAIN)
        btn.action = #selector(ActionWrapper.invoke)
        btn.target = wrapper
        return btn
    }

    private func makeBadge(_ text: String, color: UInt) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 7, weight: .bold)
        label.textColor = NSColor(hex: color)
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor(hex: color, alpha: 0.12).cgColor
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
    private let gainLabel = NSTextField(labelWithString: "+0")
    private let freqLabel: NSTextField
    private let index: Int

    init(label: String, index: Int) {
        self.index = index
        self.freqLabel = NSTextField(labelWithString: label)
        super.init(frame: .zero)
        wantsLayer = true

        gainLabel.font = NSFont.monospacedSystemFont(ofSize: 7, weight: .medium)
        gainLabel.textColor = NSColor(hex: 0x333333)
        gainLabel.alignment = .center

        freqLabel.font = NSFont.monospacedSystemFont(ofSize: 7, weight: .regular)
        freqLabel.textColor = NSColor(hex: 0x333333)
        freqLabel.alignment = .center

        for v in [gainLabel, freqLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            gainLabel.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            gainLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            freqLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            freqLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
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
