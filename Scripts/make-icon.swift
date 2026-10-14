// Builds the app icon and the in-app logo from the square logo artwork.
// Usage: swift Scripts/make-icon.swift <logo.png> <Assets.xcassets path>
//
// The artwork is placed in the macOS icon shape: a rounded square inset 10%
// from the canvas with a soft shadow, so it sits correctly in the Dock.
import AppKit

let source = URL(filePath: CommandLine.arguments[1])
let assets = URL(filePath: CommandLine.arguments[2])
guard let logo = NSImage(contentsOf: source) else {
    fatalError("Can't read \(source.path)")
}

func bitmap(pixels: Int, draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    draw(CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func drawIcon(size: CGFloat) {
    let inset = size * 100 / 1024
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.shadowBlurRadius = size * 0.03
    shadow.set()
    NSColor.white.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    logo.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.black.withAlphaComponent(0.08).setStroke()
    shape.lineWidth = max(1, size / 512)
    shape.stroke()
}

// App icon
let iconSet = assets.appending(path: "AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try bitmap(pixels: points * scale, draw: drawIcon).write(to: iconSet.appending(path: name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let iconContents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: iconContents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appending(path: "Contents.json"))

// In-app logo: the artwork itself, square. Views round the corners.
let logoSet = assets.appending(path: "Logo.imageset")
try FileManager.default.createDirectory(at: logoSet, withIntermediateDirectories: true)
for (name, pixels) in [("logo.png", 128), ("logo@2x.png", 256), ("logo@3x.png", 384)] {
    try bitmap(pixels: pixels) { size in
        logo.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    }.write(to: logoSet.appending(path: name))
}
let logoContents: [String: Any] = [
    "images": [
        ["idiom": "universal", "scale": "1x", "filename": "logo.png"],
        ["idiom": "universal", "scale": "2x", "filename": "logo@2x.png"],
        ["idiom": "universal", "scale": "3x", "filename": "logo@3x.png"],
    ],
    "info": ["author": "xcode", "version": 1],
]
try JSONSerialization.data(withJSONObject: logoContents, options: [.prettyPrinted, .sortedKeys])
    .write(to: logoSet.appending(path: "Contents.json"))

print("Wrote \(images.count) icon images and the in-app logo")
