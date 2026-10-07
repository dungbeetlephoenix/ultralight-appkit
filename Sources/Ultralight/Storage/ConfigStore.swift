import Foundation

enum ConfigStore {
    private static var configURL: URL {
        let dir = dataDirectory
        return dir.appendingPathComponent("config.json")
    }

    static var dataDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ultralight")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Config

    struct Config: Codable {
        var folders: [String] = []
        var theme: String = "dark"
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return config
    }

    static func save(_ config: Config) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}

extension ConfigStore.Config {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: JSONKey.self)
        folders = try values.read([String].self, "folders")
        theme = try values.read(String.self, "theme")
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: JSONKey.self)
        try values.write(folders, "folders")
        try values.write(theme, "theme")
    }
}
