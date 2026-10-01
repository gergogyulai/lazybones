import AppKit
import SwiftUI

/// Edits one app in a sheet. Changes are made to a copy and take effect on Done (or Add App), so
/// an app isn't reloaded for every letter typed into its address, and Cancel leaves it as it was.
struct ServiceEditor: View {
    let isNew: Bool
    let save: (Service) -> Void
    /// Removes the app; nil for built-in apps, which can only be hidden, and for one not yet added.
    let remove: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Service
    @State private var address: String
    @State private var confirmingRemove = false

    init(service: Service, isNew: Bool, save: @escaping (Service) -> Void, remove: (() -> Void)? = nil) {
        self.isNew = isNew
        self.save = save
        self.remove = remove
        _draft = State(initialValue: service)
        _address = State(initialValue: isNew ? "" : service.url.absoluteString)
    }

    private var url: URL? { Service.url(from: address) }
    private var name: String { draft.name.trimmingCharacters(in: .whitespaces) }
    private var symbolExists: Bool { NSImage(systemSymbolName: draft.symbol, accessibilityDescription: nil) != nil }
    private var canSave: Bool { url != nil && !name.isEmpty && symbolExists }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    preview
                }
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Required"))
                    TextField("Address", text: $address, prompt: Text("example.com"))
                    TextField("Tagline", text: $draft.tagline, prompt: Text("Optional"))
                } footer: {
                    Group {
                        if !address.isEmpty, url == nil {
                            Text("Enter a web address, like example.com or http://192.168.1.5:8096.")
                                .foregroundStyle(.red)
                        } else {
                            Text("The tagline appears under the app’s name in the top shelf.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.footnote)
                }
                if draft.brand != nil {
                    Section {
                        Text("\(draft.name) uses its official logo and colors.")
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Appearance")
                    }
                } else {
                    appearance
                }
                Section {
                    Picker("Identify as", selection: $draft.agent) {
                        Text("Safari").tag(Service.Agent.safari)
                        Text("Smart TV").tag(Service.Agent.tv)
                    }
                    let handles = ServiceModules.handlesNavigation(draft)
                    Toggle(isOn: handles ? .constant(false) : $draft.spatialNav) {
                        Text("Remote navigation")
                        Text(handles ? "\(draft.name) handles the remote itself."
                                     : "Moves focus between a desktop site’s links and buttons with the clickpad")
                    }
                    .disabled(handles)
                } header: {
                    Text("Browser")
                } footer: {
                    Text("Smart TV serves sites’ TV layouts, like youtube.com/tv.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                if remove != nil {
                    Button("Remove App…", role: .destructive) { confirmingRemove = true }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add App" : "Done", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 4)
        }
        .frame(width: 540, height: 740)
        .confirmationDialog("Remove \(name.isEmpty ? "this app" : name)?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) {
                remove?()
                dismiss()
            }
        } message: {
            Text("It’s taken off the Home Screen, and its page is closed.")
        }
    }

    /// Symbol and colors, for apps without official artwork.
    private var appearance: some View {
        Section {
            LabeledContent("Symbol") {
                HStack(spacing: 8) {
                    TextField("Symbol", text: $draft.symbol, prompt: Text("SF Symbol name"))
                        .labelsHidden()
                    Image(systemName: symbolExists ? draft.symbol : "questionmark.square.dashed")
                        .foregroundStyle(symbolExists ? .primary : .secondary)
                        .frame(width: 22)
                }
            }
            ColorPicker("Color", selection: Binding(get: { draft.color }, set: { draft.tint = RGB($0) }),
                        supportsOpacity: false)
            ColorPicker("Highlight", selection: Binding(get: { draft.accent ?? draft.color },
                                                        set: { draft.accentTint = RGB($0) }),
                        supportsOpacity: false)
        } header: {
            Text("Appearance")
        } footer: {
            if !symbolExists {
                Text("There’s no SF Symbol named “\(draft.symbol)”.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// The icon as it will look on the Home Screen, updating as you edit.
    private var preview: some View {
        VStack(spacing: 10) {
            IconFace(service: draft, height: 90, unit: 0.45)
                .frame(width: 150, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.2)))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .animation(.default, value: draft)
            Text(isNew ? "New App" : "Home Screen Icon")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Icon preview")
    }

    private func commit() {
        guard let url else { return }
        var s = draft
        s.name = name
        s.url = url
        save(s)
        dismiss()
    }
}
