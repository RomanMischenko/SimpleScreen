import AppKit
import Carbon

private func cwLog(_ message: String) {
    let logURL = URL(fileURLWithPath: "/tmp/simplescreenlog.txt")
    let line = "\(Date()): [CropWindow] \(message)\n"
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

final class CropWindow: NSWindow {
    var cropCompletion: ((CGRect?) -> Void)?

    init(image: CGImage) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        cwLog("init — screen.frame=\(screen.frame) image=\(image.width)x\(image.height)")
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let cropView = CropView(frame: screen.frame, image: image)
        cropView.selectionCompletion = { [weak self] rect in
            self?.finish(rect)
        }
        contentView = cropView
        makeFirstResponder(cropView)
        cwLog("init — done")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        cwLog("deinit")
    }

    private func finish(_ rect: CGRect?) {
        cwLog("finish rect=\(String(describing: rect))")
        close()
        cropCompletion?(rect)
    }
}

private final class CropView: NSView {
    var selectionCompletion: ((CGRect?) -> Void)?

    private let nsImage: NSImage
    private var startPoint: NSPoint = .zero
    private var currentPoint: NSPoint = .zero
    private var isDragging = false

    init(frame: NSRect, image: CGImage) {
        nsImage = NSImage(cgImage: image, size: frame.size)
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        nsImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)

        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard isDragging else { return }

        let selectionRect = computeSelectionRect()
        let w = abs(currentPoint.x - startPoint.x)
        let h = abs(currentPoint.y - startPoint.y)

        // Redraw the image un-dimmed within the selection area.
        NSGraphicsContext.current?.saveGraphicsState()
        selectionRect.clip()
        nsImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.current?.restoreGraphicsState()

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
        let labelX = currentPoint.x + 8
        let labelY = currentPoint.y + 8
        let labelRect = NSRect(
            x: labelX,
            y: labelY,
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
        cwLog("mouseDown at \(startPoint)")
        setNeedsDisplay(bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        isDragging = false
        cwLog("mouseUp current=\(currentPoint) start=\(startPoint)")

        let dX = currentPoint.x - startPoint.x
        let dY = currentPoint.y - startPoint.y

        guard abs(dX) >= 10, abs(dY) >= 10 else {
            cwLog("mouseUp — selection too small (\(dX)x\(dY)), cancelling")
            selectionCompletion?(nil)
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Selection Too Small"
                alert.informativeText = "The selected area was too small — capture cancelled."
                alert.runModal()
            }
            return
        }

        let selectionRect = computeSelectionRect()
        cwLog("mouseUp — completing with selectionRect=\(selectionRect)")
        selectionCompletion?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            cwLog("keyDown — Escape, cancelling")
            selectionCompletion?(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
