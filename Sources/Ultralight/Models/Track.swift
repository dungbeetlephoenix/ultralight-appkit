import Foundation

struct Track: Identifiable, Codable, Hashable {
    let id: String          // file content hash
    var path: String
    var title: String
    var artist: String
    var album: String
    var duration: Double    // seconds
    var analyzed: Bool = false

    var displayTitle: String {
        title.isEmpty ? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent : title
    }

    var durationString: String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}
