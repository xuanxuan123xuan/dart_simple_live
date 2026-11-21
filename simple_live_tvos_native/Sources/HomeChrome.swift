import Combine
import SwiftUI
import UIKit

enum HomeSection: String, CaseIterable, Identifiable {
    case home, live, search, favorites, history, settings

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .home: "首页"
        case .live: "热门"
        case .search: "搜索"
        case .favorites: "关注"
        case .history: "历史"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
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

@MainActor
final class HomeFocusCoordinator {
    var bottomBarIsFocused = false
    var entryID: UUID?
    let entryRequests = PassthroughSubject<UUID, Never>()

    func moveUpFromBottomBar() -> Bool {
        guard bottomBarIsFocused, let entryID else { return false }
        Task { @MainActor in
            guard bottomBarIsFocused, self.entryID == entryID else { return }
            entryRequests.send(entryID)
        }
        return true
    }
}

struct HomeFocusHost<Content: View>: UIViewControllerRepresentable {
    @ViewBuilder let content: (HomeFocusCoordinator) -> Content

    func makeUIViewController(context: Context) -> HomeFocusHostingController<Content> {
        HomeFocusHostingController(content: content)
    }

    func updateUIViewController(_ controller: HomeFocusHostingController<Content>, context: Context) {
        controller.rootView = content(controller.focusCoordinator)
    }
}

final class HomeFocusHostingController<Content: View>: UIHostingController<Content> {
    let focusCoordinator: HomeFocusCoordinator

    init(content: (HomeFocusCoordinator) -> Content) {
        let coordinator = HomeFocusCoordinator()
        focusCoordinator = coordinator
        super.init(rootView: content(coordinator))
    }

    @MainActor required dynamic init?(coder: NSCoder) { nil }

    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        // Stop the directional update before tvOS can focus a lower row.
        if context.focusHeading.contains(.up), focusCoordinator.moveUpFromBottomBar() {
            return false
        }
        return super.shouldUpdateFocus(in: context)
    }
}

private struct HomeFocusCoordinatorKey: EnvironmentKey {
    static let defaultValue: HomeFocusCoordinator? = nil
}

extension EnvironmentValues {
    var homeFocusCoordinator: HomeFocusCoordinator? {
        get { self[HomeFocusCoordinatorKey.self] }
        set { self[HomeFocusCoordinatorKey.self] = newValue }
    }
}

enum HomeContentAnchor: Hashable {
    case top
}

private struct HomeContentFocus<Item: Hashable>: ViewModifier {
    @Environment(\.homeFocusCoordinator) private var coordinator
    @State private var id = UUID()
    @State private var pendingItem: Item?
    let firstItem: Item?
    let focus: FocusState<Item?>.Binding

    func body(content: Content) -> some View {
        if let coordinator {
            ScrollViewReader { scroll in
                content
                    .onAppear {
                        if firstItem != nil { coordinator.entryID = id }
                    }
                    .onDisappear {
                        if coordinator.entryID == id { coordinator.entryID = nil }
                    }
                    .onReceive(coordinator.entryRequests) { entryID in
                        guard entryID == id, let firstItem else { return }
                        scroll.scrollTo(HomeContentAnchor.top, anchor: .top)
                        pendingItem = firstItem
                    }
                    .task(id: pendingItem) {
                        guard let pendingItem else { return }
                        // A lazy grid can instantiate the first row after the scroll.
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        if coordinator.entryID == id, coordinator.bottomBarIsFocused {
                            focus.wrappedValue = pendingItem
                        }
                        self.pendingItem = nil
                    }
            }
        } else {
            content
        }
    }
}

extension View {
    func focusFirstItemFromBottomBar<Item: Hashable>(_ firstItem: Item?, focus: FocusState<Item?>.Binding) -> some View {
        modifier(HomeContentFocus(firstItem: firstItem, focus: focus))
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
