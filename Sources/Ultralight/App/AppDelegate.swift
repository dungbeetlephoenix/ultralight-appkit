import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: MainWindow!
    let menuBarManager = MenuBarManager()
    let mediaKeyHandler = MediaKeyHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        mainWindow = MainWindow()
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppState.shared.onPlaybackError = { [weak self] error in
            guard let window = self?.mainWindow else { return }
            NSAlert(error: error).beginSheetModal(for: window)
        }

        menuBarManager.playerWindow = mainWindow
        menuBarManager.setup(state: AppState.shared)
        mediaKeyHandler.setup(state: AppState.shared)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow?.makeKeyAndOrderFront(nil) }
        return true
    }
}
