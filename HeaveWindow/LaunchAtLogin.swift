import ServiceManagement
import os

private let logger = Logger(subsystem: "com.heavewindow.HeaveWindow", category: "LaunchAtLogin")

@available(macOS 13.0, *)
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            logger.error("Failed to toggle launch at login: \(error)")
        }
    }
}
