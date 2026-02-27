import Foundation

enum EQStore {
    private static var fileURL: URL {
        ConfigStore.dataDirectory.appendingPathComponent("eq-profiles.json")
    }

    private static var cache: [String: EQProfile] = {
        guard let data = try? Data(contentsOf: fileURL),
              let profiles = try? JSONDecoder().decode([String: EQProfile].self, from: data) else {
            return [:]
        }
        return profiles
    }()

    static func profile(for hash: String) -> EQProfile? {
        cache[hash]
    }

    static func save(profile: EQProfile, for hash: String) {
        cache[hash] = profile
        persist()
    }

    static func remove(for hash: String) {
        cache.removeValue(forKey: hash)
        persist()
    }

    private static func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
