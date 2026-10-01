import AppKit
import SwiftUI

/// The debug window (⌥⌘I): the whole event log with filters, the app's live state, and each page's
/// reports with a JavaScript console. For the Mac's screen, next to the TV, not for the remote.
struct DebugWindow: View {
    static let windowID = "debug"

    @EnvironmentObject var model: AppModel
    @EnvironmentObject var diagnostics: Diagnostics
    @AppStorage("debugTab") private var tab = Tab.log

    enum Tab: String, CaseIterable, Identifiable {
        case log = "Log", state = "State", pages = "Pages"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            switch tab {
            case .log: DebugLogView()
            case .state: DebugStateView()
            case .pages: DebugPagesView()
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle("Overlay", systemImage: "rectangle.inset.topright.filled", isOn: $diagnostics.isVisible)
                    .help("Show the debug overlay on the TV (⇧⌘D)")
                Button("Remote", systemImage: "appletvremote.gen4") { model.simulator.toggle() }
                    .help("Show the on-screen remote (⌥⌘R)")
                Button("Copy Report", systemImage: "doc.on.clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.debugReport, forType: .string)
                }
                .help("Copy state, page reports and the log, for a bug report")
            }
        }
    }
}

// MARK: Log

private struct DebugLogView: View {
    @EnvironmentObject var diagnostics: Diagnostics
    @State private var query = ""
    @State private var hidden: Set<LogCategory> = []
    @AppStorage("debugLogMinLevel") private var minLevel = LogLevel.debug.rawValue
    @State private var follows = true

    private var shown: [LogEntry] {
        diagnostics.events.filter { e in
            e.level.rawValue >= minLevel && !hidden.contains(e.category)
                && (query.isEmpty || e.message.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        let entries = shown
        VStack(spacing: 0) {
            HStack {
                Menu {
                    ForEach(LogCategory.allCases, id: \.self) { c in
                        Toggle(c.rawValue, isOn: Binding(get: { !hidden.contains(c) },
                                                         set: { on in if on { hidden.remove(c) } else { hidden.insert(c) } }))
                    }
                    Divider()
                    Button("Show All") { hidden = [] }
                } label: {
                    Label(hidden.isEmpty ? "All categories" : "\(LogCategory.allCases.count - hidden.count) categories",
                          systemImage: "line.3.horizontal.decrease")
                }
                .fixedSize()
                Picker("Level", selection: $minLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { Text("\($0.label) and up").tag($0.rawValue) }
                }
                .labelsHidden()
                .fixedSize()
                TextField("Filter", text: $query).textFieldStyle(.roundedBorder)
                Toggle("Follow", isOn: $follows).toggleStyle(.checkbox)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entries.map(\.line).joined(separator: "\n"), forType: .string)
                }
                Button("Clear") { diagnostics.clear() }
            }
            .padding(8)
            Divider()
            ScrollViewReader { proxy in
                List(entries) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(e.time).foregroundStyle(.tertiary)
                        Text(e.category.rawValue).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                        Text(e.message).foregroundStyle(e.level >= .warning ? e.level.color : .primary)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .listRowSeparator(.hidden)
                    .id(e.id)
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 16)
                .onChange(of: entries.last?.id) { _, last in
                    if follows, let last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }
}

// MARK: State

private struct DebugStateView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // The parts of the state that aren't published (the web views' URLs) change without telling
        // anyone, so this redraws on a timer too.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Form {
                ForEach(model.debugState, id: \.0) { k, v in
                    LabeledContent(k) { Text(v).textSelection(.enabled).multilineTextAlignment(.trailing) }
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: Pages

private struct DebugPagesView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var diagnostics: Diagnostics
    @State private var selection: String?
    @State private var script = ""
    @State private var output: [(id: UUID, input: String, result: String)] = []

    private var ids: [String] { model.web.views.keys.sorted() }

    var body: some View {
        HSplitView {
            List(ids, id: \.self, selection: $selection) { id in
                VStack(alignment: .leading) {
                    Text(model.settings.services.first { $0.id == id }?.name ?? id)
                    if model.active?.id == id { Text("open").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .frame(minWidth: 140, idealWidth: 160, maxWidth: 220)
            if let id = selection ?? model.active?.id ?? ids.first {
                page(id)
            } else {
                Text("No pages loaded. Open an app first.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func page(_ id: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.web.views[id]?.url?.absoluteString ?? "").lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled).foregroundStyle(.secondary)
                Spacer()
                if let s = model.settings.services.first(where: { $0.id == id }) {
                    Button("Open") { model.open(s) }.disabled(model.active?.id == id)
                    Button("Reload") { model.web.reload(s) }
                }
            }
            .padding(8)
            Divider()
            Form {
                ForEach((diagnostics.reports[id] ?? [:]).sorted { $0.key < $1.key }, id: \.key) { k, v in
                    LabeledContent(k) { Text(v).textSelection(.enabled).multilineTextAlignment(.trailing) }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: .infinity)
            Divider()
            console(id)
        }
    }

    private func console(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(output, id: \.id) { entry in
                            Text("› " + entry.input).foregroundStyle(.secondary)
                            Text(entry.result).foregroundStyle(entry.result.hasPrefix("error:") ? .red : .primary)
                                .textSelection(.enabled)
                                .id(entry.id)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .onChange(of: output.last?.id) { _, last in if let last { proxy.scrollTo(last, anchor: .bottom) } }
            }
            .frame(height: 160)
            TextField("JavaScript, run in \(id)'s page (Return to run)", text: $script)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .onSubmit {
                    let js = script
                    guard !js.isEmpty else { return }
                    script = ""
                    Task {
                        let result = await model.web.evaluate(js, in: id)
                        output.append((UUID(), js, result))
                    }
                }
        }
    }
}
