import Foundation
import AVFoundation

enum FolderScanner {
    private static let audioExtensions: Set<String> = [
        "mp3", "flac", "wav", "aac", "m4a", "ogg", "opus", "aiff", "aif", "wma", "alac", "wv"
    ]

    static func scan(folders: [String]) async -> [Track] {
        var tracks: [Track] = []
        for url in audioFiles(in: folders) {
            guard !Task.isCancelled else { return [] }
            let path = url.path
            guard let hash = FileHasher.hash(path: path) else { continue }
            let metadata = await extractMetadata(url: url)
            guard metadata.duration.isFinite, metadata.duration > 0 else { continue }
            tracks.append(Track(id: hash, path: path, title: metadata.title,
                artist: metadata.artist, album: metadata.album, duration: metadata.duration))
        }
        return tracks
    }

    private static func audioFiles(in folders: [String]) -> [URL] {
        let fm = FileManager.default
        var paths = Set<URL>()

        for folder in folders {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: folder),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard !Task.isCancelled else { return [] }
                let ext = url.pathExtension.lowercased()
                guard audioExtensions.contains(ext) else { continue }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                paths.insert(url.resolvingSymlinksInPath().standardizedFileURL)
            }
        }

        return paths.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private struct Metadata {
        var title: String = ""
        var artist: String = ""
        var album: String = ""
        var duration: Double = 0
    }

    private static func extractMetadata(url: URL) async -> Metadata {
        var meta = Metadata()
        let asset = AVAsset(url: url)

        // Duration
        do {
            let duration = try await asset.load(.duration)
            meta.duration = CMTimeGetSeconds(duration)
        } catch {}

        // Common metadata (title, artist, album)
        do {
            let items = try await asset.load(.commonMetadata)
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    meta.title = try await item.load(.stringValue) ?? ""
                case .commonKeyArtist:
                    meta.artist = try await item.load(.stringValue) ?? ""
                case .commonKeyAlbumName:
                    meta.album = try await item.load(.stringValue) ?? ""
                default:
                    break
                }
            }
        } catch {}

        return meta
    }
}
