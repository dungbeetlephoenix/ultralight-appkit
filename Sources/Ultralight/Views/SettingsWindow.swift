import AppKit

final class SettingsWindow: NSWindow {
    private static var instance: SettingsWindow?

    static func show() {
        if let existing = instance {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let win = SettingsWindow()
        instance = win
        win.makeKeyAndOrderFront(nil)
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Settings"
        backgroundColor = NSColor(hex: 0x111111)
        isReleasedWhenClosed = false
        center()

        let content = NSView()
        content.wantsLayer = true
        contentView = content

        // Header
        let header = NSTextField(labelWithString: "MUSIC FOLDERS")
        header.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        header.textColor = NSColor(hex: 0xe0e0e0)

        // Folder list
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        tableView.backgroundColor = NSColor(hex: 0x0a0a0a)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.selectionHighlightStyle = .none

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        let delegate = FolderTableDelegate()
        tableView.dataSource = delegate
        tableView.delegate = delegate
        objc_setAssociatedObject(self, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        // Buttons
        let addBtn = NSButton(title: "ADD FOLDER", target: nil, action: nil)
        addBtn.bezelStyle = .inline
        addBtn.isBordered = false
        addBtn.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium)
        addBtn.contentTintColor = NSColor(hex: 0x4a9eff)
        addBtn.wantsLayer = true
        addBtn.layer?.borderColor = NSColor(hex: 0x2a2a2a).cgColor
        addBtn.layer?.borderWidth = 1

        let wrapper = AddFolderAction(tableView: tableView)
        objc_setAssociatedObject(self, "addAction", wrapper, .OBJC_ASSOCIATION_RETAIN)
        addBtn.target = wrapper
        addBtn.action = #selector(AddFolderAction.invoke)

        // Layout
        for v in [header, scrollView, addBtn] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: addBtn.topAnchor, constant: -12),

            addBtn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            addBtn.centerXAnchor.constraint(equalTo: content.centerXAnchor),
        ])
    }
}

private final class FolderTableDelegate: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        AppState.shared.folders.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let folder = AppState.shared.folders[row]
        let cell = NSView()
        cell.wantsLayer = true

        let label = NSTextField(labelWithString: folder)
        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        label.textColor = NSColor(hex: 0xe0e0e0)
        label.lineBreakMode = .byTruncatingMiddle

        let removeBtn = NSButton(title: "✕", target: nil, action: nil)
        removeBtn.bezelStyle = .inline
        removeBtn.isBordered = false
        removeBtn.font = NSFont.systemFont(ofSize: 9)
        removeBtn.contentTintColor = NSColor(hex: 0x555555)

        let action = RemoveFolderAction(path: folder, tableView: tableView)
        objc_setAssociatedObject(removeBtn, "action", action, .OBJC_ASSOCIATION_RETAIN)
        removeBtn.target = action
        removeBtn.action = #selector(RemoveFolderAction.invoke)

        for v in [label, removeBtn] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(v)
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: removeBtn.leadingAnchor, constant: -4),
            removeBtn.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            removeBtn.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }
}

private final class RemoveFolderAction: NSObject {
    let path: String
    weak var tableView: NSTableView?
    init(path: String, tableView: NSTableView) {
        self.path = path
        self.tableView = tableView
    }
    @objc func invoke() {
        AppState.shared.removeFolder(path)
        tableView?.reloadData()
    }
}

private final class AddFolderAction: NSObject {
    weak var tableView: NSTableView?
    init(tableView: NSTableView) { self.tableView = tableView }
    @objc func invoke() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                AppState.shared.addFolder(url.path)
            }
            tableView?.reloadData()
        }
    }
}
