import AppKit
import Combine

final class MainWindow: NSWindow {
    let headerView = HeaderView()
    let trackListView = TrackListView()
    let eqPanelView = EQPanelView()
    let playbackBar = PlaybackBarView()

    private var cancellables = Set<AnyCancellable>()

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
        NSLayoutConstraint.activate([
            uiConstraint(container, .top, content, .top, .equal, 0),
            uiConstraint(container, .leading, content, .leading, .equal, 0),
            uiConstraint(container, .trailing, content, .trailing, .equal, 0),
            uiConstraint(container, .bottom, content, .bottom, .equal, 0),
        ])

        uiInstall(container, [headerView, trackListView, eqPanelView, playbackBar] as [NSView])

        NSLayoutConstraint.activate([
            // Header at top
            uiConstraint(headerView, .top, container, .top, .equal, 0),
            uiConstraint(headerView, .leading, container, .leading, .equal, 0),
            uiConstraint(headerView, .trailing, container, .trailing, .equal, 0),
            uiConstraint(headerView, .height, nil, .notAnAttribute, .equal, 50),

            // Playback bar at bottom
            uiConstraint(playbackBar, .bottom, container, .bottom, .equal, 0),
            uiConstraint(playbackBar, .leading, container, .leading, .equal, 0),
            uiConstraint(playbackBar, .trailing, container, .trailing, .equal, 0),
            uiConstraint(playbackBar, .height, nil, .notAnAttribute, .equal, 96),

            // EQ panel on right
            uiConstraint(eqPanelView, .top, headerView, .bottom, .equal, 0),
            uiConstraint(eqPanelView, .trailing, container, .trailing, .equal, 0),
            uiConstraint(eqPanelView, .bottom, playbackBar, .top, .equal, 0),
            uiConstraint(eqPanelView, .width, nil, .notAnAttribute, .equal, 230),

            // Track list fills remaining space
            uiConstraint(trackListView, .top, headerView, .bottom, .equal, 0),
            uiConstraint(trackListView, .leading, container, .leading, .equal, 0),
            uiConstraint(trackListView, .trailing, eqPanelView, .leading, .equal, 0),
            uiConstraint(trackListView, .bottom, playbackBar, .top, .equal, 0),
        ])
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
            guard self?.isKeyWindow == true else { return event }
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
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return false }

        let paths = items.compactMap { url -> String? in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue ? url.path : url.deletingLastPathComponent().path
        }

        for path in Set(paths) {
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
