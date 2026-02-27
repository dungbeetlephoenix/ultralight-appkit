import AppKit
import Combine

final class TrackListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let headerBar = NSView()
    private let countLabel = NSTextField(labelWithString: "0 tracks")
    private let eqBtn = NSButton(title: "EQ", target: nil, action: nil)
    private var cancellables = Set<AnyCancellable>()
    private var displayedTracks: [Track] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x0a0a0a).cgColor
        setupHeader()
        setupTable()
        bind()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupHeader() {
        headerBar.wantsLayer = true
        headerBar.layer?.backgroundColor = NSColor(hex: 0x111111).cgColor
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerBar)

        let libLabel = NSTextField(labelWithString: "LIBRARY")
        libLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        libLabel.textColor = NSColor(hex: 0x4a9eff)

        countLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        countLabel.textColor = NSColor(hex: 0x555555)

        for v in [libLabel, countLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            headerBar.addSubview(v)
        }

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 28),
            libLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 10),
            libLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -10),
            countLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
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
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func bind() {
        let state = AppState.shared
        Publishers.CombineLatest3(state.$tracks, state.$searchQuery, state.$currentTrack)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.reload() }
            .store(in: &cancellables)

        state.$isPlaying.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.tableView.reloadData() }
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
        let isActive = track.id == state.currentTrack?.id
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
    private let nameLabel = NSTextField(labelWithString: "")
    private let formatBadge = NSTextField(labelWithString: "")
    private let accentBar = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        nameLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        formatBadge.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium)
        formatBadge.textColor = NSColor(hex: 0x444444)
        formatBadge.wantsLayer = true
        formatBadge.layer?.borderColor = NSColor(hex: 0x2a2a2a).cgColor
        formatBadge.layer?.borderWidth = 1
        formatBadge.setContentHuggingPriority(.required, for: .horizontal)
        formatBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = NSColor(hex: 0x4a9eff).cgColor

        for v in [accentBar, nameLabel, formatBadge] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentBar.topAnchor.constraint(equalTo: topAnchor),
            accentBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 2),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: formatBadge.leadingAnchor, constant: -8),

            formatBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            formatBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
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
