#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Generate a lockLac app icon: dark rounded-rect background with a white lock shield drawn via Core Graphics

func renderIcon(pixelSize: Int) -> NSImage {
    let s = CGFloat(pixelSize)
    let image = NSImage(size: NSSize(width: s, height: s))

    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    // --- Dark rounded-rect background ---
    let cornerRadius = s * 0.22
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Gradient: dark navy top to darker bottom
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.12, green: 0.12, blue: 0.20, alpha: 1.0),
        CGColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1.0),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: s/2, y: s),
                               end: CGPoint(x: s/2, y: 0),
                               options: [])
    }

    // Subtle border
    ctx.resetClip()
    let insetRect = rect.insetBy(dx: s * 0.005, dy: s * 0.005)
    let borderPath = CGPath(roundedRect: insetRect, cornerWidth: cornerRadius - s*0.005, cornerHeight: cornerRadius - s*0.005, transform: nil)
    ctx.addPath(borderPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.1))
    ctx.setLineWidth(s * 0.008)
    ctx.strokePath()

    // --- Draw shield + lock shape ---
    ctx.saveGState()

    // Center the drawing
    let iconScale = s * 0.0045
    let iconW = 100 * iconScale  // roughly 100 units wide
    let iconH = 130 * iconScale  // roughly 130 units tall
    let offsetX = (s - iconW) / 2
    let offsetY = (s - iconH) / 2 - s * 0.02

    ctx.translateBy(x: offsetX, y: offsetY)
    ctx.scaleBy(x: iconScale, y: iconScale)

    // Shield outline (pointed at bottom)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    let shield = CGMutablePath()
    shield.move(to: CGPoint(x: 50, y: 130))      // top center
    shield.addCurve(to: CGPoint(x: 5, y: 100),    // top-left
                    control1: CGPoint(x: 25, y: 128),
                    control2: CGPoint(x: 5, y: 115))
    shield.addLine(to: CGPoint(x: 5, y: 50))      // left side
    shield.addCurve(to: CGPoint(x: 50, y: 0),      // bottom point
                    control1: CGPoint(x: 5, y: 20),
                    control2: CGPoint(x: 30, y: 5))
    shield.addCurve(to: CGPoint(x: 95, y: 50),     // right side
                    control1: CGPoint(x: 70, y: 5),
                    control2: CGPoint(x: 95, y: 20))
    shield.addLine(to: CGPoint(x: 95, y: 100))     // right top
    shield.addCurve(to: CGPoint(x: 50, y: 130),    // back to top center
                    control1: CGPoint(x: 95, y: 115),
                    control2: CGPoint(x: 75, y: 128))
    shield.closeSubpath()
    ctx.addPath(shield)
    ctx.fillPath()

    // Lock body (dark rectangle on the shield)
    let lockBodyColor = CGColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 1.0)
    ctx.setFillColor(lockBodyColor)
    let bodyW: CGFloat = 40
    let bodyH: CGFloat = 30
    let bodyX: CGFloat = 50 - bodyW/2
    let bodyY: CGFloat = 40
    let bodyPath = CGPath(roundedRect: CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
                          cornerWidth: 4, cornerHeight: 4, transform: nil)
    ctx.addPath(bodyPath)
    ctx.fillPath()

    // Lock shackle (dark arc above the body)
    ctx.setStrokeColor(lockBodyColor)
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    let shackleCenter = CGPoint(x: 50, y: bodyY + bodyH)
    let shackleRadius: CGFloat = 14
    ctx.addArc(center: shackleCenter, radius: shackleRadius,
               startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.strokePath()

    // Keyhole (small white circle + triangle)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    let keyholeCenter = CGPoint(x: 50, y: 55)
    ctx.addArc(center: keyholeCenter, radius: 4, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.fillPath()

    // Keyhole slot
    let slot = CGMutablePath()
    slot.move(to: CGPoint(x: 48, y: 54))
    slot.addLine(to: CGPoint(x: 52, y: 54))
    slot.addLine(to: CGPoint(x: 51, y: 44))
    slot.addLine(to: CGPoint(x: 49, y: 44))
    slot.closeSubpath()
    ctx.addPath(slot)
    ctx.fillPath()

    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Error: could not create PNG for \(path)")
        return
    }
    try! pngData.write(to: URL(fileURLWithPath: path))
}

// Icon sizes required for .iconset
let sizes: [(name: String, size: Int, scale: Int)] = [
    ("icon_16x16",       16, 1),
    ("icon_16x16@2x",    16, 2),
    ("icon_32x32",       32, 1),
    ("icon_32x32@2x",    32, 2),
    ("icon_128x128",    128, 1),
    ("icon_128x128@2x", 128, 2),
    ("icon_256x256",    256, 1),
    ("icon_256x256@2x", 256, 2),
    ("icon_512x512",    512, 1),
    ("icon_512x512@2x", 512, 2),
]

let iconsetDir = "AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try! fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for entry in sizes {
    let px = entry.size * entry.scale
    let image = renderIcon(pixelSize: px)
    let path = "\(iconsetDir)/\(entry.name).png"
    savePNG(image, to: path)
    print("Generated \(path) (\(px)x\(px))")
}

print("\nDone! Run: iconutil -c icns AppIcon.iconset -o AppIcon.icns")
