import AVKit
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var core: NativeCoreClient
    let provider: String
    let room: RoomDescriptor

    @StateObject private var engine = KSPlayerPlaybackEngine()
    @State private var errorMessage: String?
    @State private var qualities: [String] = []
    @State private var selectedQuality: String?

    var body: some View {
        ZStack {
            if let nativeView = engine.session?.nativeView {
                KSPlayerViewRepresentable(playerView: nativeView)
                    .ignoresSafeArea()
            } else if let player = engine.session?.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
            }
            if let errorMessage {
                Text(errorMessage)
                    .padding(24)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
            }
            DanmakuOverlay(messages: core.danmakuMessages)
            if !qualities.isEmpty {
                Menu(selectedQuality ?? "清晰度") {
                    ForEach(qualities, id: \.self) { quality in
                        Button(quality) {
                            selectedQuality = quality
                            Task { await reloadPlayback() }
                        }
                    }
                }
                .padding(.top, 36)
                .padding(.trailing, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .task {
            await core.startDanmaku(provider: provider, roomId: room.roomId)
            await startPlayback()
        }
        .onDisappear {
            engine.stop()
            Task { await core.stopDanmaku(provider: provider, roomId: room.roomId) }
        }
    }

    private func startPlayback() async {
        do {
            qualities = try await core.qualityNames(provider: provider, roomId: room.roomId)
            selectedQuality = qualities.first
            await reloadPlayback()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadPlayback() async {
        guard let selectedQuality else { return }
        engine.stop()
        do {
            let descriptor = try await core.playback(
                provider: provider,
                roomId: room.roomId,
                quality: selectedQuality
            )
            for (index, url) in descriptor.urls.enumerated() {
                let protocolName = descriptor.protocols.indices.contains(index)
                    ? descriptor.protocols[index]
                    : "unknown"
                let kind = StreamProtocol(rawValue: protocolName) ?? .unknown
                do {
                    _ = try await engine.prepare(
                        url: url,
                        headers: descriptor.headers,
                        protocolKind: kind
                    )
                    engine.play()
                    errorMessage = nil
                    return
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            if descriptor.urls.isEmpty {
                errorMessage = "平台没有返回播放地址"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DanmakuOverlay: View {
    let messages: [DanmakuDescriptor]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(messages.suffix(8)) { item in
                HStack(spacing: 8) {
                    Text("\(item.userName)：\(item.message)")
                        .foregroundStyle(Color(
                            red: Double(item.red) / 255,
                            green: Double(item.green) / 255,
                            blue: Double(item.blue) / 255
                        ))
                        .shadow(radius: 4)
                    if let imageURL = item.imageURLs.first,
                       let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            EmptyView()
                        }
                        .frame(width: 28, height: 28)
                    }
                }
            }
        }
        .font(.title3)
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}
