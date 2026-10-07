import AppKit
import Combine

final class SettingsWindow: NSWindow, NSTableViewDataSource, NSTableViewDelegate {
    private static var instance: SettingsWindow?
    private let tableView = NSTableView()

    static func show() {
        if let existing = instance {
            existing.tableView.reloadData()
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
        tableView.backgroundColor = NSColor(hex: 0x0a0a0a)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.selectionHighlightStyle = .none

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        tableView.dataSource = self
        tableView.delegate = self
        uiRetain([AppState.shared.$folders.sinkOnMain { [weak tableView] _ in
            tableView?.reloadData()
        }], on: content)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        // Buttons
        let addBtn = uiButton("ADD FOLDER")
        uiStyleButton(addBtn, 8, .medium, true, 0x4a9eff)
        uiBorder(addBtn, 0x2a2a2a)

        uiAction(addBtn) { [weak tableView] in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = true
            if panel.runModal() == .OK {
                for url in panel.urls { AppState.shared.addFolder(url.path) }
                tableView?.reloadData()
            }
        }

        // Layout
        uiInstall(content, [header, scrollView, addBtn] as [NSView])

        uiAlign(header, .top, to: content, offset: 16)
        uiAlign(header, .leading, to: content, offset: 16)

        uiConstrain(scrollView, .top, header, .bottom, .equal, 8)
        uiAlign(scrollView, .leading, to: content, offset: 16)
        uiAlign(scrollView, .trailing, to: content, offset: -16)
        uiConstrain(scrollView, .bottom, addBtn, .top, .equal, -12)

        uiAlign(addBtn, .bottom, to: content, offset: -16)
        uiAlign(addBtn, .centerX, to: content)
    }

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
        uiDescribe(removeBtn, "Remove folder " + folder)
        uiStyleButton(removeBtn, 9, .regular, false, 0x555555)

        uiAction(removeBtn) { [weak tableView] in
            AppState.shared.removeFolder(folder)
            tableView?.reloadData()
        }

        uiInstall(cell, [label, removeBtn])

        uiAlign(label, .leading, to: cell, offset: 8)
        uiAlign(label, .centerY, to: cell)
        uiConstrain(label, .trailing, removeBtn, .leading, .equal, -4)
        uiAlign(removeBtn, .trailing, to: cell, offset: -8)
        uiAlign(removeBtn, .centerY, to: cell)

        return cell
    }
}
