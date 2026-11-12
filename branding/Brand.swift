// Renders QuotaBar's brand assets into assets/. Run ./branding/render.sh.
// Compiled together with QuotaBar.swift, so screenshots use the app's real views.
import AppKit
import SwiftUI

enum Brand {
    static let ink = Color(red: 0.055, green: 0.063, blue: 0.078)       // #0E1014
    static let inkHigh = Color(red: 0.118, green: 0.133, blue: 0.161)   // #1E2229
    static let track = Color(red: 0.200, green: 0.220, blue: 0.255)     // #333841
    static let trackLight = Color(red: 0.870, green: 0.886, blue: 0.906) // #DEE2E7
    static let mint = Color.quotaMint                                   // #3DDC97
    static let mintDeep = Color(red: 0.122, green: 0.690, blue: 0.459)  // #1FB075
    static let paper = Color(red: 0.965, green: 0.969, blue: 0.961)     // #F6F7F5
}

/// The mark: a track, a fill (what's left) and a tick (where an even pace would be).
struct Mark: View {
    var fill: Double = 0.66
    var tick: Double = 0.5
    var track: Color = Brand.track
    var tickColor: Color = Brand.paper

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let th = h * 0.46, tw = max(h * 0.1, 1), gap = h * 0.07
            let x = w * tick
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule().fill(track).frame(width: w, height: th)
                    Capsule()
                        .fill(LinearGradient(colors: [Brand.mint, Brand.mintDeep], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(w * fill, th), height: th)
                }
                // Mask the bar into two segments so the gap shows whatever is behind the mark.
                .mask(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Rectangle().frame(width: x - tw / 2 - gap)
                        Rectangle().frame(width: w - x - tw / 2 - gap).offset(x: x + tw / 2 + gap)
                    }
                    .frame(width: w, height: h, alignment: .leading)
                }
                Capsule().fill(tickColor)
                    .frame(width: tw, height: h)
                    .offset(x: x - tw / 2)
            }
            .frame(width: w, height: h)
        }
    }
}

/// macOS app icon on Apple's 1024 grid: 824pt body, continuous corners.
struct AppIconArt: View {
    let size: CGFloat

    var body: some View {
        let body = size * 824 / 1024
        let radius = body * 0.2237
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Brand.inkHigh, Brand.ink], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.09), lineWidth: max(size / 400, 0.5))
                )
                .frame(width: body, height: body)
                .shadow(color: .black.opacity(size >= 64 ? 0.3 : 0), radius: size * 0.018, y: size * 0.01)
            VStack(spacing: body * 0.07) {
                Mark()
                    .frame(width: body * 0.68, height: body * 0.30)
                // Gauge graduations, so it reads as a meter rather than a slider.
                if size >= 64 {
                    HStack(spacing: 0) {
                        ForEach(0..<11) { i in
                            Capsule()
                                .fill(Brand.paper.opacity(i % 5 == 0 ? 0.34 : 0.16))
                                .frame(width: body * 0.012, height: body * (i % 5 == 0 ? 0.05 : 0.03))
                            if i < 10 { Spacer(minLength: 0) }
                        }
                    }
                    .frame(width: body * 0.68 - body * 0.138, height: body * 0.05, alignment: .top)
                }
            }
            .offset(y: size >= 64 ? body * 0.04 : 0)
        }
        .frame(width: size, height: size)
    }
}

struct Lockup: View {
    let dark: Bool
    var height: CGFloat = 80

    var body: some View {
        HStack(spacing: height * 0.3) {
            Mark(track: dark ? Brand.track : Brand.trackLight, tickColor: dark ? Brand.paper : Brand.ink)
                .frame(width: height * 1.55, height: height * 0.68)
            Text("QuotaBar")
                .font(.system(size: height * 0.74, weight: .bold, design: .rounded))
                .kerning(-height * 0.012)
                .foregroundStyle(dark ? Brand.paper : Brand.ink)
        }
        .padding(.horizontal, height * 0.12)
        .padding(.vertical, height * 0.08)
    }
}

// MARK: - Product shots (fictional numbers, real row views)

