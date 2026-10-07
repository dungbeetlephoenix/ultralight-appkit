import Foundation
import AppKit
import AVFoundation
import Combine

@main struct QualityGates {
    static var passed = 0
    static var failed = 0
    static var snapshots: [String: AnalysisResult] = [:]
    static func check(_ condition: Bool, _ name: String) {
        if condition { passed += 1; print("PASS \(name)") }
        else { failed += 1; print("FAIL \(name)") }
    }
    static func sameJSON<T: Encodable>(_ a: T, _ b: T) throws -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(a) == encoder.encode(b)
    }
    static func near(_ x: Float, _ y: Float, _ tolerance: Float = 0.01) -> Bool { abs(x-y) <= tolerance }
    static func wave(_ url: URL, channels: [[Float]], rate: Double = 48000) throws {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels.count))!
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        if channels[0].isEmpty { return }
        let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(channels[0].count))!
        buffer.frameLength = buffer.frameCapacity
        for c in channels.indices { channels[c].withUnsafeBufferPointer { data in buffer.floatChannelData![c].update(from: data.baseAddress!, count: data.count) } }
        try file.write(from: buffer)
    }
    static func tone(_ hz: Float, frames: Int = 48000, amplitude: Float = 0.5) -> [Float] {
        (0..<frames).map { amplitude * sin(2 * Float.pi * hz * Float($0) / 48000) }
    }
    @MainActor static func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
    @MainActor static func action(_ root: NSView, _ title: String) -> Bool {
        guard let b = allViews(root).compactMap({$0 as? NSButton}).first(where: {$0.title == title}), let a = b.action else { return false }
        return NSApplication.shared.sendAction(a, to: b.target, from: b)
    }
    // Literal fixtures describe the pre-optimization disk schema independently
    // of the candidate encoder, so a matching encoder/decoder bug cannot pass.
    static func checkPersistenceSchemas(fixtures: URL) throws {
        let band: [String: Any] = ["frequency": 310, "gain": -2.25, "bandwidth": 1.5]
        let secondBand: [String: Any] = ["frequency": 6000, "gain": 1.25, "bandwidth": 0.5]
        let profile: [String: Any] = ["bands": [band, secondBand], "preamp": -3.5]
        let config: [String: Any] = ["folders": ["/music/α", "/archive/space folder"], "theme": "light"]
        var analysis: [String: Any] = [
            "bassEnergy": 0.125, "midEnergy": 0.25, "trebleEnergy": 0.625,
            "spectralCentroid": 1234.5, "dynamicRange": 12.5, "peakLevel": -0.5,
            "suggestedEQ": profile,
            "isBassHeavy": true, "isBright": false, "isCompressed": true,
            "isClipping": false, "isDynamic": true, "isThin": false, "isMuddy": true,
        ]
        let b = try verifySchema(EQBand.self, fixture: band, name: "EQBand")
        check(b.frequency == 310 && b.gain == -2.25 && b.bandwidth == 1.5, "EQBand literal scalar mapping")
        let p = try verifySchema(EQProfile.self, fixture: profile, name: "EQProfile", savedFile: fixtures.appendingPathComponent("legacy-eq-profiles.json"))
        check(p.preamp == -3.5 && p.bands.count == 2 && p.bands[1].frequency == 6000 && p.bands[1].gain == 1.25 && p.bands[1].bandwidth == 0.5,
              "EQProfile literal scalar and nested mapping")
        let c = try verifySchema(ConfigStore.Config.self, fixture: config, name: "Config")
        check(c.folders == ["/music/α", "/archive/space folder"] && c.theme == "light", "Config literal scalar mapping")
        let a = try verifySchema(AnalysisResult.self, fixture: analysis, name: "AnalysisResult", savedFile: fixtures.appendingPathComponent("legacy-analysis-cache.json"))
        check([a.bassEnergy, a.midEnergy, a.trebleEnergy, a.spectralCentroid, a.dynamicRange, a.peakLevel] == [0.125, 0.25, 0.625, 1234.5, 12.5, -0.5],
              "AnalysisResult all six literal scalar mappings")
        check(try sameJSON(a.suggestedEQ, p), "AnalysisResult literal suggested EQ mapping")
        let flags = ["isBassHeavy", "isBright", "isCompressed", "isClipping", "isDynamic", "isThin", "isMuddy"]
        for selected in flags.indices {
            for index in flags.indices { analysis[flags[index]] = index == selected }
            let value = try JSONDecoder().decode(AnalysisResult.self, from: canonicalJSON(analysis))
            let actual = [value.isBassHeavy, value.isBright, value.isCompressed, value.isClipping, value.isDynamic, value.isThin, value.isMuddy]
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            let exactJSON = try canonicalJSON(encoded) == canonicalJSON(analysis)
            check(actual == flags.indices.map { $0 == selected } && exactJSON,
                  "AnalysisResult distinct flag mapping " + flags[selected])
        }
    }

    static func canonicalJSON(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }

    static func verifySchema<T: Codable>(_ type: T.Type, fixture: [String: Any], name: String, savedFile: URL? = nil) throws -> T {
        let expected = try canonicalJSON(fixture)
        let decoder = JSONDecoder()
        let value = try decoder.decode(type, from: expected)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        check(Set(encoded.keys) == Set(fixture.keys), name + " exact persisted keys")
        for key in fixture.keys.sorted() {
            check(try encoded[key].map { try canonicalJSON($0) } == canonicalJSON(fixture[key]!), name + " exact persisted value " + key)
            var missing = fixture; missing.removeValue(forKey: key)
            check((try? decoder.decode(type, from: canonicalJSON(missing))) == nil, name + " rejects missing " + key)
            var wrong = fixture; wrong[key] = fixture[key] is String ? 17 : "wrong-type"
            check((try? decoder.decode(type, from: canonicalJSON(wrong))) == nil, name + " rejects wrong type " + key)
        }
        var future = fixture; future["futureField"] = ["unknown": true]
        let extended = try decoder.decode(type, from: canonicalJSON(future))
        let extendedJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(extended))
        check(try canonicalJSON(extendedJSON) == expected, name + " tolerates unknown keys")
        if let savedFile {
            try canonicalJSON(["legacy": fixture]).write(to: savedFile)
            let saved = try decoder.decode([String: T].self, from: Data(contentsOf: savedFile))
            let savedJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved))
            check(try canonicalJSON(savedJSON) == canonicalJSON(["legacy": fixture]), name + " reads legacy persisted dictionary")
        }
        return value
    }

    @MainActor static func main() async throws {
        let scratch = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ULTRALIGHT_GATE_ROOT"]!)
        let fixtures = scratch.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        // Actual production AppState / views, isolated empty config; engine remains stopped.
        _ = NSApplication.shared
        let state = AppState.shared
        var volumes: [Float] = []
        var changes = 0
        let a = state.$volume.sink { volumes.append($0) }
        let b = state.objectWillChange.sink { changes += 1 }
        state.volume = 0.4
        check(volumes.count == 2 && near(volumes[0], 0.8) && near(volumes[1], 0.4), "Combine published initial and changed value")
        check(changes == 1, "Combine objectWillChange")
        var eqValues: [EQProfile] = []
        let c = state.$eqProfile.sink { eqValues.append($0) }
        state.eqProfile.bands[0].gain = 3
        check(eqValues.count == 2 && eqValues.last!.bands[0].gain == 3, "Combine nested EQ mutation")
        let playback = PlaybackBarView(frame: .zero)
        check(action(playback, "⤮") && state.shuffle, "AppKit shuffle target action")
        check(action(playback, "↻") && state.repeatMode, "AppKit repeat target action")
        check(action(playback, "EQ") && !state.showEQ, "AppKit EQ visibility target action")
        let eqPanel = EQPanelView(frame: .zero)
        check(action(eqPanel, "AUTO") && state.eqBypassed, "AppKit retained EQ wrapper action")
        check(action(eqPanel, "RST") && state.eqProfile.isFlat, "AppKit EQ reset action")
        withExtendedLifetime([a,b,c]) {}
        check(!state.audioEngine.isPlaying, "No playback during UI tests")

        let frequencies: [Float] = [60,170,310,600,1000,3000,6000,12000]
        check(EQBand.defaultBands.map(\.frequency) == frequencies, "Eight default EQ frequencies")
        check(EQProfile.flat.isFlat, "Flat EQ predicate")
        var profile = EQProfile.flat
        profile.preamp = -4
        profile.bands[0].gain = 5
        check(!profile.isFlat && EQProfile.flat.bands[0].gain == 0, "EQ value semantics")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        check(try sameJSON(decoder.decode(EQProfile.self, from: encoder.encode(profile)), profile), "EQ Codable round trip")
        try checkPersistenceSchemas(fixtures: fixtures)
        let track = Track(id: "test", path: "/test/example.flac", title: "", artist: "artist", album: "album", duration: 125)
        check(track.displayTitle == "example" && track.durationString == "2:05", "Track title fallback and duration")
        var trackCopy = track; trackCopy.title = "Changed"
        check(track.displayTitle == "example" && trackCopy.displayTitle == "Changed", "Track value semantics")
        var config = ConfigStore.Config(); config.folders = ["one", "two"]; config.theme = "light"
        ConfigStore.save(config)
        let loaded = ConfigStore.load()
        check(loaded.folders == config.folders && loaded.theme == config.theme, "Config persisted round trip")
        EQStore.save(profile: profile, for: "fixture")
        check(try sameJSON(EQStore.profile(for: "fixture"), profile), "EQ cache save lookup")
        let eqDisk = try decoder.decode([String:EQProfile].self, from: Data(contentsOf: ConfigStore.dataDirectory.appendingPathComponent("eq-profiles.json")))
        check(try sameJSON(eqDisk["fixture"], profile), "EQ disk format round trip")
        EQStore.remove(for: "fixture")
        check(EQStore.profile(for: "fixture") == nil, "EQ removal")
        let hashes: [(Int, String)] = [
            (0, "cfcd208495d565ef66e7dff9f98764da"),
            (10, "e41d8b1e86f0fae80e9d18029242cfc3"),
            (65535, "b097762e16fe73926084f925cca58d6d"),
            (65536, "03e0567fc6ccbf2c02cc21c4a7cf238d"),
            (65537, "9606c154f8d286c1b15abf944500333f"),
            (131072, "36d9de3c330b98db04ca71f17521728b"),
            (131073, "566a846afda08e671e06ceb358fd97ae"),
        ]
        for (length, expected) in hashes {
            let url = fixtures.appendingPathComponent("hash-\(length).bin")
            try Data((0..<length).map {UInt8($0 % 251)}).write(to: url)
            check(FileHasher.hash(path: url.path) == expected, "Legacy hash boundary \(length)")
        }
        check(FileHasher.hash(path: "/definitely/not/present") == nil, "Missing file hash")
        let silence = fixtures.appendingPathComponent("silence.wav")
        try wave(silence, channels: [[Float](repeating: 0, count: 48000)])
        check(await AudioAnalyzer.analyze(path: silence.path) == nil, "Silent analysis omitted")
        check(await AudioAnalyzer.analyze(path: "/definitely/not/present") == nil, "Missing analysis omitted")
        let short = fixtures.appendingPathComponent("short.wav")
        try wave(short, channels: [tone(1000, frames: 512)])
        check(await AudioAnalyzer.analyze(path: short.path) == nil, "Short analysis omitted")
        let cases: [(String, Float, Int, [Float])] = [
            ("bass", 93.75, 0, [-3,-2,0,0,0,0,1.5,2]),
            ("mid", 996.09375, 1, [3,2,1,-2,-1.5,0,0,0]),
            ("treble", 7992.1875, 2, [5,3.5,1,0,0,0,-2,-3])
        ]
        for (name, frequency, band, gains) in cases {
            let url = fixtures.appendingPathComponent("\(name).wav")
            try wave(url, channels: [tone(frequency)])
            guard let result = await AudioAnalyzer.analyze(path: url.path) else { check(false,"\(name) analysis exists"); continue }
            snapshots[name] = result
            let energies = [result.bassEnergy,result.midEnergy,result.trebleEnergy]
            check(energies[band] > 0.999, "\(name) correct spectral band")
            check(near(energies.reduce(0,+), 1, 0.00001), "\(name) normalized energies")
            check(near(result.spectralCentroid,frequency,1), "\(name) spectral centroid")
            check(near(result.peakLevel,-6.0206,0.005), "\(name) peak level")
            check(near(result.dynamicRange,3.0103,0.02), "\(name) crest estimate")
            check(result.suggestedEQ.bands.map(\.gain) == gains, "\(name) auto EQ signature")
            check(try sameJSON(decoder.decode(AnalysisResult.self, from: encoder.encode(result)), result), "\(name) analysis Codable round trip")
            AnalysisStore.save(result: result, for: name)
            check(try sameJSON(AnalysisStore.result(for: name), result), "\(name) analysis cache lookup")
        }
        let analysisDisk = try decoder.decode([String:AnalysisResult].self, from: Data(contentsOf: ConfigStore.dataDirectory.appendingPathComponent("analysis-cache.json")))
        check(try sameJSON(analysisDisk, snapshots), "Analysis disk format round trip")
        let waveform = await AudioAnalyzer.computeWaveform(path: fixtures.appendingPathComponent("mid.wav").path)
        check(waveform?.count == 200, "Waveform 200 bins")
        check(waveform?.allSatisfy({$0.isFinite && $0 >= 0 && $0 <= 1}) == true, "Waveform finite normalized bounds")
        check(near(waveform?.max() ?? -1, 1, 0.000001), "Waveform peak normalized to one")
        let silentWaveform = await AudioAnalyzer.computeWaveform(path: silence.path)
        check(silentWaveform?.allSatisfy({$0 == 0}) == true, "Silent waveform zeros")
        check(await AudioAnalyzer.computeWaveform(path: "/definitely/not/present") == nil, "Missing waveform omitted")
        let scanDir = scratch.appendingPathComponent("scan")
        try FileManager.default.createDirectory(at: scanDir.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("bass.wav"), to: scanDir.appendingPathComponent("b.WAV"))
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("mid.wav"), to: scanDir.appendingPathComponent("nested/a.wav"))
        try FileManager.default.copyItem(at: silence, to: scanDir.appendingPathComponent(".hidden.wav"))
        try Data("not audio".utf8).write(to: scanDir.appendingPathComponent("ignore.txt"))
        let scanned = await FolderScanner.scan(folders: [scanDir.path])
        check(scanned.map(\.displayTitle) == ["b", "a"], "Scanner recursive uppercase extension and sorting")
        check(scanned.count == 2 && scanned.allSatisfy({abs($0.duration-1) < 0.0001}), "Scanner duration metadata")
        check(Set(scanned.map(\.id)).count == 2, "Scanner content identities")
        check(await FolderScanner.scan(folders: [scratch.appendingPathComponent("missing").path]).isEmpty, "Missing folder scan")

        // Baseline mode excludes known defects and potentially crashing invalid-resolution calls.
        if ProcessInfo.processInfo.environment["ULTRALIGHT_GATE_BASELINE"] != "1" {
        // Exercise the actual live spectrum callback with synthetic PCM; no engine output.
        func liveSpectrum(frames: Int, rate: Double = 48000, frequency: Float, antiphase: Bool = false, rightOnly: Bool = false) -> [Float]? {
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
            buffer.frameLength = buffer.frameCapacity
            let signal = tone(frequency, frames: frames)
            for i in 0..<frames {
                buffer.floatChannelData![0][i] = rightOnly ? 0 : signal[i]
                buffer.floatChannelData![1][i] = antiphase ? -signal[i] : signal[i]
            }
            return state.audioEngine.gateSpectrum(buffer)
        }
        for frames in [256,512,1024,1536] {
            let values = liveSpectrum(frames: frames, frequency: 93.75)
            check(values?.count == 32 && values!.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, "Live spectrum \(frames)-frame buffer bounds")
            check(values != nil && values![0] > 0.9 && values![0] > values![20], "Live spectrum \(frames)-frame bass localization")
        }
        let trebleLive = liveSpectrum(frames: 512, frequency: 12000)
        check(trebleLive != nil && trebleLive![16] > 0.9 && trebleLive![16] > trebleLive![0], "Live spectrum short buffer treble localization")
        let inPhaseLive = liveSpectrum(frames: 1024, frequency: 937.5)
        let antiLive = liveSpectrum(frames: 1024, frequency: 937.5, antiphase: true)
        check(inPhaseLive == antiLive, "Live spectrum antiphase preserves channel power")
        let rightLive = liveSpectrum(frames: 1536, frequency: 12000, rightOnly: true)
        check(rightLive != nil && rightLive![16] > 0.9, "Live spectrum right-only stereo")
        let normalLive = liveSpectrum(frames: 1024, frequency: 937.5)
        let longerLive = liveSpectrum(frames: 1536, frequency: 937.5)
        check(normalLive == longerLive, "Live spectrum ignores incomplete trailing window")
        state.audioEngine.setEQBypassed(true)
        check(state.audioEngine.gateEQUnitBypassed, "EQ bypass includes unit preamp")
        state.audioEngine.setEQBypassed(false)
        check(!state.audioEngine.gateEQUnitBypassed, "EQ unit bypass restores")
        // Regression tests for defects reproduced in the original baseline.
        let negative = fixtures.appendingPathComponent("negative.wav")
        var negativeData = tone(1000, amplitude: 0.1); negativeData[1234] = -1
        try wave(negative, channels: [negativeData])
        let negativeResult = await AudioAnalyzer.analyze(path: negative.path)
        check(negativeResult?.isClipping == true, "Negative transient clipping detected")
        check(near(negativeResult?.peakLevel ?? -200, 0), "Negative transient absolute peak")
        let rightOnly = fixtures.appendingPathComponent("right-only.wav")
        try wave(rightOnly, channels: [[Float](repeating:0,count:48000), tone(1000)])
        let rightResult = await AudioAnalyzer.analyze(path: rightOnly.path)
        check(rightResult != nil && near(rightResult!.spectralCentroid, 1000, 1), "Right-only stereo spectrum")
        let rightWaveform = await AudioAnalyzer.computeWaveform(path: rightOnly.path)
        check(near(rightWaveform?.max() ?? 0, 1), "Right-only stereo waveform")
        let tail = fixtures.appendingPathComponent("tail.wav")
        var tailData = [Float](repeating:0,count:48001); tailData[48000] = 1
        try wave(tail, channels:[tailData])
        let tailWaveform = await AudioAnalyzer.computeWaveform(path:tail.path)
        check(tailWaveform?.last == 1, "Waveform final remainder impulse retained")
        let antiphase = fixtures.appendingPathComponent("antiphase.wav")
        let signal = tone(996.09375)
        try wave(antiphase, channels: [signal, signal.map { -$0 }])
        let antiResult = await AudioAnalyzer.analyze(path: antiphase.path)
        check(antiResult != nil && near(antiResult!.spectralCentroid, 996.09375, 1), "Antiphase stereo preserves energy")
        let stereo = fixtures.appendingPathComponent("stereo.wav")
        try wave(stereo, channels: [tone(93.75), tone(7992.1875)])
        let stereoResult = await AudioAnalyzer.analyze(path: stereo.path)
        check(stereoResult != nil && near(stereoResult!.bassEnergy, 0.5, 0.001) && near(stereoResult!.trebleEnergy, 0.5, 0.001), "Stereo spectral power balanced across channels")
        let nyquist = fixtures.appendingPathComponent("nyquist.wav")
        try wave(nyquist, channels: [(0..<48000).map { $0 % 2 == 0 ? 0.5 : -0.5 }])
        let nyquistResult = await AudioAnalyzer.analyze(path: nyquist.path)
        check(nyquistResult != nil && nyquistResult!.trebleEnergy > 0.999 && nyquistResult!.spectralCentroid > 23990, "Nyquist belongs to treble not DC")
        let tiny = fixtures.appendingPathComponent("tiny.wav")
        try wave(tiny, channels: [[0.25,-0.5]])
        check(await AudioAnalyzer.computeWaveform(path: tiny.path) == [0.5,1], "Sub-resolution waveform retains samples")
        check(await AudioAnalyzer.computeWaveform(path: tiny.path, resolution: 0) == nil, "Zero waveform resolution rejected")
        check(await AudioAnalyzer.computeWaveform(path: tiny.path, resolution: -1) == nil, "Negative waveform resolution rejected")
        let empty = fixtures.appendingPathComponent("empty.wav")
        try wave(empty, channels: [[]])
        check(await AudioAnalyzer.computeWaveform(path: empty.path) == nil, "Empty waveform omitted")
        check(await AudioAnalyzer.analyze(path: empty.path) == nil, "Empty analysis omitted")
        let chunked = fixtures.appendingPathComponent("chunked.wav")
        var chunkData = [Float](repeating: 0, count: 48000); chunkData[23999] = -1; chunkData[47999] = -0.5
        try wave(chunked, channels: [chunkData])
        check(await AudioAnalyzer.computeWaveform(path: chunked.path, resolution: 2) == [1,0.5], "Chunked waveform preserves bin boundaries")
        let cancelledAnalysis = Task { await AudioAnalyzer.analyze(path: stereo.path) }; cancelledAnalysis.cancel()
        check(await cancelledAnalysis.value == nil, "Cancelled analysis stops")
        let cancelledWaveform = Task { await AudioAnalyzer.computeWaveform(path: stereo.path) }; cancelledWaveform.cancel()
        check(await cancelledWaveform.value == nil, "Cancelled waveform stops")
        let overlapping = await FolderScanner.scan(folders: [scanDir.path, scanDir.appendingPathComponent("nested").path])
        check(overlapping.count == 2 && Set(overlapping.map(\.path)).count == 2, "Overlapping folders deduplicate paths")
        }
        print("SNAPSHOT \(String(data:try encoder.encode(snapshots),encoding:.utf8)!)")
        print("RESULT \(passed) passed; \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
