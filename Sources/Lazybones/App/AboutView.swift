import AppKit
import SwiftUI

/// The About window: what this build is, what it's running on, and where to go next. Replaces
/// AppKit's standard panel, which can't show build details or anything you can copy.
struct AboutView: View {
    static let windowID = "about"

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.bottom, 20)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(AboutInfo.current.rows, id: \.label) { row in
                    GridRow {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(row.value)
                            .textSelection(.enabled)
                    }
                }
            }
            .font(.callout)
            .monospacedDigit()
            .padding(.horizontal, 24)

            HStack(spacing: 10) {
                Button(copied ? "Copied" : "Copy Info", action: copy)
                Link("Source Code", destination: AboutInfo.repository)
                Link("Report an Issue", destination: AboutInfo.issues)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 20)

            footer
                .padding(.top, 20)
                .padding(.bottom, 22)
                .padding(.horizontal, 28)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(SettingsWindowBehavior())
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .padding(.bottom, 6)
            Text("Lazybones")
                .font(.system(size: 26, weight: .semibold))
            Text("A tvOS-style launcher for streaming sites,\nfor a Mac plugged into a TV")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var footer: some View {
        Text("Ad blocking by uBlock Origin Lite (GPLv3). Service logos are trademarks of their owners, used only to identify each service.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AboutInfo.current.plainText, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

/// The build and system details the About window lists, also copied as text for bug reports.
struct AboutInfo {
    struct Row { let label: String; let value: String }

    static let repository = URL(string: "https://github.com/gergogyulai/lazybones")!
    static let issues = URL(string: "https://github.com/gergogyulai/lazybones/issues/new")!

    static let current = AboutInfo(info: Bundle.main.infoDictionary ?? [:],
                                   resources: Bundle.main.resourceURL)

    let rows: [Row]

    init(info: [String: Any], resources: URL?) {
        func string(_ key: String) -> String? { info[key] as? String }

        // `swift run` has no bundle, so no Info.plist: say so rather than show blanks.
        let version = string("CFBundleShortVersionString").map { short in
            string("CFBundleVersion").map { "\(short) (\($0))" } ?? short
        } ?? "Development build"

        var build = [string("LBGitCommit"), string("LBBuildConfiguration")].compactMap { $0 }
        if let date = string("LBBuildDate").flatMap({ try? Date($0, strategy: .iso8601) }) {
            build.append(date.formatted(date: .abbreviated, time: .shortened))
        }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        var rows = [Row(label: "Version", value: version)]
        if !build.isEmpty { rows.append(Row(label: "Build", value: build.joined(separator: " · "))) }
        if let sdk = string("LBBuildSDK") { rows.append(Row(label: "SDK", value: "macOS \(sdk)")) }
        rows.append(Row(label: "macOS", value: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"))
        rows.append(Row(label: "Safari", value: BrowserIdentity.safariVersion))
        rows.append(Row(label: "uBO Lite", value: Self.ubolVersion(in: resources) ?? "Not bundled"))
        self.rows = rows
    }

    var plainText: String {
        (["Lazybones"] + rows.map { "\($0.label): \($0.value)" }).joined(separator: "\n")
    }

    /// The bundled extension's own version, from its manifest.
    private static func ubolVersion(in resources: URL?) -> String? {
        guard let url = resources?.appendingPathComponent("uBOLite/manifest.json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return manifest["version"] as? String
    }
}

/// App menu > About Lazybones, opening the window above instead of AppKit's standard panel.
struct AboutButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Lazybones") { openWindow(id: AboutView.windowID) }
    }
}
