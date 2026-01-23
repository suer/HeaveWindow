import Foundation
import Yams
import os

private let logger = Logger(subsystem: "com.heavewindow.HeaveWindow", category: "Config")

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

    let configPath: String
    private(set) var appConfig: AppConfig?

    static let defaultConfigContent = """
        hotkey:
          modifiers:
            - option
            - shift
          key: space
        """

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
            let yamlString = try? String(contentsOfFile: configPath, encoding: .utf8)
        else {
            appConfig = nil
            return
        }

        do {
            appConfig = try YAMLDecoder().decode(AppConfig.self, from: yamlString)
            logger.error("config: \(yamlString)")
        } catch {
            logger.error("Failed to parse config: \(error)")
            appConfig = nil
        }
    }

    func createDefaultConfigIfNeeded() -> Bool {
        if FileManager.default.fileExists(atPath: configPath) {
            return true
        }

        let configDir = (configPath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: configDir, withIntermediateDirectories: true, attributes: nil)
            try Config.defaultConfigContent.write(
                toFile: configPath, atomically: true, encoding: .utf8)
            reload()
            return true
        } catch {
            logger.error("Failed to create default config: \(error)")
            return false
        }
    }
}
