import AppKit
import Combine

final class HeaderView: NSView {
    private let logo = uiLabel("ULTRALIGHT")
    private let titleLabel = uiLabel("")
    private let artistLabel = uiLabel("")
    private let formatBadge = uiLabel("")
    private let settingsBtn = uiButton("⚙")
    private var cancellables = Set<AnyCancellable>()

    override init(frame: NSRect) {
        super.init(frame: frame)
        uiBackground(self, 0x0e0e0e)

        setupViews()
        bind()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        // Logo — small, blue, monospace
        uiStyleLabel(logo, 10, .bold, 0x4a9eff)
        logo.setContentHuggingPriority(.required, for: .horizontal)
        logo.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Track title — large, bold, white
        uiStyleLabel(titleLabel, 13, .bold, 0xe0e0e0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Artist — smaller, gray, below title
        uiStyleLabel(artistLabel, 10, .regular, 0x555555)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        artistLabel.isHidden = true

        // Format badge — bordered, right side
        uiStyleLabel(formatBadge, 9, .medium, 0x555555)
        uiBorder(formatBadge, 0x333333)
        formatBadge.isHidden = true
        formatBadge.setContentHuggingPriority(.required, for: .horizontal)

        // Settings gear
        uiStyleButton(settingsBtn, 14, .regular, false, 0x444444)
        settingsBtn.target = self
        settingsBtn.action = #selector(openSettings)

        // Title + artist stacked
        let infoStack = NSStackView(views: [titleLabel, artistLabel])
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 0
        infoStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Layout with direct constraints
        uiInstall(self, [logo, infoStack, formatBadge, settingsBtn] as [NSView])

        NSLayoutConstraint.activate([
            // Logo: 76px from left to clear traffic lights
            uiConstraint(logo, .leading, self, .leading, .equal, 76),
            uiConstraint(logo, .centerY, self, .centerY, .equal, 0),

            // Track info next to logo
            uiConstraint(infoStack, .leading, logo, .trailing, .equal, 12),
            uiConstraint(infoStack, .centerY, self, .centerY, .equal, 0),

            // Format badge right-aligned
            uiConstraint(formatBadge, .trailing, settingsBtn, .leading, .equal, -10),
            uiConstraint(formatBadge, .centerY, self, .centerY, .equal, 0),

            // Settings gear far right
            uiConstraint(settingsBtn, .trailing, self, .trailing, .equal, -10),
            uiConstraint(settingsBtn, .centerY, self, .centerY, .equal, 0),

            // Info shouldn't overlap badge
            uiConstraint(infoStack, .trailing, formatBadge, .leading, .lessThanOrEqual, -10),
        ])
    }

    private func bind() {
        let state = AppState.shared
        state.$currentTrack.sinkOnMain { [weak self] track in
            guard let self else { return }
            if let t = track {
                titleLabel.stringValue = t.displayTitle
                artistLabel.stringValue = t.artist
                artistLabel.isHidden = t.artist.isEmpty
                let ext = URL(fileURLWithPath: t.path).pathExtension.uppercased()
                formatBadge.stringValue = " \(ext) "
                formatBadge.isHidden = false
                window?.title = t.displayTitle
            } else {
                titleLabel.stringValue = ""
                artistLabel.isHidden = true
                formatBadge.isHidden = true
                window?.title = "Ultralight"
            }
        }.store(in: &cancellables)
    }

    @objc private func openSettings() { SettingsWindow.show() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(hex: 0x1a1a1a).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}
