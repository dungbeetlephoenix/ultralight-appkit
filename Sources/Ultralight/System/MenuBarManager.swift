import AppKit

final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private weak var state: AppState?

    func setup(state: AppState) {
        self.state = state

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // Simple colored square icon matching accent color
            let image = NSImage(size: NSSize(width: 16, height: 16))
            image.lockFocus()
            NSColor(red: 74/255, green: 158/255, blue: 255/255, alpha: 1).setFill()
            NSRect(x: 2, y: 2, width: 12, height: 12).fill()
            image.unlockFocus()
            image.isTemplate = false
            button.image = image
            button.action = #selector(toggleWindow)
            button.target = self
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Player", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let playItem = NSMenuItem(title: "Play/Pause", action: #selector(togglePlay), keyEquivalent: "")
        playItem.target = self
        menu.addItem(playItem)

        let nextItem = NSMenuItem(title: "Next Track", action: #selector(nextTrack), keyEquivalent: "")
        nextItem.target = self
        menu.addItem(nextItem)

        let prevItem = NSMenuItem(title: "Previous Track", action: #selector(prevTrack), keyEquivalent: "")
        prevItem.target = self
        menu.addItem(prevItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    @objc private func showWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func togglePlay() {
        state?.togglePlay()
    }

    @objc private func nextTrack() {
        state?.playNext()
    }

    @objc private func prevTrack() {
        state?.playPrevious()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
