import SwiftUI

/// An app's navigation and, when it uses the cursor, the cursor's settings. Shared by the app's
/// settings and the sheet for adding an app.
struct NavigationSections: View {
    @Binding var service: Service
    /// Changes apply as they're made, so say that a change of navigation reloads the app.
    var live = false

    var body: some View {
        let handles = ServiceModules.handlesNavigation(service)
        Section {
            if handles {
                LabeledContent("Navigation", value: "Built In")
            } else {
                Picker("Navigation", selection: $service.navigation) {
                    ForEach(Navigation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Remote")
        } footer: {
            footnote(handles ? "\(service.name) handles the remote itself."
                             : service.navigation.detail + (live ? ". The app reloads when you change this." : "."))
        }
        if !handles, service.navigation == .cursor {
            cursorSections
        }
    }

    @ViewBuilder private var cursorSections: some View {
        let c = $service.cursor
        Section {
            Toggle(isOn: c.followsTouch) {
                Text("Move with touch")
                Text("Slide a finger on the clickpad, like a trackpad")
            }
            .disabled(service.cursor.followsTouch && !service.cursor.followsArrows)
            speed("Touch speed", c.touchSpeed).disabled(!service.cursor.followsTouch)
            Toggle(isOn: c.followsArrows) {
                Text("Move with the clickpad")
                Text("Click the ring to step, hold it to glide. Otherwise the page gets arrow keys.")
            }
            .disabled(service.cursor.followsArrows && !service.cursor.followsTouch)
            speed("Clickpad speed", c.arrowSpeed).disabled(!service.cursor.followsArrows)
            Picker("Snapping", selection: c.snapping) {
                ForEach(CursorSettings.Snapping.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Size", selection: c.size) {
                ForEach(CursorSettings.Size.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Cursor")
        } footer: {
            footnote(snappingNote)
        }
        Section {
            Toggle(isOn: c.ringScrolls) {
                Text("Circle the ring to scroll")
                Text("Run a finger around the clickpad’s edge, as you would to scrub on Apple TV")
            }
            Group {
                Picker("Turning clockwise scrolls", selection: c.scrollDirection) {
                    ForEach(CursorSettings.ScrollDirection.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                speed("Scroll speed", c.scrollSpeed)
                Toggle(isOn: c.scrollMomentum) {
                    Text("Momentum")
                    Text("Keeps scrolling for a moment after a quick turn, like a trackpad")
                }
            }
            .disabled(!service.cursor.ringScrolls)
        } header: {
            Text("Ring Scrolling")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                footnote("Scrolls whatever is under the cursor. Pushing the cursor past the top or bottom of the page scrolls too.")
                Spacer()
                Button("Restore Defaults") { service.cursor = CursorSettings() }
                    .disabled(service.cursor == CursorSettings())
            }
        }
    }

    private var snappingNote: String {
        switch service.cursor.snapping {
        case .off: "The cursor goes exactly where you move it."
        case .light: "The cursor leans toward buttons and slows a little over them."
        case .medium: "The cursor is drawn onto nearby buttons, and a click of the ring hops to the next one."
        case .hard: "The cursor locks onto buttons from further away, and a click of the ring hops to the next one, however far."
        }
    }

    private func speed(_ title: String, _ value: Binding<Double>) -> some View {
        LabeledContent(title) {
            Slider(value: value, in: 0...1) {
                Text(title)
            } minimumValueLabel: {
                Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "hare.fill").foregroundStyle(.secondary)
            }
            .labelsHidden()
            .frame(maxWidth: 260)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
    }
}
