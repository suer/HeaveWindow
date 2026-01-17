import Foundation
import Yams

struct HotkeyConfig: Decodable {
    let modifiers: [String]
    let key: String

    static let `default` = HotkeyConfig(
        modifiers: ["option", "shift"],
        key: "space"
    )
}

struct AppConfig: Decodable {
    let hotkey: HotkeyConfig?
}

class Config {
    static let shared = Config()

    private let configPath: String
    private(set) var appConfig: AppConfig?

    var hotkeyConfig: HotkeyConfig {
        appConfig?.hotkey ?? HotkeyConfig.default
    }

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        configPath = "\(homeDir)/.config/heave-window/config.yml"
        reload()
    }

    func reload() {
        guard FileManager.default.fileExists(atPath: configPath),
              let yamlString = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            appConfig = nil
            return
        }

        do {
            appConfig = try YAMLDecoder().decode(AppConfig.self, from: yamlString)
        } catch {
            print("Failed to parse config: \(error)")
            appConfig = nil
        }
    }
}
