import AppKit
import Combine

func makeHeaderView() -> NSView {
    let logo = uiLabel("ULTRALIGHT")
    let titleLabel = uiLabel("")
    let artistLabel = uiLabel("")
    let formatBadge = uiLabel("")
    let settingsBtn = uiButton("⚙")
    uiDescribe(settingsBtn, "Settings")
    var cancellables = [AnyCancellable]()
    let panel = uiContainer(border: .minY)
    uiBackground(panel, 0x0e0e0e)

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
    uiAction(settingsBtn) { SettingsWindow.show() }

    // Title + artist stacked
    let infoStack = NSStackView(views: [titleLabel, artistLabel])
    infoStack.orientation = .vertical
    infoStack.alignment = .leading
    infoStack.spacing = 0
    infoStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // Layout with direct constraints
    uiInstall(panel, [logo, infoStack, formatBadge, settingsBtn] as [NSView])

    // Logo: 76px from left to clear traffic lights
    uiAlign(logo, .leading, to: panel, offset: 76)
    uiAlign(logo, .centerY, to: panel)

    // Track info next to logo
    uiConstrain(infoStack, .leading, logo, .trailing, .equal, 12)
    uiAlign(infoStack, .centerY, to: panel)

    // Format badge right-aligned
    uiConstrain(formatBadge, .trailing, settingsBtn, .leading, .equal, -10)
    uiAlign(formatBadge, .centerY, to: panel)

    // Settings gear far right
    uiAlign(settingsBtn, .trailing, to: panel, offset: -10)
    uiAlign(settingsBtn, .centerY, to: panel)

    // Info shouldn't overlap badge
    uiConstrain(infoStack, .trailing, formatBadge, .leading, .lessThanOrEqual, -10)

    let state = AppState.shared
    state.$currentTrack.sinkOnMain { [weak panel] track in
        guard let panel else { return }
        if let t = track {
            titleLabel.stringValue = t.displayTitle
            artistLabel.stringValue = t.artist
            artistLabel.isHidden = t.artist.isEmpty
            let ext = URL(fileURLWithPath: t.path).pathExtension.uppercased()
            formatBadge.stringValue = " \(ext) "
            formatBadge.isHidden = false
            panel.window?.title = t.displayTitle
        } else {
            titleLabel.stringValue = ""
            artistLabel.isHidden = true
            formatBadge.isHidden = true
            panel.window?.title = "Ultralight"
        }
    }.store(in: &cancellables)

    uiRetain(cancellables, on: panel)
    return panel
}
