import SwiftUI

extension View {
    func destructiveButtonStyle() -> some View {
        buttonStyle(DestructiveButtonStyle())
            .focusEffectDisabled()
    }
}

private struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration)
    }

    private struct Pill: View {
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration

        var body: some View {
            let fill = isFocused ? Color(red: 0.65, green: 0.15, blue: 0.20)
                                 : Color(red: 0.52, green: 0.11, blue: 0.16)

            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 30)
                .frame(minHeight: 66)
                .background(fill, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isFocused ? .white : .clear, lineWidth: 2)
                }
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

struct TVConfirmation: View {
    let title: String
    var message: String? = nil
    let confirmTitle: String
    var isDestructive = true
    var confirmIdentifier = "confirmation-confirm"
    let cancel: () -> Void
    let confirm: () -> Void

    @FocusState private var focus: Action?

    private enum Action: Hashable { case cancel, confirm }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 24) {
                Text(title)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message).foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    Button("取消", role: .cancel, action: cancel)
                        .focused($focus, equals: .cancel)
                    confirmButton
                }
            }
            .padding(44)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30))
            .focusSection()
        }
        .defaultFocus($focus, .cancel)
        .task { focus = .cancel }
        .onExitCommand(perform: cancel)
    }

    @ViewBuilder
    private var confirmButton: some View {
        let button = Button(confirmTitle, role: isDestructive ? .destructive : nil, action: confirm)
            .focused($focus, equals: .confirm)
            .accessibilityIdentifier(confirmIdentifier)

        if isDestructive {
            button.destructiveButtonStyle()
        } else {
            button
        }
    }
}

struct DestructiveConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var message: String? = nil
    let confirmTitle: String
    let action: () -> Void

    var body: some View {
        TVConfirmation(title: title, message: message, confirmTitle: confirmTitle,
                       cancel: { dismiss() }) {
            dismiss()
            action()
        }
        .presentationBackground(.clear)
    }
}
