import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windowOperation: WindowOperation?
    var accessibilityCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuIcon")
            button.action = #selector(statusBarButtonClicked)
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu

        setupWithAccessibilityCheck()
    }

    @objc func statusBarButtonClicked() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func setupWithAccessibilityCheck() {
        if AXIsProcessTrusted() {
            enableWindowOperation()
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            startAccessibilityPolling()
        }
    }

    func startAccessibilityPolling() {
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            if AXIsProcessTrusted() {
                self?.enableWindowOperation()
                self?.stopAccessibilityPolling()
            }
        }
    }

    func stopAccessibilityPolling() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
    }

    func enableWindowOperation() {
        guard windowOperation == nil else { return }
        windowOperation = WindowOperation()
    }
}
