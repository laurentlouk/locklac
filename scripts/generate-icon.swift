#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Generate a lockLac app icon: dark rounded-rect background with pixel art loc lac beef

// 16x16 pixel art: loc lac beef on a plate (same as lock screen)
// 0 = transparent, 1 = dark outline, 2 = beef brown, 3 = beef seared,
// 4 = plate cream, 5 = lettuce green, 6 = lime green
let locLacGrid: [[UInt8]] = [
    [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
    [0,0,0,1,1,4,4,4,4,4,4,1,1,0,0,0],
    [0,0,1,4,4,4,4,4,4,4,4,4,4,1,0,0],
    [0,1,4,4,5,5,5,5,5,5,5,5,4,4,1,0],
    [0,1,4,5,1,1,1,1,1,1,1,1,5,4,1,0],
    [1,4,5,1,2,2,1,3,3,1,2,2,1,5,4,1],
    [1,4,5,1,2,3,1,3,2,1,2,3,1,5,4,1],
    [1,4,4,1,1,1,1,1,1,1,1,1,1,4,4,1],
    [1,4,4,1,3,3,1,2,2,1,3,3,1,4,4,1],
    [1,4,5,1,3,2,1,2,3,1,3,2,1,5,4,1],
    [0,1,4,5,1,1,1,1,1,1,1,1,5,4,1,0],
    [0,1,4,4,5,5,5,5,5,5,5,5,4,4,1,0],
    [0,0,1,4,4,4,4,4,4,6,6,4,4,1,0,0],
    [0,0,0,1,4,4,4,4,6,6,6,4,1,0,0,0],
    [0,0,0,0,1,1,4,4,4,6,1,1,0,0,0,0],
    [0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0],
]

let locLacPalette: [UInt8: (r: CGFloat, g: CGFloat, b: CGFloat)] = [
    1: (0.15, 0.12, 0.10),  // dark outline
    2: (0.63, 0.32, 0.18),  // beef brown
    3: (0.42, 0.20, 0.06),  // beef seared
    4: (0.95, 0.93, 0.89),  // plate cream
    5: (0.36, 0.55, 0.24),  // lettuce green
    6: (0.64, 0.79, 0.23),  // lime green
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

    // Gradient: dark grey top to darker grey bottom
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1.0),
        CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0),
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

    // --- Draw pixel art loc lac ---
    ctx.saveGState()

    // Clip to rounded rect so pixels don't bleed outside
    ctx.addPath(bgPath)
    ctx.clip()

    let rows = locLacGrid.count
    let cols = locLacGrid[0].count
    let padding = s * 0.12
    let availableSize = s - padding * 2
    let pixelSize_ = availableSize / CGFloat(max(rows, cols))

    let gridW = CGFloat(cols) * pixelSize_
    let gridH = CGFloat(rows) * pixelSize_
    let originX = (s - gridW) / 2
    let originY = (s - gridH) / 2

    for row in 0..<rows {
        for col in 0..<cols {
            let value = locLacGrid[row][col]
            guard value != 0, let color = locLacPalette[value] else { continue }
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
