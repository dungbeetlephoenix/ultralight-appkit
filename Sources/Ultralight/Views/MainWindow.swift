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
    }

    private func setupLayout() {
        let content = DropView()
        content.wantsLayer = true
        contentView = content

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: content.topAnchor),
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        for v in [headerView, trackListView, eqPanelView, playbackBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }

        NSLayoutConstraint.activate([
            // Header at top
            headerView.topAnchor.constraint(equalTo: container.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50),

            // Playback bar at bottom
            playbackBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            playbackBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            playbackBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            playbackBar.heightAnchor.constraint(equalToConstant: 84),

            // EQ panel on right
            eqPanelView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            eqPanelView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            eqPanelView.bottomAnchor.constraint(equalTo: playbackBar.topAnchor),
            eqPanelView.widthAnchor.constraint(equalToConstant: 230),

            // Track list fills remaining space
            trackListView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            trackListView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trackListView.trailingAnchor.constraint(equalTo: eqPanelView.leadingAnchor),
            trackListView.bottomAnchor.constraint(equalTo: playbackBar.topAnchor),
        ])
    }

    private func setupDragDrop() {
        (contentView as? DropView)?.registerForDraggedTypes([.fileURL])
    }

    private func setupBindings() {
        let state = AppState.shared
        state.$showEQ.receive(on: RunLoop.main).sink { [weak self] show in
            self?.eqPanelView.isHidden = !show
        }.store(in: &cancellables)
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
    convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
