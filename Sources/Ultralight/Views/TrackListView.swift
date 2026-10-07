import AppKit
import Combine

final class TrackListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let headerBar = NSView()
    private let countLabel = uiLabel("0 tracks")
    private let eqBtn = uiButton("EQ")
    private var cancellables = Set<AnyCancellable>()
    private var displayedTracks: [Track] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        uiBackground(self, 0x0a0a0a)
        setupHeader()
        setupTable()
        bind()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupHeader() {
        uiBackground(headerBar, 0x111111)
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerBar)

        let libLabel = uiLabel("LIBRARY")
        uiStyleLabel(libLabel, 10, .bold, 0x4a9eff)

        uiStyleLabel(countLabel, 10, .regular, 0x555555)

        uiInstall(headerBar, [libLabel, countLabel])

        NSLayoutConstraint.activate([
            uiConstraint(headerBar, .top, self, .top, .equal, 0),
            uiConstraint(headerBar, .leading, self, .leading, .equal, 0),
            uiConstraint(headerBar, .trailing, self, .trailing, .equal, 0),
            uiConstraint(headerBar, .height, nil, .notAnAttribute, .equal, 28),
            uiConstraint(libLabel, .leading, headerBar, .leading, .equal, 10),
            uiConstraint(libLabel, .centerY, headerBar, .centerY, .equal, 0),
            uiConstraint(countLabel, .trailing, headerBar, .trailing, .equal, -10),
            uiConstraint(countLabel, .centerY, headerBar, .centerY, .equal, 0),
        ])
    }

    private func setupTable() {
        tableView.backgroundColor = NSColor(hex: 0x0a0a0a)
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.rowHeight = 32
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(doubleClicked)
        tableView.target = self

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            uiConstraint(scrollView, .top, self, .top, .equal, 28),
            uiConstraint(scrollView, .leading, self, .leading, .equal, 0),
            uiConstraint(scrollView, .trailing, self, .trailing, .equal, 0),
            uiConstraint(scrollView, .bottom, self, .bottom, .equal, 0),
        ])
    }

    private func bind() {
        let state = AppState.shared
        Publishers.CombineLatest3(state.$tracks, state.$searchQuery, state.$currentTrack)
            .sinkOnMain { [weak self] _, _, _ in self?.reload() }
            .store(in: &cancellables)

        state.$isPlaying.sinkOnMain { [weak self] _ in self?.tableView.reloadData() }
            .store(in: &cancellables)
    }

    private func reload() {
        displayedTracks = AppState.shared.filteredTracks
        countLabel.stringValue = "\(displayedTracks.count) tracks"
        tableView.reloadData()
    }

    @objc private func doubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < displayedTracks.count else { return }
        AppState.shared.play(track: displayedTracks[row])
    }

    // MARK: - DataSource

    func numberOfRows(in tableView: NSTableView) -> Int { displayedTracks.count }

    // MARK: - Delegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let track = displayedTracks[row]
        let state = AppState.shared
        let isActive = track.path == state.currentTrack?.path
        let isPlaying = isActive && state.isPlaying

        let cell = TrackCellView()
        cell.configure(track: track, isActive: isActive, isPlaying: isPlaying)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rv = NSTableRowView()
        rv.isEmphasized = false
        return rv
    }
}

// MARK: - Cell

private final class TrackCellView: NSView {
    private let nameLabel = uiLabel("")
    private let formatBadge = uiLabel("")
    private let accentBar = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        nameLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        uiStyleLabel(formatBadge, 8, .medium, 0x444444)
        uiBorder(formatBadge, 0x2a2a2a)
        formatBadge.setContentHuggingPriority(.required, for: .horizontal)
        formatBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        uiBackground(accentBar, 0x4a9eff)

        uiInstall(self, [accentBar, nameLabel, formatBadge])

        NSLayoutConstraint.activate([
            uiConstraint(accentBar, .leading, self, .leading, .equal, 0),
            uiConstraint(accentBar, .top, self, .top, .equal, 0),
            uiConstraint(accentBar, .bottom, self, .bottom, .equal, 0),
            uiConstraint(accentBar, .width, nil, .notAnAttribute, .equal, 2),

            uiConstraint(nameLabel, .leading, self, .leading, .equal, 12),
            uiConstraint(nameLabel, .centerY, self, .centerY, .equal, 0),
            uiConstraint(nameLabel, .trailing, formatBadge, .leading, .lessThanOrEqual, -8),

            uiConstraint(formatBadge, .trailing, self, .trailing, .equal, -10),
            uiConstraint(formatBadge, .centerY, self, .centerY, .equal, 0),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(track: Track, isActive: Bool, isPlaying: Bool) {
        nameLabel.stringValue = track.displayTitle
        nameLabel.textColor = isActive ? NSColor(hex: 0x4a9eff) : NSColor(hex: 0xe0e0e0)
        nameLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: isActive ? .bold : .regular)

        let ext = URL(fileURLWithPath: track.path).pathExtension.uppercased()
        formatBadge.stringValue = " \(ext) "

        layer?.backgroundColor = isActive ? NSColor(hex: 0x151515).cgColor : nil
        accentBar.isHidden = !isActive
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Subtle row separator
        NSColor(hex: 0x1a1a1a).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}
