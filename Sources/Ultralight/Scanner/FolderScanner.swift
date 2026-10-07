import Foundation
import AVFoundation

enum FolderScanner {
    private static let audioExtensions: [String] = [
        "mp3", "flac", "wav", "aac", "m4a", "ogg", "opus", "aiff", "aif", "wma", "alac", "wv"
    ]

    static func scan(folders: [String]) async -> [Track] {
        var tracks: [Track] = []
        for path in audioFiles(in: folders) {
            guard !Task.isCancelled else { return [] }
            guard let hash = FileHasher.hash(path: path) else { continue }
            let track = await extractMetadata(path: path, hash: hash)
            guard !Task.isCancelled else { return [] }
            guard track.duration.isFinite, track.duration > 0 else { continue }
            tracks.append(track)
        }
        return tracks
    }

    private static func audioFiles(in folders: [String]) -> [String] {
        let fm = FileManager.default
        let paths = NSMutableSet()

        for folder in folders {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: folder),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let value = enumerator.nextObject() {
                guard let url = value as? URL else { continue }
                guard !Task.isCancelled else { return [] }
                let ext = url.pathExtension.lowercased()
                guard audioExtensions.contains(ext) else { continue }
                var regular: AnyObject?
                do { try (url as NSURL).getResourceValue(&regular, forKey: .isRegularFileKey) }
                catch { continue }
                guard (regular as? NSNumber)?.boolValue == true else { continue }
                paths.add(url.resolvingSymlinksInPath().standardizedFileURL.path)
            }
        }

        return (paths.allObjects as NSArray).sortedArray(using: #selector(NSString.localizedStandardCompare(_:))) as! [String]
    }

    private static func extractMetadata(path: String, hash: String) async -> Track {
        var meta = Track(id: hash, path: path, title: "", artist: "", album: "", duration: 0)
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)

        await load(asset, keys: ["duration", "commonMetadata"])
        if asset.statusOfValue(forKey: "duration", error: nil) == .loaded {
            meta.duration = CMTimeGetSeconds(asset.duration)
        }
        if asset.statusOfValue(forKey: "commonMetadata", error: nil) == .loaded {
            for item in asset.commonMetadata {
                guard !Task.isCancelled else { break }
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle, .commonKeyArtist, .commonKeyAlbumName: break
                default: continue
                }
                await load(item, keys: ["stringValue"])
                guard item.statusOfValue(forKey: "stringValue", error: nil) == .loaded else { break }
                let value = item.stringValue ?? ""
                switch key {
                case .commonKeyTitle: meta.title = value
                case .commonKeyArtist: meta.artist = value
                default: meta.album = value
                }
            }
        }

        return meta
    }
    // Read cached values only after AVFoundation reports asynchronous loading done.
    private static func load(_ object: AVAsynchronousKeyValueLoading, keys: [String]) async {
        guard !Task.isCancelled else { return }
        await withCheckedContinuation { continuation in
            object.loadValuesAsynchronously(forKeys: keys) { continuation.resume() }
        }
    }

}
