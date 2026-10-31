import SwiftUI

struct SettingsView: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        @Bindable var runtime = runtime
        Form {
            Picker(Copy.appearance, selection: $runtime.appearance) {
                ForEach(AppearanceChoice.allCases) { choice in
                    Text(Copy.appearanceName(choice)).tag(choice)
                }
            }
            Toggle(Copy.revealDone, isOn: $runtime.revealWhenDone)
            Toggle(Copy.sound, isOn: $runtime.soundOnDone)
            Toggle(Copy.haptic, isOn: $runtime.hapticOnWheel)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Copy.quality)  \(Int(runtime.jpegQuality * 100))%")
                Slider(value: $runtime.jpegQuality, in: 0.4...1)
            }
            Text(Copy.about)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(12)
        .onChange(of: runtime.appearance) { _, _ in runtime.noteSettingsChanged() }
        .onChange(of: runtime.revealWhenDone) { _, _ in runtime.noteSettingsChanged() }
        .onChange(of: runtime.soundOnDone) { _, _ in runtime.noteSettingsChanged() }
        .onChange(of: runtime.hapticOnWheel) { _, _ in runtime.noteSettingsChanged() }
        .onChange(of: runtime.jpegQuality) { _, _ in runtime.noteSettingsChanged() }
    }
}
