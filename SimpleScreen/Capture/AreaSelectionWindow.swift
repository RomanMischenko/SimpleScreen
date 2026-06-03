import AppKit
import Carbon
import os

private let log = Logger(subsystem: "com.simplescreenapp.SimpleScreen", category: "areaSelect")

final class CropWindow: NSWindow {
    var cropCompletion: ((CGRect?) -> Void)?

    init(image: CGImage, onSelectionTooSmall: (() -> Void)? = nil) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        log.debug("init — screen.frame=\(NSStringFromRect(screen.frame), privacy: .public) image=\(image.width)x\(image.height)")
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
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
        cropView.tooSmallHandler = onSelectionTooSmall
        contentView = cropView
        makeFirstResponder(cropView)
        log.debug("init — done")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    deinit {
        log.debug("deinit")
    }

    private func finish(_ rect: CGRect?) {
        log.debug("finish rect=\(String(describing: rect), privacy: .public)")
        close()
        cropCompletion?(rect)
    }
}

private final class CropView: NSView {
    var selectionCompletion: ((CGRect?) -> Void)?
    var tooSmallHandler: (() -> Void)?

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
        log.debug("mouseDown at \(NSStringFromPoint(self.startPoint), privacy: .public)")
        setNeedsDisplay(bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        isDragging = false
        log.debug("mouseUp current=\(NSStringFromPoint(self.currentPoint), privacy: .public) start=\(NSStringFromPoint(self.startPoint), privacy: .public)")

        let dX = currentPoint.x - startPoint.x
        let dY = currentPoint.y - startPoint.y

        guard abs(dX) >= 10, abs(dY) >= 10 else {
            log.info("mouseUp — selection too small (\(dX)x\(dY)), cancelling")
            selectionCompletion?(nil)
            tooSmallHandler?()
            return
        }

        let selectionRect = computeSelectionRect()
        log.debug("mouseUp — completing with selectionRect=\(NSStringFromRect(selectionRect), privacy: .public)")
        selectionCompletion?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            log.debug("keyDown — Escape, cancelling")
            selectionCompletion?(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
