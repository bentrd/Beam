import AppKit
import QuartzCore

/// Captures only this recorder's actual window views, including the titlebar and its attached welcome sheet.
/// It does not read the screen, require Screen Recording permission, or capture other applications.
@MainActor
enum BeamDemoSnapshot {
    enum CaptureMode: String { case layer, view, combined }

    static func write(window: NSWindow, mode: CaptureMode, to url: URL) throws {
        guard let content = window.contentView else { throw BeamDemoFailure(description: "no window content") }
        let view = content.superview ?? content
        refresh(view)
        if let sheet = window.attachedSheet, let sheetContent = sheet.contentView { refresh(sheetContent.superview ?? sheetContent) }
        CATransaction.flush()
        let base = try bitmap(of: view)
        guard let combined = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: base.pixelsWide,
                                             pixelsHigh: base.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: combined) else {
            throw BeamDemoFailure(description: "could not allocate the recording bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        let scale = CGFloat(base.pixelsWide) / view.bounds.width
        graphics.cgContext.scaleBy(x: scale, y: scale)
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: view.bounds.size).fill()
        if mode != .layer { draw(base, in: NSRect(origin: .zero, size: view.bounds.size)) }
        if mode != .view {
            renderLayer(of: view, in: graphics.cgContext)
        }
        if let sheet = window.attachedSheet, let sheetContent = sheet.contentView {
            let sheetView = sheetContent.superview ?? sheetContent
            let sheetBitmap = try bitmap(of: sheetView)
            let origin = NSPoint(x: sheet.frame.minX - window.frame.minX, y: sheet.frame.minY - window.frame.minY)
            graphics.cgContext.saveGState()
            graphics.cgContext.translateBy(x: origin.x, y: origin.y)
            if mode != .layer { draw(sheetBitmap, in: NSRect(origin: .zero, size: sheetView.bounds.size)) }
            if mode != .view { renderLayer(of: sheetView, in: graphics.cgContext) }
            graphics.cgContext.restoreGState()
        }
        for settings in NSApp.windows where settings.isVisible && settings !== window && settings.title == "Beam Settings" {
            guard let settingsContent = settings.contentView else { continue }
            let settingsView = settingsContent.superview ?? settingsContent
            refresh(settingsView)
            let settingsBitmap = try bitmap(of: settingsView)
            graphics.cgContext.saveGState()
            graphics.cgContext.translateBy(x: settings.frame.minX - window.frame.minX,
                                          y: settings.frame.minY - window.frame.minY)
            if mode != .layer { draw(settingsBitmap, in: NSRect(origin: .zero, size: settingsView.bounds.size)) }
            if mode != .view { renderLayer(of: settingsView, in: graphics.cgContext) }
            graphics.cgContext.restoreGState()
        }
        graphics.flushGraphics()
        graphics.cgContext.flush()
        let opaque = try flattened(combined)
        guard let png = opaque.representation(using: .png, properties: [:]) else {
            throw BeamDemoFailure(description: "could not encode the recording frame")
        }
        try png.write(to: url, options: .atomic)
    }

    /// AppKit's theme-frame bitmap cache can hold its initial SwiftUI backing store. Flush the current child
    /// layers and composite their current presentation contents, including AppKit text and scroll views.
    private static func refresh(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        for child in view.subviews { refresh(child) }
        view.displayIfNeeded()
        view.layer?.displayIfNeeded()
    }

    /// Give rounded window corners an opaque paper backdrop before GIF/MP4 encoding discards their alpha.
    private static func flattened(_ bitmap: NSBitmapImageRep) throws -> NSBitmapImageRep {
        guard let flat = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide,
                                         pixelsHigh: bitmap.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: flat) else {
            throw BeamDemoFailure(description: "could not flatten the recording frame")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        let rectangle = NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        NSColor.windowBackgroundColor.setFill()
        rectangle.fill()
        draw(bitmap, in: rectangle)
        graphics.flushGraphics()
        return flat
    }

    private static func renderLayer(of view: NSView, in context: CGContext) {
        if let layer = view.layer {
            (layer.presentation() ?? layer).render(in: context)
        } else {
            for child in view.subviews where !child.isHidden {
                context.saveGState()
                let rectangle = view.convert(child.bounds, from: child)
                context.translateBy(x: rectangle.minX, y: rectangle.minY)
                renderLayer(of: child, in: context)
                context.restoreGState()
            }
        }
    }

    private static func bitmap(of view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw BeamDemoFailure(description: "could not cache the app view")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private static func draw(_ bitmap: NSBitmapImageRep, in rectangle: NSRect) {
        let image = NSImage(size: rectangle.size)
        image.addRepresentation(bitmap)
        image.draw(in: rectangle, from: .zero, operation: .sourceOver, fraction: 1)
    }
}
