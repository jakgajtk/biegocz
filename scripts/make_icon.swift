// Draws the 1024×1024 app icon: a white running figure on a navy gradient.
// Run with: swift scripts/make_icon.swift
import AppKit

let size = 1024.0
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appending(path: "Biegocz/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Navy diagonal gradient, matching BrandNavy → BrandNavyDeep.
let gradient = NSGradient(
    starting: NSColor(srgbRed: 0.16, green: 0.27, blue: 0.62, alpha: 1),
    ending: NSColor(srgbRed: 0.04, green: 0.09, blue: 0.22, alpha: 1)
)!
gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -50)

// The figure.
let configuration = NSImage.SymbolConfiguration(pointSize: 560, weight: .bold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "figure.run", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration) {
    let symbolSize = symbol.size
    let rect = NSRect(
        x: (size - symbolSize.width) / 2 + 10,
        y: (size - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )
    symbol.draw(in: rect)
}

image.unlockFocus()

// Write an opaque 1024×1024 PNG (app icons must not have transparency).
let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try! bitmap.representation(using: .png, properties: [:])!.write(to: output)
print("Wrote \(output.path)")
