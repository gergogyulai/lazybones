import SwiftUI

struct LayoutSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Picker("Apps per row", selection: $model.settings.columns) {
                ForEach(3...7, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Top shelf", isOn: $model.settings.showShelf)
            Toggle("Show control hints", isOn: $model.settings.showHints)
        }
        .formStyle(.grouped)
    }
}
