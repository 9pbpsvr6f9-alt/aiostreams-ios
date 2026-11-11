import SwiftUI

/// The streams the configuration's addons found for one title, best first, as the server sorted them.
struct VersionsView: View {
    @EnvironmentObject private var session: Session
    let choice: VersionChoice
    let play: (PlayRequest) -> Void

    @State private var info: PlaybackInfo?
    @State private var error: String?
    @State private var opening: String?

    var body: some View {
        NavigationStack {
            Group {
                if let sources = info?.mediaSources, !sources.isEmpty {
                    List(sources, id: \.ownId) { source in
                        Button {
                            Task { await open(source) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(source.label).font(.headline).lineLimit(2)
                                    Spacer()
                                    if opening == source.ownId { ProgressView() }
                                }
                                if let description = source.aiostreams?.description, !description.isEmpty {
                                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                                }
                                if let size = source.size, size > 0 {
                                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(opening != nil || source.aiostreams?.ytId != nil)
                    }
                } else if let error {
                    VStack(spacing: 30) {
                        ErrorText(text: error)
                        Button("Try again") { Task { await load(refresh: true) } }
                    }
                } else if info != nil {
                    VStack(spacing: 30) {
                        Text("No playable versions found. Only streams with a link play: use debrid or Usenet.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Search again") { Task { await load(refresh: true) } }
                    }
                } else {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Searching your addons…").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(choice.item.isEpisode ? "\(choice.item.seriesName ?? "") · \(choice.item.displayTitle)" : (choice.item.name ?? "Versions"))
        }
        .task { await load(refresh: false) }
    }

    private func load(refresh: Bool) async {
        guard let client = session.client, let userId = session.userId else { return }
        error = nil
        if refresh { info = nil }
        do {
            var result = try await client.playbackInfo(userId: userId, itemId: choice.item.id, refresh: refresh)
            // Versions only the app's own player could open from YouTube aren't offered here.
            result.mediaSources = result.mediaSources?.filter { $0.aiostreams?.ytId == nil }
            info = result
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Naming the version again gets its subtitles from the configuration's subtitle addons.
    private func open(_ source: MediaSource) async {
        guard let client = session.client, let userId = session.userId else { return }
        opening = source.ownId
        defer { opening = nil }
        var chosen = source
        var playSession = info?.playSessionId
        if let named = try? await client.playbackInfo(userId: userId, itemId: choice.item.id, sourceId: source.ownId),
           let match = named.mediaSources?.first(where: { $0.ownId == source.ownId }) ?? named.mediaSources?.first {
            chosen = match
            playSession = named.playSessionId ?? playSession
        }
        play(PlayRequest(item: choice.item, source: chosen, playSessionId: playSession, startMs: choice.startMs))
    }
}
