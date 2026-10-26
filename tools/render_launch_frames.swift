// Offline renderer for the launch screen and the app icon artwork.
//
// Compiles the app's own design-system and launch sources for macOS and draws
// them with ImageRenderer, so the output is exactly what the app draws.
// Usage: tools/render_assets.sh   (see that script for the compile line)
//
//   render_launch_frames frames <outputDir>   -> montage PNGs per device shape/theme
//   render_launch_frames icons  <outputDir>   -> 1024pt app icon PNGs

import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct DeviceShape {
    let name: String
    let size: CGSize
    let insets: EdgeInsets
}

let shapes: [DeviceShape] = [
    DeviceShape(name: "iphone-portrait", size: CGSize(width: 393, height: 852),
                insets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)),
    DeviceShape(name: "iphone-landscape", size: CGSize(width: 852, height: 393),
                insets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)),
    DeviceShape(name: "iphone-se-portrait", size: CGSize(width: 375, height: 667),
                insets: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0)),
    DeviceShape(name: "iphone-se-landscape", size: CGSize(width: 667, height: 375),
                insets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)),
    DeviceShape(name: "ipad-portrait", size: CGSize(width: 834, height: 1194),
                insets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)),
    DeviceShape(name: "ipad-landscape", size: CGSize(width: 1194, height: 834),
                insets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0)),
    DeviceShape(name: "narrow-split", size: CGSize(width: 320, height: 700),
                insets: EdgeInsets(top: 24, leading: 0, bottom: 0, trailing: 0))
]

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("cannot create \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(url.path)") }
}

@MainActor
func render<V: View>(_ view: V, scale: CGFloat) -> CGImage {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.cgImage else { fatalError("render failed") }
    return image
}

@MainActor
func montage(_ images: [CGImage], gap: Int) -> CGImage {
    let cellW = images.map(\.width).max() ?? 0
    let cellH = images.map(\.height).max() ?? 0
    let columns = max(1, min(images.count, 2600 / (cellW + gap)))
    let rows = (images.count + columns - 1) / columns
    let width = columns * cellW + gap * (columns - 1)
    let height = rows * cellH + gap * (rows - 1)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (index, image) in images.enumerated() {
        let col = index % columns
        let row = index / columns
        ctx.draw(image, in: CGRect(x: col * (cellW + gap),
                                   y: height - (row + 1) * cellH - row * gap,
                                   width: image.width, height: image.height))
    }
    return ctx.makeImage()!
}

@MainActor
func renderFrames(into dir: URL) {
    let times: [Double] = [0.0, 0.25, 0.5, 0.7, 0.85, 1.0, 1.15, 1.3, 1.7]
    for scheme in [ColorScheme.dark, ColorScheme.light] {
        for shape in shapes {
            let frames = times.map { t -> CGImage in
                let scene = LaunchScene(
                    timeline: LaunchTimeline(variant: .full),
                    t: t, size: shape.size, insets: shape.insets
                )
                .frame(width: shape.size.width, height: shape.size.height)
                .duovaTheme()
                .environment(\.colorScheme, scheme)
                return render(scene, scale: 1)
            }
            let name = "launch-\(shape.name)-\(scheme == .dark ? "dark" : "light").png"
            writePNG(montage(frames, gap: 8), to: dir.appendingPathComponent(name))
        }
    }
    // Quick, resume, and reduced-motion variants on a portrait phone.
    let phone = shapes[0]
    let variants: [(String, LaunchTimeline, [Double])] = [
        ("quick", LaunchTimeline(variant: .quick), [0.0, 0.15, 0.3, 0.5, 0.65, 0.85]),
        ("resume", LaunchTimeline(variant: .resume), [0.0, 0.1, 0.2, 0.35]),
        ("reduced", LaunchTimeline(variant: .full, reducesMotion: true), [0.0, 0.2, 0.4, 0.55])
    ]
    for (label, timeline, ts) in variants {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let frames = ts.map { t -> CGImage in
                let scene = LaunchScene(timeline: timeline, t: t, size: phone.size, insets: phone.insets)
                    .frame(width: phone.size.width, height: phone.size.height)
                    .duovaTheme()
                    .environment(\.colorScheme, scheme)
                return render(scene, scale: 1)
            }
            let name = "launch-\(label)-\(scheme == .dark ? "dark" : "light").png"
            writePNG(montage(frames, gap: 8), to: dir.appendingPathComponent(name))
        }
    }
}

/// App icons must not contain an alpha channel, so flatten onto an opaque bitmap.
func opaque(_ image: CGImage) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()!
}

@MainActor
func renderIcons(into dir: URL) {
    func icon(_ style: DuovaMarkStyle) -> CGImage {
        let view = DuovaMark(style: style, fullBleed: true)
            .frame(width: 1024, height: 1024)
            .environment(\.duovaTheme, style == .light ? .light : .dark)
        return opaque(render(view, scale: 1))
    }
    writePNG(icon(.light), to: dir.appendingPathComponent("AppIcon-Light.png"))
    writePNG(icon(.dark), to: dir.appendingPathComponent("AppIcon-Dark.png"))
    writePNG(icon(.mono), to: dir.appendingPathComponent("AppIcon-Tinted.png"))
}

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: render_launch_frames frames|icons <outputDir>")
    exit(2)
}
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
switch args[1] {
case "frames": MainActor.assumeIsolated { renderFrames(into: outDir) }
case "icons": MainActor.assumeIsolated { renderIcons(into: outDir) }
default: print("unknown mode \(args[1])"); exit(2)
}
