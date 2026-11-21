import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink("播放设置") { PlaybackSettingsView() }
                .accessibilityIdentifier("settings-playback")
            NavigationLink("弹幕设置") { DanmakuSettingsView() }
            NavigationLink("关注设置") { FavoriteSettingsView() }
            NavigationLink("多屏设置") { MultiRoomSettingsView() }
                .accessibilityIdentifier("settings-multi-room")
            NavigationLink("账号设置") { AccountSettingsView() }
            NavigationLink("关于") { AboutUpdateView() }
        }
        .listStyle(.plain)
    }
}

struct SettingsPicker<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> Text

    init(_ title: LocalizedStringKey, selection: Binding<Value>, options: [Value],
         label: @escaping (Value) -> Text) {
        self.title = title
        _selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        let currentLabel = options.contains(selection) ? label(selection) : nil
        NavigationLink {
            SettingsPickerOptions(title: title, selection: $selection, options: options, label: label)
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                if let currentLabel {
                    currentLabel
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityValue(currentLabel ?? Text(verbatim: ""))
    }
}

private struct SettingsPickerOptions<Value: Hashable>: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedOption: Value?

    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> Text

    var body: some View {
        List(options, id: \.self) { option in
            Button {
                selection = option
                dismiss()
            } label: {
                HStack {
                    label(option)
                    Spacer(minLength: 12)
                    if option == selection {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                }
            }
            .accessibilityAddTraits(option == selection ? .isSelected : [])
            .focused($focusedOption, equals: option)
        }
        .defaultFocus($focusedOption, selection)
        .navigationTitle(title)
    }
}

extension Array where Element: Comparable {
    // Synced preferences can fall between the presets offered on tvOS.
    func includingSelection(_ selection: Element) -> Self {
        contains(selection) ? self : (self + [selection]).sorted()
    }
}
