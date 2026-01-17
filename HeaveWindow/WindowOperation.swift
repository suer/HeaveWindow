import Cocoa
import Carbon

class WindowOperation {
    private var isInMoveMode = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentWindow: AXUIElement?
    private var highlightWindow: HighlightWindow?
    private var workspaceObserver: NSObjectProtocol?
    private let hotkey: ParsedHotkey

    init() {
        hotkey = ParsedHotkey.from(config: Config.shared.hotkeyConfig)
        setupEventTap()
        highlightWindow = HighlightWindow()
        setupWorkspaceObserver()
    }

    private func setupEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let mover = Unmanaged<WindowOperation>.fromOpaque(refcon).takeUnretainedValue()
                return mover.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        self.eventTap = eventTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if keyCode == hotkey.keyCode && flags.contains(hotkey.modifierFlags) {
            toggleMoveMode()
            return nil
        }

        if isInMoveMode {
            return handleMoveMode(keyCode: keyCode, event: event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func toggleMoveMode() {
        isInMoveMode.toggle()

        if isInMoveMode {
            currentWindow = getActiveWindow()
            NSSound.beep()

            if let window = currentWindow {
                highlightWindow?.highlight(window: window)
            }
        } else {
            highlightWindow?.hide()
            currentWindow = nil
        }
    }

    private func handleMoveMode(keyCode: Int64, event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let isShiftPressed = flags.contains(.maskShift)

        switch keyCode {
        case 53, 36: // ESC, Enter
            toggleMoveMode()
            return nil
        case 126, 40: // Up, k
            if isShiftPressed {
                resizeWindow(dw: 0, dh: -20)
            } else {
                moveWindow(dx: 0, dy: -20)
            }
            return nil
        case 125, 38: // Down, j
            if isShiftPressed {
                resizeWindow(dw: 0, dh: 20)
            } else {
                moveWindow(dx: 0, dy: 20)
            }
            return nil
        case 123, 4: // Left, h
            if isShiftPressed {
                resizeWindow(dw: -20, dh: 0)
            } else {
                moveWindow(dx: -20, dy: 0)
            }
            return nil
        case 124, 37: // Right, l
            if isShiftPressed {
                resizeWindow(dw: 20, dh: 0)
            } else {
                moveWindow(dx: 20, dy: 0)
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func getActiveWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appRef = AXUIElementCreateApplication(app.processIdentifier)

        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &value)

        if result == .success, let window = value as! AXUIElement? {
            return window
        }

        return nil
    }

    private func moveWindow(dx: CGFloat, dy: CGFloat) {
        guard let window = currentWindow else { return }

        var positionValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)

        guard result == .success, let position = positionValue else { return }

        var point = CGPoint.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)

        point.x += dx
        point.y += dy

        if let newPosition = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, newPosition)
            highlightWindow?.highlight(window: window)
        }
    }

    private func resizeWindow(dw: CGFloat, dh: CGFloat) {
        guard let window = currentWindow else { return }

        var sizeValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)

        guard result == .success, let size = sizeValue else { return }

        var currentSize = CGSize.zero
        AXValueGetValue(size as! AXValue, .cgSize, &currentSize)

        currentSize.width = max(100, currentSize.width + dw)
        currentSize.height = max(100, currentSize.height + dh)

        if let newSize = AXValueCreate(.cgSize, &currentSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, newSize)
            highlightWindow?.highlight(window: window)
        }
    }

    private func setupWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppSwitch()
        }
    }

    private func handleAppSwitch() {
        if isInMoveMode {
            print("App switched, exiting move mode")
            isInMoveMode = false
            highlightWindow?.hide()
            currentWindow = nil
        }
    }

    deinit {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
