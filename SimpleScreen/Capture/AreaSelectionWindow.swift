import AppKit
import Carbon

private func aswLog(_ message: String) {
    let logURL = URL(fileURLWithPath: "/tmp/simplescreenlog.txt")
    let line = "\(Date()): [AreaSelectionWindow] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logURL.path),
       let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: logURL)
    }
}

final class AreaSelectionWindow: NSPanel {
    var completion: ((CGRect?) -> Void)?

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        aswLog("init — screen.frame=\(screen.frame)")
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Prevent AppKit's extra release in close() (isReleasedWhenClosed=true by default
        // causes RC to hit 0 before our deferred nil-out runs, making a dangling pointer).
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false

        let selectionView = SelectionView(frame: screen.frame)
        contentView = selectionView
        makeFirstResponder(selectionView)
        aswLog("init — done, retainCount path OK")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        aswLog("deinit")
    }

    // Borderless windows don't become key by default; override so keyboard events (Escape) work.
    override var canBecomeKey: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        NSCursor.crosshair.push()
    }

    func cancel() {
        aswLog("cancel")
        NSCursor.pop()
        close()
        completion?(nil)
    }

    fileprivate func completeSelection(_ rect: CGRect) {
        aswLog("completeSelection rect=\(rect)")
        NSCursor.pop()
        close()
        completion?(rect)
    }
}

private final class SelectionView: NSView {
    private var startPoint: NSPoint = .zero
    private var currentPoint: NSPoint = .zero
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard isDragging else { return }

        let selectionRect = computeSelectionRect()
        let w = abs(currentPoint.x - startPoint.x)
        let h = abs(currentPoint.y - startPoint.y)

        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3).setFill()
        selectionRect.fill()

        NSColor.white.setStroke()
        let borderPath = NSBezierPath(rect: selectionRect)
        borderPath.lineWidth = 1
        borderPath.stroke()

        let labelText = "\(Int(w)) × \(Int(h))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 11, weight: .medium)
        ]
        let attrStr = NSAttributedString(string: labelText, attributes: attrs)
        let labelSize = attrStr.size()
        let padding: CGFloat = 4
        let labelRect = NSRect(
            x: currentPoint.x + 8,
            y: currentPoint.y + 8,
            width: labelSize.width + padding * 2,
            height: labelSize.height + padding * 2
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 3, yRadius: 3).fill()
        attrStr.draw(at: NSPoint(x: labelRect.origin.x + padding, y: labelRect.origin.y + padding))
    }

    private func computeSelectionRect() -> NSRect {
        NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isDragging = true
        aswLog("mouseDown at \(startPoint)")
        setNeedsDisplay(bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        isDragging = false
        aswLog("mouseUp current=\(currentPoint) start=\(startPoint)")

        let dX = currentPoint.x - startPoint.x
        let dY = currentPoint.y - startPoint.y

        guard abs(dX) >= 10, abs(dY) >= 10 else {
            aswLog("mouseUp — selection too small (\(dX)x\(dY)), cancelling")
            (window as? AreaSelectionWindow)?.cancel()
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Selection Too Small"
                alert.informativeText = "The selected area was too small — capture cancelled."
                alert.runModal()
            }
            return
        }

        let selectionRect = computeSelectionRect()
        guard let nsWindow = self.window else {
            aswLog("mouseUp — window is nil, cannot complete")
            return
        }
        let screenRect = nsWindow.convertToScreen(convert(selectionRect, to: nil))
        aswLog("mouseUp — completing with screenRect=\(screenRect)")
        (nsWindow as? AreaSelectionWindow)?.completeSelection(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            aswLog("keyDown — Escape, cancelling")
            (window as? AreaSelectionWindow)?.cancel()
        } else {
            super.keyDown(with: event)
        }
    }
}
