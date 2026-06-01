#!/usr/bin/swift
import CoreGraphics
import ImageIO
import Foundation

func makeIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Fill entire canvas black — macOS clips corners itself
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // White arrow centered, ~50% of canvas width
    let aw = s * 0.52   // arrow total width
    let ah = s * 0.28   // arrow total height
    let ax = (s - aw) / 2
    let ay = (s - ah) / 2
    let sw = ah * 0.20  // shaft half-height
    let hw = ah * 0.50  // head height

    let arrow = CGMutablePath()
    // left tip
    arrow.move(to:    CGPoint(x: ax,        y: ay + ah/2))
    arrow.addLine(to: CGPoint(x: ax + hw,   y: ay))
    arrow.addLine(to: CGPoint(x: ax + hw,   y: ay + ah/2 - sw))
    // shaft across
    arrow.addLine(to: CGPoint(x: ax + aw - hw, y: ay + ah/2 - sw))
    // right head
    arrow.addLine(to: CGPoint(x: ax + aw - hw, y: ay))
    arrow.addLine(to: CGPoint(x: ax + aw,   y: ay + ah/2))
    arrow.addLine(to: CGPoint(x: ax + aw - hw, y: ay + ah))
    arrow.addLine(to: CGPoint(x: ax + aw - hw, y: ay + ah/2 + sw))
    // shaft back
    arrow.addLine(to: CGPoint(x: ax + hw,   y: ay + ah/2 + sw))
    arrow.addLine(to: CGPoint(x: ax + hw,   y: ay + ah))
    arrow.closeSubpath()

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(arrow)
    ctx.fillPath()

    return ctx.makeImage()!
}

func savePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let iconsetDir = "/tmp/ghbdtn_iconset"
try? FileManager.default.removeItem(atPath: iconsetDir)
try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png",       16),  ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),  ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",     128), ("icon_128x128@2x.png",  256),
    ("icon_256x256.png",     256), ("icon_256x256@2x.png",  512),
    ("icon_512x512.png",     512), ("icon_512x512@2x.png",  1024),
]
for (name, size) in specs {
    savePNG(makeIcon(size: size), to: "\(iconsetDir)/\(name)")
    print("✓ \(name)")
}
