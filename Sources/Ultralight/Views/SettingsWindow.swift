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
        let header = uiLabel("MUSIC FOLDERS")
        uiStyleLabel(header, 9, .bold, 0xe0e0e0)

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
        let addBtn = uiButton("ADD FOLDER")
        uiStyleButton(addBtn, 8, .medium, true, 0x4a9eff)
        uiBorder(addBtn, 0x2a2a2a)

        let wrapper = AddFolderAction(tableView: tableView)
        objc_setAssociatedObject(self, "addAction", wrapper, .OBJC_ASSOCIATION_RETAIN)
        addBtn.target = wrapper
        addBtn.action = #selector(AddFolderAction.invoke)

        // Layout
        uiInstall(content, [header, scrollView, addBtn] as [NSView])

        NSLayoutConstraint.activate([
            uiConstraint(header, .top, content, .top, .equal, 16),
            uiConstraint(header, .leading, content, .leading, .equal, 16),

            uiConstraint(scrollView, .top, header, .bottom, .equal, 8),
            uiConstraint(scrollView, .leading, content, .leading, .equal, 16),
            uiConstraint(scrollView, .trailing, content, .trailing, .equal, -16),
            uiConstraint(scrollView, .bottom, addBtn, .top, .equal, -12),

            uiConstraint(addBtn, .bottom, content, .bottom, .equal, -16),
            uiConstraint(addBtn, .centerX, content, .centerX, .equal, 0),
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

        let label = uiLabel(folder)
        uiStyleLabel(label, 10, .regular, 0xe0e0e0)
        label.lineBreakMode = .byTruncatingMiddle

        let removeBtn = uiButton("✕")
        uiStyleButton(removeBtn, 9, .regular, false, 0x555555)

        let action = RemoveFolderAction(path: folder, tableView: tableView)
        objc_setAssociatedObject(removeBtn, "action", action, .OBJC_ASSOCIATION_RETAIN)
        removeBtn.target = action
        removeBtn.action = #selector(RemoveFolderAction.invoke)

        uiInstall(cell, [label, removeBtn])

        NSLayoutConstraint.activate([
            uiConstraint(label, .leading, cell, .leading, .equal, 8),
            uiConstraint(label, .centerY, cell, .centerY, .equal, 0),
            uiConstraint(label, .trailing, removeBtn, .leading, .equal, -4),
            uiConstraint(removeBtn, .trailing, cell, .trailing, .equal, -8),
            uiConstraint(removeBtn, .centerY, cell, .centerY, .equal, 0),
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
