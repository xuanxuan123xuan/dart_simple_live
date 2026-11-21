import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var removal: Removal?
    @State private var manage = false
    @FocusState private var focusedRoom: String?
    @State private var lastFocusedRoom: String?

    private enum Removal: Identifiable {
        case all
        case entry(HistoryEntry)

        var id: String {
            switch self {
            case .all: "all"
            case let .entry(entry): "entry:\(entry.id)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("观看历史").font(.system(size: 42, weight: .bold)).accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink("导入历史", value: HomeRoute.sync(.histories))
                    .accessibilityIdentifier("history-import")
                Button(manage ? "完成管理" : "管理") { manage.toggle() }
                    .disabled(library.historyEntries.isEmpty)
                Button("清空记录", role: .destructive) { removal = .all }
                    .destructiveButtonStyle()
                    .disabled(library.historyEntries.isEmpty)
                    .accessibilityIdentifier("history-clear")
            }
            .focusSection()
            if library.historyEntries.isEmpty {
                ContentUnavailableView("暂无观看历史", systemImage: "clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                historyGrid(library.historyEntries)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fullScreenCover(item: $removal) { removal in
            switch removal {
            case .all:
                DestructiveConfirmation(title: "清空观看历史？", message: "此操作会删除此设备上的全部观看记录。",
                                        confirmTitle: "清空") {
                    library.clearRecent()
                    manage = false
                }
            case let .entry(entry):
                DestructiveConfirmation(title: "删除此记录？", message: entry.room.title,
                                        confirmTitle: "删除此记录") {
                    library.removeVisit(entry.room)
                }
            }
        }
    }

    private func historyGrid(_ entries: [HistoryEntry]) -> some View {
        let source = entries.map(\.room)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 24)], spacing: 24) {
                ForEach(entries) { entry in
                    Group {
                        if manage {
                            Button { removal = .entry(entry) } label: { card(entry) }
                        } else {
                            NavigationLink(value: HomeRoute.room(entry.room, queue: source)) { card(entry) }
                                .contextMenu {
                                    Button("删除此记录…") { removal = .entry(entry) }
                                }
                        }
                    }
                    .buttonStyle(HomeButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedRoom, equals: entry.id)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .id(HomeContentAnchor.top)
        }
        .defaultFocus($focusedRoom, entries.contains(where: { $0.id == lastFocusedRoom }) ? lastFocusedRoom : entries.first?.id)
        .onChange(of: focusedRoom) { _, value in
            if let value { lastFocusedRoom = value }
        }
        .focusSection()
        .focusFirstItemFromBottomBar(entries.first?.id, focus: $focusedRoom)
    }

    private func card(_ entry: HistoryEntry) -> some View {
        let time = entry.watchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "观看时间未知"
        return RoomTile(room: entry.room, caption: time)
    }
}
