import Foundation
import Combine

@main @MainActor struct ObservationAudit {
    static var checks: [[String: Any]] = []
    static var traces: [String: [String]] = [:]
    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        checks.append(["name": name, "pass": condition, "detail": detail])
        if !condition { print("FAIL \(name) \(detail)") }
    }
    static func text<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }
    static func track(_ value: Track) -> String {
        text([value.id, value.path, value.title, value.artist, value.album,
              String(value.duration), String(value.analyzed)])
    }
    static func exercise<Value>(_ name: String, _ key: ReferenceWritableKeyPath<AppState, Value>,
                                _ publisher: (AppState) -> Published<Value>.Publisher,
                                _ first: Value, _ second: Value, _ render: @escaping (Value) -> String) {
        for objectFirst in [true, false] {
            let label = name + (objectFirst ? "/object-first" : "/property-first")
            let state = AppState()
            var events: [String] = []
            let initial = render(state[keyPath: key])
            var object: AnyCancellable!
            var property: AnyCancellable!
            func observeObject() { object = state.objectWillChange.sink { events.append("object|" + render(state[keyPath: key])) } }
            func observeProperty() { property = publisher(state).sink { events.append("property|" + render($0) + "|stored:" + render(state[keyPath: key])) } }
            if objectFirst { observeObject(); observeProperty() }
            else { observeProperty(); observeObject() }
            check(label + " initial subscription emits one property value and no object event",
                  events == ["property|" + initial + "|stored:" + initial], text(events))
            let identity = state.objectWillChange
            check(label + " repeated publisher access preserves identity", (0..<50).allSatisfy { _ in state.objectWillChange === identity })
            for (step, value) in [("new", first), ("unchanged", first), ("second", second)] {
                let old = render(state[keyPath: key]); let new = render(value)
                events = []
                state[keyPath: key] = value
                let expected = ["object|" + old, "property|" + new + "|stored:" + old]
                check(label + " " + step + " exact notification order and old storage", events == expected, text(events))
                check(label + " " + step + " stores new value after notifications", render(state[keyPath: key]) == new)
                traces[label + "/" + step] = events
            }
            object.cancel(); events = []
            let old = render(state[keyPath: key])
            state[keyPath: key] = first
            check(label + " object cancellation leaves direct publisher connected",
                  events == ["property|" + render(first) + "|stored:" + old], text(events))
            property.cancel(); events = []
            state[keyPath: key] = second
            check(label + " cancelling both suppresses later emissions", events.isEmpty)
        }
        do {
            let state = AppState(); let old = render(state[keyPath: key]); var events: [String] = []
            let token = state.objectWillChange.sink { events.append(render(state[keyPath: key])) }
            state[keyPath: key] = first
            check(name + " object-only subscription works without accessing projected publisher", events == [old])
            token.cancel()
        }
        do {
            let state = AppState(); let old = render(state[keyPath: key]); var events: [String] = []
            let token = publisher(state).sink { events.append(render($0) + "|stored:" + render(state[keyPath: key])) }
            state[keyPath: key] = first
            check(name + " direct publisher works before any object publisher access",
                  events == [old + "|stored:" + old, render(first) + "|stored:" + old])
            token.cancel()
        }
    }
    static func nested<Value>(_ name: String, _ key: KeyPath<AppState, Value>,
                              _ publisher: (AppState) -> Published<Value>.Publisher,
                              _ state: AppState, _ mutate: () -> Void, _ render: @escaping (Value) -> String) {
        let old = render(state[keyPath: key]); var events: [String] = []
        let object = state.objectWillChange.sink { events.append("object|" + render(state[keyPath: key])) }
        let property = publisher(state).dropFirst().sink { events.append("property|" + render($0) + "|stored:" + render(state[keyPath: key])) }
        mutate()
        let new = render(state[keyPath: key])
        check(name + " exact nested mutation event and old storage", old != new && events == ["object|" + old, "property|" + new + "|stored:" + old], text(events))
        traces[name] = events
        object.cancel(); property.cancel()
    }
    static func main() throws {
        let a = Track(id: "a", path: "/fixture/a.wav", title: "A", artist: "artist", album: "album", duration: 10)
        let b = Track(id: "b", path: "/fixture/b.wav", title: "B", artist: "other", album: "next", duration: 20)
        var eq = EQProfile.flat; eq.preamp = -4; eq.bands[0].gain = 2
        exercise("tracks", \.tracks, { $0.$tracks }, [a], [b], { text($0.map(track)) })
        exercise("folders", \.folders, { $0.$folders }, ["/a"], ["/b"], text)
        exercise("searchQuery", \.searchQuery, { $0.$searchQuery }, "alpha", "beta", text)
        exercise("currentTrack", \.currentTrack, { $0.$currentTrack }, a, b, { $0.map(track) ?? "nil" })
        exercise("isPlaying", \.isPlaying, { $0.$isPlaying }, true, false, text)
        exercise("currentTime", \.currentTime, { $0.$currentTime }, 3, 6, text)
        exercise("duration", \.duration, { $0.$duration }, 10, 20, text)
        exercise("volume", \.volume, { $0.$volume }, 0.3, 0.6, text)
        exercise("shuffle", \.shuffle, { $0.$shuffle }, true, false, text)
        exercise("repeatMode", \.repeatMode, { $0.$repeatMode }, true, false, text)
        exercise("eqProfile", \.eqProfile, { $0.$eqProfile }, eq, .flat, text)
        exercise("eqBypassed", \.eqBypassed, { $0.$eqBypassed }, true, false, text)
        exercise("showEQ", \.showEQ, { $0.$showEQ }, false, true, text)
        exercise("spectrumData", \.spectrumData, { $0.$spectrumData }, [0.1, 0.2], [0.3], text)
        exercise("waveformData", \.waveformData, { $0.$waveformData }, [0.2, 0.8], [0.1], text)
        do {
            let state = AppState(); state.tracks = [a]; state.currentTrack = a
            nested("nested band gain", \.eqProfile, { $0.$eqProfile }, state, { state.eqProfile.bands[0].gain = 4 }, text)
            nested("nested preamp", \.eqProfile, { $0.$eqProfile }, state, { state.eqProfile.preamp = -3 }, text)
            nested("nested track array", \.tracks, { $0.$tracks }, state, { state.tracks[0].title = "Changed" }, { text($0.map(track)) })
            nested("nested optional track", \.currentTrack, { $0.$currentTrack }, state, { state.currentTrack?.title = "Changed" }, { $0.map(track) ?? "nil" })
            nested("nested waveform append", \.waveformData, { $0.$waveformData }, state, { state.waveformData.append(0.5) }, text)
        }
        do {
            let state = AppState(); var left: [Float] = []; var right: [Float] = []; var objectCounts = [0, 0]
            let a = state.$volume.sink { left.append($0) }; let b = state.$volume.sink { right.append($0) }
            let c = state.objectWillChange.sink { objectCounts[0] += 1 }
            let d = state.objectWillChange.sink { objectCounts[1] += 1 }
            state.volume = 0.3; c.cancel(); a.cancel(); state.volume = 0.6
            check("multiple subscribers independently retain values and cancellation", left == [0.8, 0.3] && right == [0.8, 0.3, 0.6] && objectCounts == [1, 2])
            b.cancel(); d.cancel()
        }
        do {
            var state: AppState? = AppState(); weak var weakState = state
            let object = state!.objectWillChange
            let property = state!.$volume
            var changes = 0; var values: [Float] = []
            let a = object.sink { changes += 1 }; let b = property.sink { values.append($0) }
            state = nil
            check("retained publishers and subscriptions do not retain AppState", weakState == nil)
            object.send()
            check("retained publisher remains independent after owner deinit", changes == 1 && values == [0.8])
            a.cancel(); b.cancel()
        }
        for trigger in ["object", "property"] {
            let state = AppState(); var events: [String] = []; var reentered = false
            let object = state.objectWillChange.sink {
                events.append("object|" + text(state.volume))
                if trigger == "object" && !reentered { reentered = true; state.volume = 0.4 }
            }
            let property = state.$volume.dropFirst().sink {
                events.append("property|" + text($0) + "|stored:" + text(state.volume))
                if trigger == "property" && !reentered { reentered = true; state.volume = 0.4 }
            }
            state.volume = 0.2
            let expected = trigger == "object" ? ["object|0.8", "object|0.8", "property|0.4|stored:0.8", "property|0.2|stored:0.4"] :
                ["object|0.8", "property|0.2|stored:0.8", "object|0.8", "property|0.4|stored:0.8"]
            check(trigger + " reentrant same-property updates preserve exact order", events == expected, text(events))
            check(trigger + " reentrant updates preserve final outer value and engine control", state.volume == 0.2 && state.audioEngine.volume == 0.2)
            traces[trigger + " reentrant"] = events
            object.cancel(); property.cancel()
        }
        do {
            let state = AppState(); var changes = 0; var token: AnyCancellable?
            token = state.objectWillChange.sink { changes += 1; token?.cancel() }
            state.volume = 0.2; state.volume = 0.4
            check("object cancellation inside its callback prevents later delivery", changes == 1)
        }
        let failed = checks.filter { $0["pass"] as? Bool != true }.count
        let report: [String: Any] = ["passed": checks.count - failed, "failed": failed, "checks": checks, "traces": traces]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("RESULT \(checks.count - failed)/\(checks.count) observation assertions")
        exit(failed == 0 ? 0 : 1)
    }
}
