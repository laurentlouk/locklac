#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Generate a lockLac app icon: dark rounded-rect background with pixel art onigiri

// 16x16 pixel art: onigiri rice ball (same as lock screen)
// 0 = transparent, 1 = dark outline, 2 = white rice, 3 = nori (seaweed), 4 = highlight
let onigiriGrid: [[UInt8]] = [
    [0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0],
    [0,0,0,0,1,1,2,2,2,2,1,1,0,0,0,0],
    [0,0,0,1,2,2,4,4,2,2,2,2,1,0,0,0],
    [0,0,1,2,2,4,4,2,2,2,2,2,2,1,0,0],
    [0,1,2,2,2,4,2,2,2,2,2,2,2,2,1,0],
    [0,1,2,2,2,2,2,2,2,2,2,2,2,2,1,0],
    [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1],
    [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1],
    [1,2,2,2,2,1,1,1,1,1,1,2,2,2,2,1],
    [1,2,2,2,1,3,3,3,3,3,3,1,2,2,2,1],
    [0,1,2,2,1,3,3,3,3,3,3,1,2,2,1,0],
    [0,1,2,2,1,3,3,3,3,3,3,1,2,2,1,0],
    [0,0,1,2,1,3,3,3,3,3,3,1,2,1,0,0],
    [0,0,0,1,1,3,3,3,3,3,3,1,1,0,0,0],
    [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
    [0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0],
]

let onigiriPalette: [UInt8: (r: CGFloat, g: CGFloat, b: CGFloat)] = [
    1: (0.15, 0.12, 0.10),  // dark outline
    2: (0.95, 0.93, 0.88),  // white rice
    3: (0.10, 0.20, 0.12),  // nori seaweed
    4: (1.00, 1.00, 0.98),  // highlight
]

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

    // --- Draw pixel art onigiri ---
    ctx.saveGState()

    // Clip to rounded rect so pixels don't bleed outside
    ctx.addPath(bgPath)
    ctx.clip()

    let rows = onigiriGrid.count
    let cols = onigiriGrid[0].count
    let padding = s * 0.12
    let availableSize = s - padding * 2
    let pixelSize_ = availableSize / CGFloat(max(rows, cols))

    let gridW = CGFloat(cols) * pixelSize_
    let gridH = CGFloat(rows) * pixelSize_
    let originX = (s - gridW) / 2
    let originY = (s - gridH) / 2

    for row in 0..<rows {
        for col in 0..<cols {
            let value = onigiriGrid[row][col]
            guard value != 0, let color = onigiriPalette[value] else { continue }
            ctx.setFillColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: 1.0))
            // Flip Y: row 0 is top of the grid, but CoreGraphics Y goes up
            let x = originX + CGFloat(col) * pixelSize_
            let y = originY + CGFloat(rows - 1 - row) * pixelSize_
            ctx.fill(CGRect(x: x, y: y, width: pixelSize_ + 0.5, height: pixelSize_ + 0.5))
        }
    }

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
