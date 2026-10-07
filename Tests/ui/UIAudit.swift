import AppKit
import Combine
import Foundation

@main
struct UIAudit {
    static var checks: [[String: Any]] = []
    static var geometryChecks: [[String: Any]] = []
    static var finishingChecks: [[String: Any]] = []
    static var lifecycleChecks: [[String: Any]] = []
    static var observations: [[String: Any]] = []
    static var layouts: [[String: Any]] = []
    static let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ULTRALIGHT_UI_AUDIT_OUTPUT"]!)

    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        checks.append(["name": name, "pass": condition, "detail": detail])
        print("\(condition ? "PASS" : "FAIL") \(name) \(detail)")
    }

    static func pump(_ window: NSWindow? = nil) {
        let deadline = Date(timeIntervalSinceNow: 0.12)
        while Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.contentView?.displayIfNeeded()
    }

    static func descendants(_ root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { descendants($0) }
    }

    static func labels(_ root: NSView) -> [NSTextField] { descendants(root).compactMap { $0 as? NSTextField } }
    static func hasLabel(_ root: NSView, _ value: String) -> Bool { labels(root).contains { $0.stringValue == value && !$0.isHidden } }
    static func button(_ root: NSView, _ title: String) -> NSButton? { descendants(root).compactMap { $0 as? NSButton }.first { $0.title == title } }
    static func click(_ root: NSView, _ title: String) {
        guard let b = button(root, title) else { check("button exists: \(title)", false); return }
        check("button target/action wired: \(title)", b.target != nil && b.action != nil)
        b.performClick(nil)
        pump(root.window)
    }

    static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1.1 }
    static func sameProfile(_ lhs: EQProfile?, _ rhs: EQProfile) -> Bool {
        guard let lhs else { return false }
        return lhs.preamp == rhs.preamp && lhs.bands.count == rhs.bands.count && zip(lhs.bands, rhs.bands).allSatisfy { a, b in a.frequency == b.frequency && a.gain == b.gain && a.bandwidth == b.bandwidth }
    }
    static func rect(_ r: NSRect) -> [String: Double] { ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height] }

    static func snapshot(_ view: NSView, _ name: String) {
        // Fix the offscreen pixel density independently of the attached screen.
        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(view.bounds.width * scale)), pixelsHigh: Int(ceil(view.bounds.height * scale)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            check("snapshot \(name)", false, "No bitmap representation"); return
        }
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { check("snapshot \(name)", false, "PNG encoding failed"); return }
        do {
            try data.write(to: output.appendingPathComponent(name + ".png"))
            check("snapshot \(name)", bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
        } catch { check("snapshot \(name)", false, error.localizedDescription) }
    }

    static func inspectLayout(_ window: MainWindow, _ name: String, _ size: NSSize) {
        window.setContentSize(size)
        pump(window)
        guard let content = window.contentView else { check("content exists", false); return }
        let h = window.headerView.convert(window.headerView.bounds, to: content)
        let t = window.trackListView.convert(window.trackListView.bounds, to: content)
        let e = window.eqPanelView.convert(window.eqPanelView.bounds, to: content)
        let p = window.playbackBar.convert(window.playbackBar.bounds, to: content)
        layouts.append(["name": name, "content": rect(content.bounds), "header": rect(h), "tracks": rect(t), "eq": rect(e), "playback": rect(p)])
        check("\(name): content size", near(content.bounds.width, size.width) && near(content.bounds.height, size.height))
        check("\(name): header layout", near(h.height, 50) && near(h.width, size.width) && near(h.maxY, size.height))
        check("\(name): playback layout", near(p.height, 96) && near(p.width, size.width) && near(p.minY, 0))
        check("\(name): EQ and library align", near(t.maxY, h.minY) && near(e.maxY, h.minY) && near(t.minY, p.maxY) && near(e.minY, p.maxY) && near(t.maxX, e.minX) && near(e.width, 230))
        check("\(name): positive library area", t.width > 300 && t.height > 200)
        let major = [window.headerView, window.trackListView, window.eqPanelView, window.playbackBar]
        check("\(name): major frames contained", major.allSatisfy { content.bounds.insetBy(dx: -1, dy: -1).contains($0.convert($0.bounds, to: content)) })
        let controls = descendants(window.playbackBar).compactMap { $0 as? NSButton }
        check("\(name): playback button frames", controls.allSatisfy { $0.bounds.width > 0 && $0.bounds.height > 0 && window.playbackBar.bounds.insetBy(dx: -1, dy: -1).contains($0.convert($0.bounds, to: window.playbackBar)) })
        inspectControlGeometry(window, name)
        snapshot(content, name)
    }

    static func inspectControlGeometry(_ window: MainWindow, _ name: String) {
        func verify(_ suffix: String, _ condition: Bool) {
            geometryChecks.append(["name": "\(name): \(suffix)", "pass": condition])
            print("\(condition ? "PASS" : "FAIL") geometry \(name): \(suffix)")
        }
        let bar = window.playbackBar
        guard let play = button(bar, "⏸") ?? button(bar, "▶"),
              let transport = play.superview as? NSStackView,
              let controls = transport.superview as? NSStackView,
              controls.arrangedSubviews.count == 7 else {
            verify("transport groups exist", false); return
        }
        let spacer = controls.arrangedSubviews[5]
        let eq = controls.arrangedSubviews[4]
        let volume = controls.arrangedSubviews[6]
        let t = transport.convert(transport.bounds, to: bar)
        let e = eq.convert(eq.bounds, to: bar)
        let v = volume.convert(volume.bounds, to: bar)
        func exact(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
        verify("fixed layout density", window.backingScaleFactor == 1)
        verify("trailing spacer fixed at zero", exact(spacer.bounds.width, 0) && !spacer.hasAmbiguousLayout)
        verify("transport stays beside EQ and volume", exact(t.maxX + 8, e.minX) && exact(e.maxX + 16, v.minX))
        verify("volume stays ten points from right edge", exact(v.maxX, bar.bounds.maxX - 10))
        verify("transport groups fit both window sizes", [t, e, v].allSatisfy { $0.width > 0 && $0.height > 0 && bar.bounds.contains($0) })
    }

    static func inspectSubscriptionOwnership() {
        let factories: [(String, () -> NSView)] = [
            ("header", { makeHeaderView() }),
            ("playback", { makePlaybackBarView() }),
            ("EQ", { makeEQPanelView() }),
        ]
        for (name, make) in factories {
            weak var root: NSView?
            weak var boundControl: NSView?
            var foundControl = false
            autoreleasepool {
                let view = make()
                root = view
                if name == "header" {
                    boundControl = labels(view).first { $0.stringValue.isEmpty }
                } else if name == "playback" {
                    boundControl = descendants(view).first { $0 is ProgressBarView }
                } else {
                    boundControl = descendants(view).first { $0 is EQSliderView }
                }
                foundControl = boundControl != nil
                // Initial @Published deliveries are still queued when ownership ends.
            }
            pump()
            for (detail, passed) in [("root releases with queued publications", root == nil),
                                     ("captured controls release after cancellation", foundControl && boundControl == nil)] {
                lifecycleChecks.append(["name": "\(name): \(detail)", "pass": passed])
                print("\(passed ? "PASS" : "FAIL") lifecycle \(name): \(detail)")
            }
        }
    }

    static func finishing(_ name: String, _ condition: Bool) {
        finishingChecks.append(["name": name, "pass": condition])
        print("\(condition ? "PASS" : "FAIL") finishing \(name)")
    }

    static func inspectFinishing(_ window: MainWindow) {
        let state = AppState.shared
        state.tracks = []
        state.currentTrack = nil
        state.isPlaying = false
        state.duration = 120
        state.currentTime = 30
        state.volume = 0.5
        state.eqProfile = .flat
        pump(window)
        let all = descendants(window.contentView!)
        func control(_ label: String) -> NSControl? { all.compactMap { $0 as? NSControl }.first { $0.cell?.accessibilityLabel() == label } }
        // Native AppKit controls export their cell as the unignored AX element.
        func element(_ control: NSControl) -> NSCell? { NSAccessibility.unignoredDescendant(of: control) as? NSCell }
        func action(_ control: NSControl, _ name: NSAccessibility.Action) -> Bool {
            guard let cell = element(control), cell.accessibilityActionNames().contains(name) else { return false }
            cell.accessibilityPerformAction(name)
            return true
        }
        func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
        let expected = ["Play", "Previous track", "Next track", "Shuffle", "Repeat", "Equalizer", "Settings"]
        finishing("glyph buttons expose readable labels and tooltips", expected.allSatisfy { label in
            guard let button = control(label) as? NSButton else { return false }
            return button.toolTip == label
        })
        state.isPlaying = true; pump(window)
        finishing("play label follows playback state", button(window.playbackBar, "⏸")?.cell?.accessibilityLabel() == "Pause")
        state.isPlaying = false; pump(window)
        for (label, get, set) in [
            ("Shuffle", { state.shuffle }, { (v: Bool) in state.shuffle = v }),
            ("Repeat", { state.repeatMode }, { (v: Bool) in state.repeatMode = v }),
            ("Equalizer", { state.showEQ }, { (v: Bool) in state.showEQ = v }),
            ("Bypass equalizer", { state.eqBypassed }, { (v: Bool) in state.eqBypassed = v }),
        ] {
            guard let button = control(label) as? NSButton else { finishing(label + " button exists", false); continue }
            set(false); pump(window)
            finishing(label + " exposes off state", number(element(button)?.accessibilityValue()) == 0)
            let pressed = action(button, .press); pump(window)
            finishing(label + " accessible press updates state", pressed && get() && number(element(button)?.accessibilityValue()) == 1)
        }
        state.showEQ = true
        state.eqBypassed = false
        pump(window)
        guard let seek = control("Playback position, seconds") as? ProgressBarView,
              let volume = control("Volume, percent") as? ProgressBarView,
              let preamp = control("Preamp, decibels") as? ProgressBarView else {
            finishing("native slider controls exist", false); return
        }
        let bands = descendants(window.eqPanelView).compactMap { $0 as? EQSliderView }
        let sliders: [ProgressBarView] = [seek, volume, preamp] + bands
        finishing("all custom controls expose slider roles", sliders.count == 11 && sliders.allSatisfy { element($0)?.accessibilityRole() == .slider })
        finishing("slider ranges use seconds percent and decibels", number(element(seek)?.accessibilityMinValue()) == 0 && number(element(seek)?.accessibilityMaxValue()) == 120 && number(element(volume)?.accessibilityMaxValue()) == 100 && ([preamp] + bands).allSatisfy { number(element($0)?.accessibilityMinValue()) == -12 && number(element($0)?.accessibilityMaxValue()) == 12 })
        finishing("slider accessible values match stored state", number(element(seek)?.accessibilityValue()) == 30 && number(element(volume)?.accessibilityValue()) == 50 && number(element(preamp)?.accessibilityValue()) == 0)
        finishing("EQ bands have distinct accessible frequency labels", Set(bands.compactMap { element($0)?.accessibilityLabel() }).count == 8)
        finishing("all slider controls accept keyboard focus", sliders.allSatisfy { $0.acceptsFirstResponder && window.makeFirstResponder($0) })

        let originalSeek = seek.onClick
        var seekFraction: Double?
        seek.onClick = { seekFraction = $0 }
        let oldSeek = seek.doubleValue
        let seekIncremented = action(seek, .increment)
        finishing("seek accessible increment reaches seek callback", seekIncremented && seek.doubleValue > oldSeek && seekFraction == seek.progress)
        _ = action(seek, .decrement)
        finishing("seek accessible decrement stays in range", seek.doubleValue < oldSeek + 1 && seek.doubleValue >= 0 && seekFraction == seek.progress)
        seek.onClick = originalSeek

        let volumeIncremented = action(volume, .increment); pump(window)
        finishing("volume accessible adjustment reaches model", volumeIncremented && state.volume > 0.5 && abs(volume.doubleValue - Double(state.volume) * 100) < 0.001)
        let preampIncremented = action(preamp, .increment); pump(window)
        finishing("preamp accessible adjustment reaches model", preampIncremented && state.eqProfile.preamp > 0 && abs(preamp.doubleValue - Double(state.eqProfile.preamp)) < 0.001)
        if let band = bands.first {
            let adjusted = action(band, .increment); pump(window)
            finishing("EQ accessible adjustment reaches correct band", adjusted && state.eqProfile.bands[0].gain > 0 && state.eqProfile.bands.dropFirst().allSatisfy { $0.gain == 0 })
            band.value = 12
            _ = action(band, .increment)
            finishing("EQ adjustment clamps at maximum", band.value == 12)
        }
        state.volume = 1; pump(window)
        _ = action(volume, .increment); pump(window)
        finishing("volume adjustment clamps at maximum", state.volume == 1 && volume.doubleValue == 100)
        state.duration = 0; pump(window)
        finishing("empty transport disables seeking", !seek.isEnabled && !seek.acceptsFirstResponder)
        state.duration = 120; state.currentTime = 30; state.volume = 0.5; pump(window)
        func key(_ code: UInt16, _ character: String) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                            windowNumber: window.windowNumber, context: nil, characters: character,
                            charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
        }
        window.makeFirstResponder(volume)
        volume.keyDown(with: key(124, String(UnicodeScalar(NSRightArrowFunctionKey)!))); pump(window)
        finishing("focused volume responds to keyboard", state.volume > 0.5)
        NSApplication.shared.setActivationPolicy(.accessory)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let activationDeadline = Date(timeIntervalSinceNow: 1)
        while Date() < activationDeadline {
            if let event = NSApplication.shared.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.02), inMode: .default, dequeue: true) {
                NSApplication.shared.sendEvent(event)
            }
        }
        pump(window)
        finishing("isolated test window becomes key for event routing", window.isKeyWindow)
        window.makeFirstResponder(bands[0])
        state.eqProfile = .flat
        state.volume = 0.5; pump(window)
        NSApplication.shared.sendEvent(key(126, String(UnicodeScalar(NSUpArrowFunctionKey)!))); pump(window)
        finishing("global volume shortcut yields to focused slider", state.eqProfile.bands[0].gain > 0 && state.volume == 0.5)
        if let equalizerButton = control("Equalizer") as? NSButton {
            state.showEQ = false; pump(window)
            let focused = window.makeFirstResponder(equalizerButton)
            NSApplication.shared.sendEvent(key(49, " ")); pump(window)
            finishing("focused glyph button receives Space without toggling playback", focused && state.showEQ && !state.isPlaying && !state.audioEngine.isPlaying)
        } else {
            finishing("focused glyph button receives Space without toggling playback", false)
        }
        window.makeFirstResponder(window)
        state.volume = 0.5; pump(window)
        NSApplication.shared.sendEvent(key(126, String(UnicodeScalar(NSUpArrowFunctionKey)!))); pump(window)
        finishing("unfocused playback volume shortcut still works", abs(state.volume - 0.55) < 0.0001)

        SettingsWindow.show()
        guard let settings = NSApplication.shared.windows.compactMap({ $0 as? SettingsWindow }).first,
              let folderTable = descendants(settings.contentView!).compactMap({ $0 as? NSTableView }).first else {
            finishing("settings window and table exist", false); return
        }
        let folder = output.appendingPathComponent("Music A").path
        state.folders = [folder]; pump(settings)
        finishing("settings tracks external folder changes while open", folderTable.numberOfRows == 1)
        let remove = descendants(settings.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "✕" }
        finishing("remove-folder action identifies its folder", remove?.cell?.accessibilityLabel() == "Remove folder " + folder && remove?.toolTip == "Remove folder " + folder)
        settings.orderOut(nil)
        state.folders = [folder, output.appendingPathComponent("Music B").path]
        SettingsWindow.show()
        finishing("reopening settings refreshes immediately", folderTable.numberOfRows == 2)
        let manager = MenuBarManager() // Never setup: no status item or device enumeration.
        manager.playerWindow = window
        window.orderOut(nil)
        _ = manager.perform(NSSelectorFromString("showWindow"))
        finishing("Show Player targets main window with Settings present", window.isVisible && settings.isVisible)
        _ = manager.perform(NSSelectorFromString("toggleWindow"))
        finishing("player toggle leaves Settings visible", !window.isVisible && settings.isVisible)
        _ = manager.perform(NSSelectorFromString("toggleWindow"))
        finishing("player toggle restores main window", window.isVisible && settings.isVisible)
        manager.playerWindow = nil
        window.orderOut(nil)
        _ = manager.perform(NSSelectorFromString("showWindow"))
        finishing("missing player target does not select another window", !window.isVisible && settings.isVisible)
        settings.orderOut(nil)
        finishing("finishing checks leave audio stopped", !state.audioEngine.isPlaying)
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let state = AppState.shared
        let dataRoot = ProcessInfo.processInfo.environment["ULTRALIGHT_UI_AUDIT_DATA_ROOT"]!
        check("config isolated", ConfigStore.dataDirectory.path.hasPrefix(dataRoot + "/"), ConfigStore.dataDirectory.path)
        check("fresh config empty", state.tracks.isEmpty && state.folders.isEmpty)
        check("audio silent before UI", !state.audioEngine.isPlaying)
        let window = MainWindow()
        pump(window)
        check("initial header cleared", window.title == "Ultralight")
        check("initial table count", hasLabel(window.trackListView, "0 tracks"))
        guard let table = descendants(window.trackListView).compactMap({ $0 as? NSTableView }).first else {
            check("NSTableView exists", false)
            finish()
            return
        }
        let a = Track(id: "audit-a", path: dataRoot + "/Aurora.flac", title: "Aurora", artist: "Glass Ensemble", album: "Northern Lights", duration: 245, analyzed: true)
        let b = Track(id: "audit-b", path: dataRoot + "/river.wav", title: "River", artist: "Orchard", album: "Quiet Water", duration: 190, analyzed: true)
        let c = Track(id: "audit-c", path: dataRoot + "/Fallback Name.m4a", title: "", artist: "", album: "Lost Signals", duration: 123, analyzed: true)
        state.tracks = [a, b, c]
        state.currentTrack = a
        state.duration = 245
        state.currentTime = 65
        state.volume = 0.37
        state.isPlaying = true // UI state only: never schedule audio or call play/resume.
        state.waveformData = (0..<64).map { Float(($0 % 7) + 1) / 8 }
        var profile = EQProfile.flat
        profile.preamp = -3
        profile.bands[0].gain = 5
        profile.bands[7].gain = -2
        state.eqProfile = profile
        pump(window)
        check("Combine header title", hasLabel(window.headerView, "Aurora") && window.title == "Aurora")
        check("Combine header artist", hasLabel(window.headerView, "Glass Ensemble"))
        check("Combine header format", hasLabel(window.headerView, " FLAC "))
        check("Combine time and duration", hasLabel(window.playbackBar, "1:05") && hasLabel(window.playbackBar, "4:05"))
        check("Combine volume label", hasLabel(window.playbackBar, "37%"))
        check("Combine play button", button(window.playbackBar, "⏸") != nil)
        let bars = descendants(window.playbackBar).compactMap { $0 as? ProgressBarView }
        check("Combine seek progress and waveform", bars.contains { abs($0.progress - 65.0 / 245.0) < 0.001 && $0.waveformData.count == 64 })
        check("Combine volume bar", bars.contains { abs($0.progress - 0.37) < 0.001 })
        let sliders = descendants(window.eqPanelView).compactMap { $0 as? EQSliderView }
        check("Combine all EQ bands", sliders.count == 8 && zip(sliders, profile.bands).allSatisfy { $0.value == $1.gain })
        check("Combine preamp label", hasLabel(window.eqPanelView, "-3"))
        check("Combine table tracks", table.numberOfRows == 3 && hasLabel(window.trackListView, "3 tracks"))
        for (query, expected, firstTitle) in [("AURORA", 1, "Aurora"), ("orchard", 1, "River"), ("lost signals", 1, "Fallback Name"), ("no matching track", 0, ""), ("", 3, "Aurora")] {
            state.searchQuery = query
            pump(window)
            check("filter \(query.isEmpty ? "clear" : query)", table.numberOfRows == expected && hasLabel(window.trackListView, "\(expected) tracks"))
            if expected > 0, let cell = window.trackListView.tableView(table, viewFor: table.tableColumns.first, row: 0) {
                check("filter row title \(query.isEmpty ? "clear" : query)", hasLabel(cell, firstTitle))
            }
        }
        click(window.playbackBar, "⤮")
        check("shuffle action on", state.shuffle)
        click(window.playbackBar, "⤮")
        check("shuffle action off", !state.shuffle)
        click(window.playbackBar, "↻")
        check("repeat action on", state.repeatMode)
        click(window.playbackBar, "↻")
        check("repeat action off", !state.repeatMode)
        let priorLibraryWidth = window.trackListView.frame.width
        click(window.playbackBar, "EQ")
        check("EQ toggle hidden", !state.showEQ && window.eqPanelView.isHidden)
        if near(window.trackListView.frame.width, priorLibraryWidth) {
            observations.append(["name": "EQ hiding reserves panel width", "detail": "Hiding EQ leaves its fixed 230-point width reserved; the library does not expand.", "libraryWidth": priorLibraryWidth])
        }
        snapshot(window.contentView!, "eq-hidden")
        click(window.playbackBar, "EQ")
        check("EQ toggle shown", state.showEQ && !window.eqPanelView.isHidden)
        click(window.eqPanelView, "AUTO")
        check("EQ AUTO bypass on", state.eqBypassed)
        click(window.eqPanelView, "AUTO")
        check("EQ AUTO bypass off", !state.eqBypassed)
        click(window.eqPanelView, "SAVE")
        check("EQ SAVE isolated persistence", sameProfile(EQStore.profile(for: a.id), profile) && FileManager.default.fileExists(atPath: ConfigStore.dataDirectory.appendingPathComponent("eq-profiles.json").path))
        click(window.eqPanelView, "RST")
        check("EQ RST flat model and sliders", state.eqProfile.isFlat && sliders.allSatisfy { $0.value == 0 } && hasLabel(window.eqPanelView, "+0"))
        state.eqProfile = profile
        pump(window)
        inspectLayout(window, "default-900x600", NSSize(width: 900, height: 600))
        inspectLayout(window, "compact-600x400", NSSize(width: 600, height: 400))
        state.currentTrack = c
        state.isPlaying = false
        pump(window)
        check("fallback filename title", hasLabel(window.headerView, "Fallback Name") && window.title == "Fallback Name")
        check("empty artist hidden", !hasLabel(window.headerView, "Glass Ensemble"))
        check("paused symbol", button(window.playbackBar, "▶") != nil)
        state.currentTrack = nil
        pump(window)
        check("nil track resets header", window.title == "Ultralight" && !hasLabel(window.headerView, "Fallback Name") && !hasLabel(window.headerView, " M4A "))
        check("audio silent after UI", !state.audioEngine.isPlaying)
        inspectSubscriptionOwnership()
        inspectFinishing(window)
        finish()
    }

    static func finish() {
        let failed = checks.filter { ($0["pass"] as? Bool) != true }.count
        let geometryFailed = geometryChecks.filter { ($0["pass"] as? Bool) != true }.count
        let lifecycleFailed = lifecycleChecks.filter { ($0["pass"] as? Bool) != true }.count
        let finishingFailed = finishingChecks.filter { ($0["pass"] as? Bool) != true }.count
        let report: [String: Any] = ["finishingChecks": finishingChecks, "finishingFailed": finishingFailed, "checks": checks, "geometryChecks": geometryChecks, "geometryFailed": geometryFailed, "lifecycleChecks": lifecycleChecks, "lifecycleFailed": lifecycleFailed, "observations": observations, "layouts": layouts, "passed": checks.count - failed, "failed": failed, "scope": "Actual AppKit views, Combine bindings, target/action wiring, filtering, layout, and hidden-window bitmap rendering. Synthetic state only; playback was never started. ConfigStore redirected to isolated temporary storage."]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output.appendingPathComponent("results.json")) }
        print("RESULT \(checks.count - failed)/\(checks.count) checks passed; \(observations.count) observations")
        print("GEOMETRY \(geometryChecks.count - geometryFailed)/\(geometryChecks.count) checks passed")
        print("LIFECYCLE \(lifecycleChecks.count - lifecycleFailed)/\(lifecycleChecks.count) checks passed")
        print("FINISHING \(finishingChecks.count - finishingFailed)/\(finishingChecks.count) checks passed")
        exit(failed == 0 && geometryFailed == 0 && lifecycleFailed == 0 && finishingFailed == 0 ? 0 : 1)
    }
}
