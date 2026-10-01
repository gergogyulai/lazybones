import SwiftUI

/// What an app shows in place of a page it couldn't reach: what went wrong and a Try Again button,
/// which as the only thing on screen always has focus. Back leaves (see `AppModel.failureHandle`).
struct FailureScreen: View {
    let service: Service
    let failure: LoadFailure
    let size: CGSize
    /// Clicks so far, for pressing the button in.
    var presses = 0
    let retry: () -> Void

    var body: some View {
        let u = max(size.width / 1920, 0.5)
        ZStack {
            Color.black
            LinearGradient(colors: [(service.accent ?? service.color).opacity(0.35), .clear],
                           startPoint: .top, endPoint: .center)

            VStack(spacing: 0) {
                Image(systemName: failure.symbol)
                    .font(.system(size: 96 * u, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 44 * u)
                Text(failure.title(for: service))
                    .font(.system(size: 57 * u, weight: .bold))
                    .padding(.bottom, 16 * u)
                Text(failure.message(for: service))
                    .font(.system(size: 29 * u, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1000 * u)
                    .padding(.bottom, 64 * u)
                // Not a Button: that would take the Mac's keyboard focus and draw its own ring,
                // when focus here belongs to the remote, as everywhere else in the app.
                Text("Try Again")
                    .font(.system(size: 29 * u, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(minWidth: 380 * u, minHeight: 86 * u)
                    .glassSurface(Capsule(), tint: .white.opacity(0.92), interactive: true)
                    .scaleEffect(1.04)
                    .pressEffect(trigger: presses, active: true)
                    .shadow(color: .black.opacity(0.45), radius: 24 * u, y: 16 * u)
                    .contentShape(Capsule())
                    .onTapGesture(perform: retry)
                    .accessibilityAddTraits(.isButton)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 90 * u)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }
}
