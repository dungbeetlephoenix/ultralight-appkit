import AppKit
import CoreAudio

final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private weak var state: AppState?
    weak var playerWindow: NSWindow?

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

        let outputItem = NSMenuItem(title: "Output Device", action: nil, keyEquivalent: "")
        outputItem.submenu = buildDeviceMenu()
        menu.addItem(outputItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func buildDeviceMenu() -> NSMenu {
        let sub = NSMenu()
        let devices = AudioEngine.outputDevices()
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectDevice(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(device.id)
            sub.addItem(item)
        }
        return sub
    }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        let deviceID = AudioDeviceID(sender.tag)
        state?.audioEngine.setOutputDevice(deviceID)
        // Update checkmarks
        if let items = sender.menu?.items {
            for item in items { item.state = .off }
        }
        sender.state = .on
    }

    @objc private func toggleWindow() {
        guard let window = playerWindow else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    @objc private func showWindow() {
        guard let window = playerWindow else { return }
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
