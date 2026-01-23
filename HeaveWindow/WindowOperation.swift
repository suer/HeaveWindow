import Carbon
import Cocoa

class WindowOperation {
    private var isInMoveMode = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentWindow: AXUIElement?
    private var highlightWindow: HighlightWindow?
    private var workspaceObserver: NSObjectProtocol?
    private var windowObserver: AXObserver?
    private let hotkey: ParsedHotkey

    init() {
        hotkey = ParsedHotkey.from(config: Config.shared.hotkeyConfig)
        setupEventTap()
        highlightWindow = HighlightWindow()
        setupWorkspaceObserver()
    }

    private func setupEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard
            let eventTap = CGEvent.tapCreate(
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
            )
        else {
            return
        }

        self.eventTap = eventTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<
        CGEvent
    >? {
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

            if let window = currentWindow {
                highlightWindow?.highlight(window: window)
                startObservingWindow(window)
            }
        } else {
            highlightWindow?.hide()
            stopObservingWindow()
            currentWindow = nil
        }
    }

    private func handleMoveMode(keyCode: Int64, event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let isShiftPressed = flags.contains(.maskShift)

        switch keyCode {
        case 53, 36:  // ESC, Enter
            toggleMoveMode()
            return nil
        case 126, 40:  // Up, k
            if isShiftPressed {
                resizeWindow(deltaWidth: 0, deltaHeight: -20)
            } else {
                moveWindow(deltaX: 0, deltaY: -20)
            }
            return nil
        case 125, 38:  // Down, j
            if isShiftPressed {
                resizeWindow(deltaWidth: 0, deltaHeight: 20)
            } else {
                moveWindow(deltaX: 0, deltaY: 20)
            }
            return nil
        case 123, 4:  // Left, h
            if isShiftPressed {
                resizeWindow(deltaWidth: -20, deltaHeight: 0)
            } else {
                moveWindow(deltaX: -20, deltaY: 0)
            }
            return nil
        case 124, 37:  // Right, l
            if isShiftPressed {
                resizeWindow(deltaWidth: 20, deltaHeight: 0)
            } else {
                moveWindow(deltaX: 20, deltaY: 0)
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
        let result = AXUIElementCopyAttributeValue(
            appRef, kAXFocusedWindowAttribute as CFString, &value)

        if result == .success {
            // swiftlint:disable:next force_cast
            return (value as! AXUIElement)
        }

        return nil
    }

    private func moveWindow(deltaX: CGFloat, deltaY: CGFloat) {
        guard let window = currentWindow else { return }

        var positionValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            window, kAXPositionAttribute as CFString, &positionValue)

        guard result == .success, let position = positionValue else { return }

        var point = CGPoint.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(position as! AXValue, .cgPoint, &point)

        point.x += deltaX
        point.y += deltaY

        if let newPosition = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, newPosition)
        }
    }

    private func resizeWindow(deltaWidth: CGFloat, deltaHeight: CGFloat) {
        guard let window = currentWindow else { return }

        var sizeValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)

        guard result == .success, let size = sizeValue else { return }

        var currentSize = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(size as! AXValue, .cgSize, &currentSize)

        currentSize.width = max(100, currentSize.width + deltaWidth)
        currentSize.height = max(100, currentSize.height + deltaHeight)

        if let newSize = AXValueCreate(.cgSize, &currentSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, newSize)
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
            isInMoveMode = false
            highlightWindow?.hide()
            stopObservingWindow()
            currentWindow = nil
        }
    }

    private func startObservingWindow(_ window: AXUIElement) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier

        var observer: AXObserver?
        let result = AXObserverCreate(
            pid,
            { (_, element, _, refcon) in
                guard let refcon = refcon else { return }
                let operation = Unmanaged<WindowOperation>.fromOpaque(refcon).takeUnretainedValue()
                DispatchQueue.main.async {
                    operation.highlightWindow?.highlight(window: element)
                }
            }, &observer)

        guard result == .success, let observer = observer else { return }

        self.windowObserver = observer

        AXObserverAddNotification(
            observer, window, kAXMovedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())
        AXObserverAddNotification(
            observer, window, kAXResizedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func stopObservingWindow() {
        guard let observer = windowObserver, let window = currentWindow else { return }

        AXObserverRemoveNotification(observer, window, kAXMovedNotification as CFString)
        AXObserverRemoveNotification(observer, window, kAXResizedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        windowObserver = nil
    }

    deinit {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        stopObservingWindow()
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
