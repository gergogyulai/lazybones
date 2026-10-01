import SwiftUI
import WebKit

/// A service's page on screen: growing out of its icon when it opens and shrinking back into it
/// when you go Home, like an app on tvOS. A page that is playing on behind the Home Screen stays
/// mounted here at full size, out of sight.
struct ServiceLayer: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let service: Service
    let webView: WKWebView

    var body: some View {
        let presented = model.presented?.id == service.id
        let progress: CGFloat = presented ? (model.zoomed ? 1 : 0) : 1

        GeometryReader { geo in
            let window = geo.frame(in: .global)
            let icon = model.iconRect(of: service, in: window)

            ZStack {
                WebContainer(webView: webView, takesFocus: model.active?.id == service.id)
                if let failure = model.failures[service.id] {
                    FailureScreen(service: service, failure: failure, size: geo.size, presses: model.presses) {
                        model.retry(service)
                    }
                        .transition(.opacity)
                }
                if model.loading.contains(service.id) {
                    LaunchScreen(service: service, size: geo.size).transition(.opacity)
                }
            }
            .animation(Motion.crossfade, value: model.loading.contains(service.id))
            .animation(Motion.crossfade, value: model.failures[service.id])
            .modifier(ZoomToIcon(progress: progress, icon: icon.rect, corner: icon.corner, size: geo.size,
                                  fadeOnly: reduceMotion))
        }
        .ignoresSafeArea()
        .opacity(presented ? 1 : 0)
        .allowsHitTesting(presented)
    }
}

/// What a service shows while its page loads for the first time: its icon, at full size, so the
/// zoom out of the icon is seamless. A page that's slow to arrive gets a spinner, so it's clear
/// something is still happening.
private struct LaunchScreen: View {
    let service: Service
    let size: CGSize
    @State private var slow = false

    var body: some View {
        IconFace(service: service, height: size.height, unit: size.height / 190)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottom) {
                if slow {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(.white)
                        .scaleEffect(max(size.width / 1920, 0.5) * 1.4)
                        .padding(.bottom, size.height * 0.14)
                        .transition(.opacity)
                }
            }
            .environment(\.colorScheme, .dark)
            .task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(Motion.crossfade) { slow = true }
            }
    }
}

/// Shows full-size content as if it were at `progress` between the icon's rectangle (0) and the
/// whole window (1). The content is scaled rather than resized, so the page never reflows mid-way.
/// At 1 it is the content itself, at full size, clipped to a rectangle that is the whole window.
/// With `fadeOnly` (Reduce Motion) it stays full size and only fades.
struct ZoomToIcon: ViewModifier, Animatable {
    var progress: CGFloat
    let icon: CGRect
    let corner: CGFloat
    let size: CGSize
    var fadeOnly = false

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let full = CGRect(origin: .zero, size: size)
        let r = fadeOnly ? full : icon.lerp(to: full, progress)
        // Cover the rectangle, like an app image being cropped to a tile.
        let scale = max(r.width / max(size.width, 1), r.height / max(size.height, 1))

        content
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .frame(width: r.width, height: r.height)
            .clipShape(RoundedRectangle(cornerRadius: fadeOnly ? 0 : corner * (1 - progress), style: .continuous))
            .position(x: r.midX, y: r.midY)
            // Fade in over the icon, so the two trade places instead of one popping over the other.
            .opacity(fadeOnly ? progress : min(1, progress / 0.12))
    }
}

extension CGRect {
    func lerp(to other: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: minX + (other.minX - minX) * t, y: minY + (other.minY - minY) * t,
               width: width + (other.width - width) * t, height: height + (other.height - height) * t)
    }
}

extension AppModel {
    /// Where a service's icon is, in the coordinates of a view whose frame in the window is `window`,
    /// and its corner radius. An app that isn't on the Home Screen grows from the middle instead.
    func iconRect(of s: Service, in window: CGRect) -> (rect: CGRect, corner: CGFloat) {
        guard let i = visible.firstIndex(where: { $0.id == s.id }), launcherFrame.width > 0 else {
            let w = window.width * 0.16, h = w * 0.6
            return (CGRect(x: (window.width - w) / 2, y: (window.height - h) / 2, width: w, height: h), w * 0.055)
        }
        let layout = LauncherLayout(size: launcherFrame.size, columns: columns, shelf: settings.showShelf,
                                    count: visible.count, selected: focus.index, appFocused: !focus.onBar)
        let frame = layout.frame(of: i)
        return (frame.offsetBy(dx: launcherFrame.minX - window.minX, dy: launcherFrame.minY - window.minY),
                layout.corner(of: i))
    }
}
