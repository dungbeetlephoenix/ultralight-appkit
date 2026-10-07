import AppKit
import Combine

final class TrackListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let countLabel = uiLabel("0 tracks")
    private var cancellables = [AnyCancellable]()
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
        let headerBar = NSView()
        uiBackground(headerBar, 0x111111)
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerBar)

        let libLabel = uiLabel("LIBRARY")
        uiStyleLabel(libLabel, 10, .bold, 0x4a9eff)

        uiStyleLabel(countLabel, 10, .regular, 0x555555)

        uiInstall(headerBar, [libLabel, countLabel])

        uiAlign(headerBar, .top, to: self)
        uiAlign(headerBar, .leading, to: self)
        uiAlign(headerBar, .trailing, to: self)
        uiDimension(headerBar, .height, 28)
        uiAlign(libLabel, .leading, to: headerBar, offset: 10)
        uiAlign(libLabel, .centerY, to: headerBar)
        uiAlign(countLabel, .trailing, to: headerBar, offset: -10)
        uiAlign(countLabel, .centerY, to: headerBar)
    }

    private func setupTable() {
        let scrollView = NSScrollView()
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

        uiFill(scrollView, in: self, top: 28)
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

        return makeTrackCell(track: track, isActive: isActive)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rv = NSTableRowView()
        rv.isEmphasized = false
        return rv
    }
}

// MARK: - Cell

private func makeTrackCell(track: Track, isActive: Bool) -> NSView {
    let nameLabel = uiLabel("")
    let formatBadge = uiLabel("")
    let accentBar = NSView()

    let cell = uiContainer(border: .minY)



    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    uiStyleLabel(formatBadge, 8, .medium, 0x444444)
    uiBorder(formatBadge, 0x2a2a2a)
    formatBadge.setContentHuggingPriority(.required, for: .horizontal)
    formatBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

    uiBackground(accentBar, 0x4a9eff)

    uiInstall(cell, [accentBar, nameLabel, formatBadge])

    uiAlign(accentBar, .leading, to: cell)
    uiAlign(accentBar, .top, to: cell)
    uiAlign(accentBar, .bottom, to: cell)
    uiDimension(accentBar, .width, 2)

    uiAlign(nameLabel, .leading, to: cell, offset: 12)
    uiAlign(nameLabel, .centerY, to: cell)
    uiConstrain(nameLabel, .trailing, formatBadge, .leading, .lessThanOrEqual, -8)

    uiAlign(formatBadge, .trailing, to: cell, offset: -10)
    uiAlign(formatBadge, .centerY, to: cell)

    nameLabel.stringValue = track.displayTitle
    uiStyleLabel(nameLabel, 12, isActive ? .bold : .regular, isActive ? 0x4a9eff : 0xe0e0e0)

    let ext = URL(fileURLWithPath: track.path).pathExtension.uppercased()
    formatBadge.stringValue = " \(ext) "

    cell.layer?.backgroundColor = isActive ? NSColor(hex: 0x151515).cgColor : nil
    accentBar.isHidden = !isActive

    return cell
}