enum Demo {
    /// 5-hour window ahead of pace; weekly window comfortably on pace.
    static func limits(_ now: Date) -> [Limit] {
        [
            Limit(id: "5h", name: "5-hour", used: 64, resetsAt: now + 2 * 3600, length: 5 * 3600),
            Limit(id: "wk", name: "Weekly · all models", used: 38, resetsAt: now + 3.9 * 86400, length: 7 * 86400),
        ]
    }
}

struct MenuBarPill: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: MenuGlyph.image(fill: 0.62, tick: 0.56)).renderingMode(.template)
            Text(text).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.14)))
    }
}

struct PanelShot: View {
    let dark: Bool

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 14) {
            Text("Claude plan usage").font(.system(size: 13, weight: .semibold))
            ForEach(Demo.limits(now)) { LimitRow(limit: $0, now: now) }
            Divider()
            HStack {
                Text("Updated just now").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(dark ? Color(white: 0.16) : Color(white: 0.975))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(dark ? .white.opacity(0.1) : .black.opacity(0.08), lineWidth: 1)
        )
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

/// Screenshot for the README: menu bar pill above the open panel.
struct ReadmeShot: View {
    let dark: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuBarPill(text: "62% left")
                .foregroundStyle(dark ? .white : .black)
                .environment(\.colorScheme, dark ? .dark : .light)
                .colorMultiply(dark ? .white : .black)
            PanelShot(dark: dark)
                .shadow(color: .black.opacity(dark ? 0.5 : 0.18), radius: 24, y: 10)
        }
        .padding(32)
    }
}

/// GitHub social preview, 1280 x 640.
struct SocialCard: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Brand.inkHigh, Brand.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(alignment: .center, spacing: 72) {
                VStack(alignment: .leading, spacing: 0) {
                    Lockup(dark: true, height: 64)
                        .padding(.leading, -8)
                    Text("Will your Claude plan\nlast the week?")
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .kerning(-0.8)
                        .lineSpacing(2)
                        .foregroundStyle(Brand.paper)
                        .padding(.top, 44)
                    Text("Plan limits, pace and run-out time,\nin your Mac's menu bar.")
                        .font(.system(size: 24, weight: .regular))
                        .lineSpacing(4)
                        .foregroundStyle(Brand.paper.opacity(0.62))
                        .padding(.top, 18)
                    Text("brew install rorydotgg/tap/quotabar")
                        .font(.system(size: 19, weight: .medium, design: .monospaced))
                        .foregroundStyle(Brand.mint)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.09)))
                        .padding(.top, 40)
                }
                VStack(alignment: .trailing, spacing: 14) {
                    MenuBarPill(text: "62% left")
                        .scaleEffect(1.18, anchor: .trailing)
                    PanelShot(dark: true)
                        .scaleEffect(1.18, anchor: .topTrailing)
                        .frame(width: 354, height: 300, alignment: .topTrailing)
                        .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
                }
            }
            .padding(.horizontal, 80)
        }
        .frame(width: 1280, height: 640)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Export

@MainActor
func save(_ view: some View, _ path: String, scale: CGFloat = 1) {
    let r = ImageRenderer(content: view)
    r.scale = scale
    guard let cg = r.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    else { fatalError("render failed: \(path)") }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(cg.width)x\(cg.height))")
}

@main
struct RenderBrand {
    @MainActor
    static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets"
        let iconset = "\(out)/AppIcon.iconset"
        try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
        for pt in [16, 32, 128, 256, 512] {
            save(AppIconArt(size: CGFloat(pt)), "\(iconset)/icon_\(pt)x\(pt).png")
            save(AppIconArt(size: CGFloat(pt * 2)), "\(iconset)/icon_\(pt)x\(pt)@2x.png")
        }
        save(AppIconArt(size: 1024), "\(out)/icon-1024.png")
        save(Lockup(dark: true), "\(out)/logo-dark.png", scale: 2)
        save(Lockup(dark: false), "\(out)/logo-light.png", scale: 2)
        save(ReadmeShot(dark: true), "\(out)/screenshot-dark.png", scale: 2)
        save(ReadmeShot(dark: false), "\(out)/screenshot-light.png", scale: 2)
        save(SocialCard(), "\(out)/social-preview.png")
    }
}
