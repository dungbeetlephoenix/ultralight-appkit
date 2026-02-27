import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: MainWindow!
    let menuBarManager = MenuBarManager()
    let mediaKeyHandler = MediaKeyHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        mainWindow = MainWindow()
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

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
