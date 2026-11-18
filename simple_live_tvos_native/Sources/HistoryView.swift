import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var confirmClear = false
    @State private var manage = false
    @FocusState private var focusedRoom: String?
    @State private var lastFocusedRoom: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("观看历史").font(.system(size: 42, weight: .bold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(manage ? "完成管理" : "管理") { manage.toggle() }
                    .disabled(library.historyEntries.isEmpty)
                Button("清空记录", role: .destructive) { confirmClear = true }
                    .disabled(library.historyEntries.isEmpty)
                    .accessibilityIdentifier("history-clear")
                    .confirmationDialog("清空观看历史？", isPresented: $confirmClear, titleVisibility: .visible) {
                        Button("清空", role: .destructive) {
                            library.clearRecent()
                            manage = false
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("此操作会删除此设备上的全部观看记录。")
                    }
            }
            .focusSection()
            if library.historyEntries.isEmpty {
                ContentUnavailableView("暂无观看历史", systemImage: "clock")
            } else {
                historyGrid(library.historyEntries)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func historyGrid(_ entries: [HistoryEntry]) -> some View {
        let source = entries.map(\.room)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 24)], spacing: 24) {
                ForEach(entries) { entry in
                    Group {
                        if manage {
                            Menu { remove(entry) } label: { card(entry) }
                        } else {
                            NavigationLink(value: HomeRoute.room(entry.room, queue: source)) { card(entry) }
                                .contextMenu { remove(entry) }
                        }
                    }
                    .buttonStyle(HomeButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedRoom, equals: entry.id)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .defaultFocus($focusedRoom, entries.contains(where: { $0.id == lastFocusedRoom }) ? lastFocusedRoom : entries.first?.id)
        .onChange(of: focusedRoom) { _, value in
            if let value { lastFocusedRoom = value }
        }
        .focusSection()
    }

    private func card(_ entry: HistoryEntry) -> some View {
        let time = entry.watchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "观看时间未知"
        return RoomTile(room: entry.room, caption: time)
    }

    private func remove(_ entry: HistoryEntry) -> some View {
        Button("删除此记录", role: .destructive) { library.removeVisit(entry.room) }
    }
}
