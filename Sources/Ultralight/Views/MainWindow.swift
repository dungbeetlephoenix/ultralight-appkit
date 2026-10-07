import AppKit
import Combine

final class MainWindow: NSWindow {
    let headerView = makeHeaderView()
    let trackListView = TrackListView()
    let eqPanelView = makeEQPanelView()
    let playbackBar = makePlaybackBarView()

    private var cancellables = [AnyCancellable]()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        title = "Ultralight"
        backgroundColor = NSColor(hex: 0x0a0a0a)
        minSize = NSSize(width: 600, height: 400)
        isReleasedWhenClosed = false
        center()

        setupLayout()
        setupDragDrop()
        setupBindings()
        setupKeyboard()
    }

    private func setupLayout() {
        let content = DropView()
        content.wantsLayer = true
        contentView = content

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(container)
        uiFill(container, in: content)

        uiInstall(container, [headerView, trackListView, eqPanelView, playbackBar] as [NSView])

        // Header at top
        uiAlign(headerView, .top, to: container)
        uiAlign(headerView, .leading, to: container)
        uiAlign(headerView, .trailing, to: container)
        uiDimension(headerView, .height, 50)

        // Playback bar at bottom
        uiAlign(playbackBar, .bottom, to: container)
        uiAlign(playbackBar, .leading, to: container)
        uiAlign(playbackBar, .trailing, to: container)
        uiDimension(playbackBar, .height, 96)

        // EQ panel on right
        uiConstrain(eqPanelView, .top, headerView, .bottom, .equal, 0)
        uiAlign(eqPanelView, .trailing, to: container)
        uiConstrain(eqPanelView, .bottom, playbackBar, .top, .equal, 0)
        uiDimension(eqPanelView, .width, 230)

        // Track list fills remaining space
        uiConstrain(trackListView, .top, headerView, .bottom, .equal, 0)
        uiAlign(trackListView, .leading, to: container)
        uiConstrain(trackListView, .trailing, eqPanelView, .leading, .equal, 0)
        uiConstrain(trackListView, .bottom, playbackBar, .top, .equal, 0)
    }

    private func setupDragDrop() {
        (contentView as? DropView)?.registerForDraggedTypes([.fileURL])
    }

    private func setupBindings() {
        let state = AppState.shared
        state.$showEQ.sinkOnMain { [weak self] show in
            self?.eqPanelView.isHidden = !show
        }.store(in: &cancellables)
    }

    private func setupKeyboard() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isKeyWindow else { return event }
            // Native controls and field editors handle their own navigation keys.
            if self.firstResponder is NSControl || self.firstResponder is NSTextView { return event }
            let state = AppState.shared
            let cmd = event.modifierFlags.contains(.command)
            switch event.keyCode {
            case 49: // Space
                state.togglePlay(); return nil
            case 123: // Left
                if cmd { state.playPrevious() } else { state.seek(to: max(0, state.currentTime - 5)) }
                return nil
            case 124: // Right
                if cmd { state.playNext() } else { state.seek(to: min(state.duration, state.currentTime + 5)) }
                return nil
            case 126: // Up
                state.volume = min(1, state.volume + 0.05); return nil
            case 125: // Down
                state.volume = max(0, state.volume - 0.05); return nil
            default:
                return event
            }
        }
    }

    // Hide instead of close
    override func close() {
        orderOut(nil)
    }
}

// Content view that accepts drag-and-drop
final class DropView: NSView {
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else { return false }

        for url in items {
            guard url.isFileURL else { continue }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let path = isDir.boolValue ? url.path : url.deletingLastPathComponent().path
            AppState.shared.addFolder(path)
        }
        return true
    }
}

// NSColor hex convenience
extension NSColor {
    @inline(never) convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
