import AppKit
import Combine

final class DragInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    init(_ objects: [NSPasteboardWriting]) {
        draggingPasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        super.init()
        draggingPasteboard.clearContents()
        if !objects.isEmpty { draggingPasteboard.writeObjects(objects) }
    }
    deinit { draggingPasteboard.releaseGlobally() }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) { fatalError("unexpected use") }
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { fatalError("unexpected use") }
    func resetSpringLoading() { fatalError("unexpected use") }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) { fatalError("unexpected use") }
}

@main @MainActor struct DragAudit {
    static var checks: [[String: Any]] = []
    static func check(_ name: String, _ value: Bool, _ detail: String = "") {
        checks.append(["name":name,"pass":value,"detail":detail])
        print("\(value ? "PASS" : "FAIL") \(name) \(detail)")
    }
    static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fm = FileManager.default
        let a = base.appendingPathComponent("music", isDirectory: true)
        let b = base.appendingPathComponent("other", isDirectory: true)
        try fm.createDirectory(at: a, withIntermediateDirectories: true)
        try fm.createDirectory(at: b, withIntermediateDirectories: true)
        let one = a.appendingPathComponent("one.wav"), two = a.appendingPathComponent("two.wav"), three = b.appendingPathComponent("three.wav")
        for file in [one,two,three] { try Data([0]).write(to: file) }
        let state = AppState.shared
        state.folders = []
        let view = DropView(frame: .zero)
        var events: [[String]] = []
        let token = state.$folders.dropFirst().sink { events.append($0) }
        let first = DragInfo([one as NSURL, two as NSURL, a as NSURL, one as NSURL])
        check("drop advertises copy", view.draggingEntered(first) == .copy)
        check("duplicate file and folder drop accepted", view.performDragOperation(first))
        check("one folder added from duplicate parents", state.folders == [a.path])
        check("duplicate parents publish once", events == [[a.path]])
        check("duplicate parents persist once", ConfigStore.saved == [[a.path]])
        check("repeat drop accepted", view.performDragOperation(first))
        check("repeat drop emits and persists nothing", events.count == 1 && ConfigStore.saved.count == 1)
        let mixed = DragInfo([three as NSURL, one as NSURL, b as NSURL])
        check("mixed folders drop accepted", view.performDragOperation(mixed))
        check("first occurrence order remains stable", state.folders == [a.path,b.path])
        check("mixed existing parents add once", events.count == 2 && ConfigStore.saved.count == 2)
        let missingParent = base.appendingPathComponent("missing", isDirectory: true)
        let missing = DragInfo([missingParent.appendingPathComponent("absent.wav") as NSURL])
        check("missing file retains parent fallback", view.performDragOperation(missing) && state.folders.last == missingParent.path)
        let before = state.folders, count = ConfigStore.saved.count
        var invalidAccepted: [Bool] = []
        for invalid in [DragInfo([]), DragInfo(["ordinary text" as NSString]), DragInfo([URL(string:"https://example.com/music.wav")! as NSURL])] {
            invalidAccepted.append(view.performDragOperation(invalid))
        }
        check("non-file return values preserve baseline", invalidAccepted == [true,true,true])
        check("empty text and network drops add no folders", state.folders == before && ConfigStore.saved.count == count)
        let mixedWeb = DragInfo([URL(string:"https://example.com/music.wav")! as NSURL, two as NSURL, URL(string:"ftp://example.com/other.wav")! as NSURL, three as NSURL])
        check("mixed file and network drop is accepted", view.performDragOperation(mixedWeb))
        check("mixed file and network drop filters every network URL", state.folders == before && ConfigStore.saved.count == count)
        let dualParent = base.appendingPathComponent("dual-representation", isDirectory: true)
        let dualFile = dualParent.appendingPathComponent("new.wav")
        let dualItem = NSPasteboardItem()
        dualItem.setString(dualFile.absoluteString, forType: .fileURL)
        dualItem.setString("https://example.com/other.wav", forType: .URL)
        check("file item carrying additional web representation stays accepted", view.performDragOperation(DragInfo([dualItem])))
        check("additional web representation preserves its file folder", state.folders == before + [dualParent.path] && ConfigStore.saved.count == count + 1)
        let composed = base.path + "/caf\u{e9}", decomposed = base.path + "/cafe\u{301}"
        state.addFolder(composed)
        let unicodeCount = ConfigStore.saved.count
        state.addFolder(decomposed)
        check("addFolder preserves Swift canonical Unicode equality", state.folders.last == composed && ConfigStore.saved.count == unicodeCount && state.folders.count == 5)
        token.cancel()
        let failed = checks.filter { $0["pass"] as? Bool != true }.count
        let report: [String: Any] = ["checks":checks,"passed":checks.count-failed,"failed":failed,"scope":"Actual DropView with named test pasteboard and actual AppState; audio/scanner/storage are deterministic doubles. No real user config or audio."]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys])
        try data.write(to: base.appendingPathComponent("results.json"))
        print("RESULT \(checks.count-failed)/\(checks.count)")
        exit(failed == 0 ? 0 : 1)
    }
}
