// Draws the app icon and writes Resources/AppIcon.icns.
//
//   swift Scripts/make-icon.swift
//
// Kept as code rather than a drawing so it can be tweaked and regenerated. The shape follows the
// macOS icon grid: an 824-point body with continuous corners, centered on a 1024 canvas, with the
// system's drop shadow in the margin.
import AppKit
import SwiftUI

struct Icon: View {
    var body: some View {
        let body = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            // A dark room.
            LinearGradient(colors: [Color(red: 0.13, green: 0.14, blue: 0.22), Color(red: 0.03, green: 0.03, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
            // Light thrown by the screen.
            Ellipse()
                .fill(Color(red: 0.42, green: 0.52, blue: 1).opacity(0.45))
                .frame(width: 700, height: 440)
                .blur(radius: 110)
                .offset(y: -90)
            // The TV, on its stand.
            Capsule()
                .fill(Color(white: 0.22))
                .frame(width: 150, height: 14)
                .offset(y: 26)
            let screen = RoundedRectangle(cornerRadius: 30, style: .continuous)
            screen
                .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.74, blue: 1), Color(red: 0.36, green: 0.34, blue: 0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                // A sheen across the glass.
                .overlay(screen.fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.35), location: 0),
                    .init(color: .white.opacity(0.08), location: 0.45),
                    .init(color: .clear, location: 0.46),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(screen.strokeBorder(.white.opacity(0.35), lineWidth: 4))
                .frame(width: 540, height: 310)
                .shadow(color: Color(red: 0.4, green: 0.5, blue: 1).opacity(0.8), radius: 60)
                .offset(y: -150)
            // And the couch in front of it.
            Image(systemName: "sofa.fill")
                .font(.system(size: 290, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
                .offset(y: 190)
        }
        .frame(width: 824, height: 824)
        .clipShape(body)
        .overlay(body.strokeBorder(.white.opacity(0.14), lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 10)
        .frame(width: 1024, height: 1024)
    }
}

func png(_ image: CGImage, size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let master = renderer.cgImage else { fatalError("couldn't render the icon") }

    let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        try! png(master, size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
        try! png(master, size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }

    let out = root.appendingPathComponent("Resources/AppIcon.icns")
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.path]
    try! iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
    print("wrote \(out.path)")
}
