import AppKit
import Combine

final class HeaderView: NSView {
    private let logo = NSTextField(labelWithString: "ULTRALIGHT")
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let formatBadge = NSTextField(labelWithString: "")
    private let settingsBtn = NSButton(title: "⚙", target: nil, action: nil)
    private var cancellables = Set<AnyCancellable>()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x0e0e0e).cgColor

        setupViews()
        bind()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        // Logo — small, blue, monospace
        logo.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        logo.textColor = NSColor(hex: 0x4a9eff)
        logo.setContentHuggingPriority(.required, for: .horizontal)
        logo.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Track title — large, bold, white
        titleLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = NSColor(hex: 0xe0e0e0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Artist — smaller, gray, below title
        artistLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        artistLabel.textColor = NSColor(hex: 0x555555)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        artistLabel.isHidden = true

        // Format badge — bordered, right side
        formatBadge.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        formatBadge.textColor = NSColor(hex: 0x555555)
        formatBadge.wantsLayer = true
        formatBadge.layer?.borderColor = NSColor(hex: 0x333333).cgColor
        formatBadge.layer?.borderWidth = 1
        formatBadge.isHidden = true
        formatBadge.setContentHuggingPriority(.required, for: .horizontal)

        // Settings gear
        settingsBtn.bezelStyle = .inline
        settingsBtn.isBordered = false
        settingsBtn.font = NSFont.systemFont(ofSize: 14)
        settingsBtn.contentTintColor = NSColor(hex: 0x444444)
        settingsBtn.target = self
        settingsBtn.action = #selector(openSettings)

        // Title + artist stacked
        let infoStack = NSStackView(views: [titleLabel, artistLabel])
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 0
        infoStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Layout with direct constraints
        for v in [logo, infoStack, formatBadge, settingsBtn] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            // Logo: 76px from left to clear traffic lights
            logo.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 76),
            logo.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Track info next to logo
            infoStack.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 12),
            infoStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Format badge right-aligned
            formatBadge.trailingAnchor.constraint(equalTo: settingsBtn.leadingAnchor, constant: -10),
            formatBadge.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Settings gear far right
            settingsBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            settingsBtn.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Info shouldn't overlap badge
            infoStack.trailingAnchor.constraint(lessThanOrEqualTo: formatBadge.leadingAnchor, constant: -10),
        ])
    }

    private func bind() {
        let state = AppState.shared
        state.$currentTrack.receive(on: RunLoop.main).sink { [weak self] track in
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
