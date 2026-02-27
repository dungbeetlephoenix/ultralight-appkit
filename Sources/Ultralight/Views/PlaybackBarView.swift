import AppKit
import Combine

final class PlaybackBarView: NSView {
    private let spectrumView = SpectrumView()
    private let progressBar = ProgressBarView()
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let durationLabel = NSTextField(labelWithString: "0:00")
    private let playBtn = NSButton(title: "▶", target: nil, action: nil)
    private let prevBtn = NSButton(title: "⏮", target: nil, action: nil)
    private let nextBtn = NSButton(title: "⏭", target: nil, action: nil)
    private let shfBtn = NSButton(title: "⤮", target: nil, action: nil)
    private let rptBtn = NSButton(title: "↻", target: nil, action: nil)
    private let eqBtn2 = NSButton(title: "EQ", target: nil, action: nil)
    private let volBar = ProgressBarView()
    private let volPctLabel = NSTextField(labelWithString: "80%")
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
        for lbl in [timeLabel, durationLabel] {
            lbl.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            lbl.textColor = NSColor(hex: 0x555555)
        }

        for btn in [prevBtn, nextBtn, shfBtn, rptBtn] {
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 14)
            btn.contentTintColor = NSColor(hex: 0x555555)
        }

        playBtn.bezelStyle = .inline
        playBtn.isBordered = false
        playBtn.font = NSFont.systemFont(ofSize: 14)
        playBtn.contentTintColor = NSColor(hex: 0xe0e0e0)
        playBtn.wantsLayer = true
        playBtn.layer?.borderColor = NSColor(hex: 0x333333).cgColor
        playBtn.layer?.borderWidth = 1

        playBtn.target = self; playBtn.action = #selector(togglePlay)
        prevBtn.target = self; prevBtn.action = #selector(prev)
        nextBtn.target = self; nextBtn.action = #selector(next)
        shfBtn.target = self; shfBtn.action = #selector(toggleShuffle)
        rptBtn.target = self; rptBtn.action = #selector(toggleRepeat)

        eqBtn2.bezelStyle = .inline
        eqBtn2.isBordered = false
        eqBtn2.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        eqBtn2.contentTintColor = NSColor(hex: 0x4a9eff)
        eqBtn2.target = self
        eqBtn2.action = #selector(toggleEQ)

        volBar.color = NSColor(hex: 0x4a9eff)
        volBar.progress = 0.8
        volBar.onClick = { [weak self] pct in
            AppState.shared.volume = Float(pct)
            self?.volPctLabel.stringValue = "\(Int(pct * 100))%"
        }

        volPctLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        volPctLabel.textColor = NSColor(hex: 0x555555)

        progressBar.color = NSColor(hex: 0x4a9eff)
        progressBar.onClick = { pct in
            AppState.shared.seek(to: AppState.shared.duration * pct)
        }

        // Layout
        spectrumView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spectrumView)

        let progressStack = NSStackView(views: [timeLabel, progressBar, durationLabel])
        progressStack.orientation = .horizontal
        progressStack.spacing = 6

        let transportStack = NSStackView(views: [prevBtn, playBtn, nextBtn])
        transportStack.spacing = 6

        let volStack = NSStackView(views: [volBar, volPctLabel])
        volStack.spacing = 6

        let spacer1 = NSView(); spacer1.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let spacer2 = NSView(); spacer2.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let controlsStack = NSStackView(views: [shfBtn, rptBtn, spacer1, transportStack, eqBtn2, spacer2, volStack])
        controlsStack.orientation = .horizontal
        controlsStack.spacing = 8

        let mainStack = NSStackView(views: [progressStack, controlsStack])
        mainStack.orientation = .vertical
        mainStack.spacing = 4
        mainStack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 6, right: 10)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            spectrumView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            spectrumView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            spectrumView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            spectrumView.heightAnchor.constraint(equalToConstant: 28),

            mainStack.topAnchor.constraint(equalTo: spectrumView.bottomAnchor, constant: 4),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            progressBar.heightAnchor.constraint(equalToConstant: 4),
            playBtn.widthAnchor.constraint(equalToConstant: 32),
            playBtn.heightAnchor.constraint(equalToConstant: 32),
            volBar.widthAnchor.constraint(equalToConstant: 60),
            volBar.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    private func bind() {
        let state = AppState.shared

        state.$currentTime.receive(on: RunLoop.main).sink { [weak self] t in
            self?.timeLabel.stringValue = Self.fmt(t)
            let dur = AppState.shared.duration
            self?.progressBar.progress = dur > 0 ? t / dur : 0
        }.store(in: &cancellables)

        state.$duration.receive(on: RunLoop.main).sink { [weak self] d in
            self?.durationLabel.stringValue = Self.fmt(d)
        }.store(in: &cancellables)

        state.$isPlaying.receive(on: RunLoop.main).sink { [weak self] p in
            self?.playBtn.title = p ? "⏸" : "▶"
        }.store(in: &cancellables)

        state.$shuffle.receive(on: RunLoop.main).sink { [weak self] s in
            self?.shfBtn.contentTintColor = s ? NSColor(hex: 0x4a9eff) : NSColor(hex: 0x444444)
        }.store(in: &cancellables)

        state.$repeatMode.receive(on: RunLoop.main).sink { [weak self] r in
            self?.rptBtn.contentTintColor = r ? NSColor(hex: 0x4a9eff) : NSColor(hex: 0x444444)
        }.store(in: &cancellables)

        state.$volume.receive(on: RunLoop.main).sink { [weak self] v in
            self?.volBar.progress = Double(v)
            self?.volPctLabel.stringValue = "\(Int(v * 100))%"
        }.store(in: &cancellables)
    }

    @objc private func togglePlay() { AppState.shared.togglePlay() }
    @objc private func prev() { AppState.shared.playPrevious() }
    @objc private func next() { AppState.shared.playNext() }
    @objc private func toggleShuffle() { AppState.shared.shuffle.toggle() }
    @objc private func toggleRepeat() { AppState.shared.repeatMode.toggle() }
    @objc private func toggleEQ() { AppState.shared.showEQ.toggle() }

    private static func fmt(_ s: Double) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(hex: 0x1a1a1a).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}

// Clickable progress/volume bar
final class ProgressBarView: NSView {
    var progress: Double = 0 { didSet { needsDisplay = true } }
    var color: NSColor = NSColor(hex: 0x4a9eff)
    var onClick: ((Double) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: 0x1a1a1a).setFill()
        bounds.fill()
        color.setFill()
        NSRect(x: 0, y: 0, width: bounds.width * CGFloat(progress), height: bounds.height).fill()
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
