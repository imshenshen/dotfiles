import AppKit
import XCTest
@testable import SpaceBar

final class RenderingTests: XCTestCase {
    func testAppKitTextRenderingAcrossSelectionFrames() throws {
        let surface = SpaceSurface(frame: NSRect(x: 0, y: 0, width: 800, height: 20))
        let space = Space(id: 1, index: 1, label: "🌈 Main", display: 1, focused: true, visible: true, fullscreen: false)
        let button = SpaceButton(space: space, pick: { _, _ in }, settings: {})
        button.frame = NSRect(x: 0, y: 0, width: 90, height: 20)
        button.surface = surface; surface.addSubview(button)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        // Exercise the actual NSString/CoreText path, including intermediate colors.
        for frame in 0..<3000 {
            autoreleasepool {
                let cg = NSGraphicsContext.current!.cgContext
                cg.saveGState()
                defer { cg.restoreGState() }
                if frame % 2 == 1 {
                    cg.translateBy(x: 0, y: 40)
                    cg.scaleBy(x: 1, y: -1)
                }
                surface.barAppearance.fontSize = [9.0, 11.0, 18.0, 24.0][(frame / 200) % 4]
                let height = surface.barAppearance.effectiveHeight - 6
                button.frame.size.height = height
                surface.frame.size.height = height
                let x = CGFloat(frame % 200) - 100.0
                surface.select(CGRect(x: x, y: 1, width: 90, height: height - 2), animated: false)
                surface.draw(surface.bounds)
                button.draw(button.bounds)
            }
        }
    }

    func testTextLayoutIsCachedWhileOnlySelectionColorChanges() throws {
        let surface = SpaceSurface(frame: NSRect(x: 0, y: 0, width: 800, height: 24))
        let space = Space(id: 1, index: 1, label: "🌈 Main", display: 1, focused: true, visible: true, fullscreen: false)
        let button = SpaceButton(space: space, pick: { _, _ in }, settings: {})
        button.frame = NSRect(x: 0, y: 0, width: 90, height: 20)
        button.surface = surface; surface.addSubview(button)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        for frame in 0..<1_000 {
            surface.select(CGRect(x: CGFloat(frame % 180) - 90, y: 1, width: 90, height: 18), animated: false)
            button.draw(button.bounds)
        }
        XCTAssertEqual(button.textLayoutBuildCount, 1)

        surface.barAppearance.fontSize = 18
        button.draw(button.bounds)
        XCTAssertEqual(button.textLayoutBuildCount, 2)
    }
}
