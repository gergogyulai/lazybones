import SwiftUI

/// The code an iPhone asks for while it pairs, shown as an Apple TV shows it: big, centred, over
/// whatever is on screen (`u` is points per point of a 1920-wide screen).
struct PhonePairingView: View {
    let name: String
    let pin: String
    var u: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 28 * u) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 54 * u, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                VStack(spacing: 10 * u) {
                    Text("Pair iPhone with \(name)")
                        .font(.system(size: 34 * u, weight: .semibold))
                    Text("Enter this code on your iPhone.")
                        .font(.system(size: 22 * u, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                }
                HStack(spacing: 18 * u) {
                    ForEach(Array(pin.enumerated()), id: \.offset) { _, digit in
                        Text(String(digit))
                            .font(.system(size: 64 * u, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 92 * u, height: 116 * u)
                            .glassSurface(RoundedRectangle(cornerRadius: 22 * u, style: .continuous))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 72 * u)
            .padding(.vertical, 56 * u)
            .glassSurface(RoundedRectangle(cornerRadius: 44 * u, style: .continuous))
        }
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }
}
