import Cocoa

class HighlightWindow: NSWindow {
    private let borderWidth: CGFloat = 4
    private let borderColor = NSColor.systemBlue.withAlphaComponent(0.8)
    
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        let contentView = BorderView(borderWidth: borderWidth, borderColor: borderColor)
        self.contentView = contentView
    }
    
    func highlight(window: AXUIElement) {
        guard let frame = getWindowFrame(window) else { return }
        
        self.setFrame(frame, display: true, animate: false)
        self.orderFrontRegardless()
    }
    
    func hide() {
        self.orderOut(nil)
    }
    
    private func getWindowFrame(_ window: AXUIElement) -> NSRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }
        
        var position = CGPoint.zero
        var size = CGSize.zero
        
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        if let screen = NSScreen.main {
            let screenHeight = screen.frame.height
            position.y = screenHeight - position.y - size.height
        }
        return NSRect(x: position.x, y: position.y, width: size.width, height: size.height)
    }
}

class BorderView: NSView {
    private let borderWidth: CGFloat
    private let borderColor: NSColor
    
    init(borderWidth: CGFloat, borderColor: NSColor) {
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let path = NSBezierPath(rect: bounds)
        path.lineWidth = borderWidth
        borderColor.setStroke()
        path.stroke()
        
        let innerRect = bounds.insetBy(dx: borderWidth, dy: borderWidth)
        let innerPath = NSBezierPath(rect: innerRect)
        NSColor.black.withAlphaComponent(0.1).setStroke()
        innerPath.lineWidth = 1
        innerPath.stroke()
    }
}
