import SwiftUI

enum HomeSection: String, CaseIterable, Identifiable {
    case live, search, favorites, history, settings

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .live: "直播"
        case .search: "搜索"
        case .favorites: "收藏"
        case .history: "历史"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .live: "tv"
        case .search: "magnifyingglass"
        case .favorites: "star"
        case .history: "clock"
        case .settings: "gearshape"
        }
    }
}

struct HomeBackdrop: View {
    var body: some View {
        Color(red: 0.047, green: 0.043, blue: 0.075)
            .overlay(alignment: .topLeading) {
                RadialGradient(
                    colors: [Color(red: 0.14, green: 0.105, blue: 0.24), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 850
                )
            }
            .ignoresSafeArea()
    }
}

struct HomePlatformBar: View {
    let providers: [ProviderDescriptor]
    let selection: String
    let select: (String) -> Void

    var body: some View {
        HStack(spacing: 24) {
            Image("SimpleLiveMark")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .accessibilityLabel("Simple Live")

            HStack(spacing: 12) {
                ForEach(providers) { provider in
                    let selected = provider.id == selection
                    Button { select(provider.id) } label: {
                        HomePill(selected: selected) {
                            Text(provider.id == "bilibili" ? "B 站" : provider.title)
                                .frame(minWidth: 78)
                        }
                    }
                    .buttonStyle(HomeButtonStyle())
                    .focusEffectDisabled()
                    .accessibilityLabel(provider.title)
                    .accessibilityIdentifier("platform-\(provider.id)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .focusSection()

            Color.clear.frame(width: 68, height: 1)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 15)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

struct HomeBottomBar: View {
    let selection: HomeSection
    let focus: FocusState<HomeSection?>.Binding
    let select: (HomeSection) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(HomeSection.allCases) { section in
                let selected = section == selection
                Button { select(section) } label: {
                    HomePill(selected: selected) {
                        Label(section.title, systemImage: section.symbol)
                            .frame(minWidth: 128)
                    }
                }
                .buttonStyle(HomeButtonStyle())
                .focusEffectDisabled()
                .focused(focus, equals: section)
                .accessibilityIdentifier("section-\(section.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(8)
        .background(.white.opacity(0.055), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.10))
        }
        .frame(maxWidth: .infinity)
        .focusSection()
    }
}

struct HomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct HomePill<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    var selected = false
    var quiet = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(.system(size: 25, weight: selected ? .semibold : .medium))
            .foregroundStyle(isFocused ? Color(red: 0.11, green: 0.07, blue: 0.20) : selected ? Color(red: 0.90, green: 0.85, blue: 1) : .white)
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(background, in: Capsule())
            .overlay {
                Capsule().strokeBorder(selected && !isFocused ? .white.opacity(0.12) : .clear)
            }
            .scaleEffect(isFocused ? 1.045 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var background: Color {
        if isFocused { return Color(red: 0.89, green: 0.83, blue: 1) }
        if selected { return Color(red: 0.31, green: 0.23, blue: 0.51) }
        return quiet ? .clear : .white.opacity(0.075)
    }
}
