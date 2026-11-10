import SwiftUI

/// What the player is asked to play: an item, from a position, in a chosen version.
struct PlayRequest: Identifiable {
    let id = UUID()
    let item: Item
    let source: MediaSource
    let playSessionId: String?
    let startMs: Double?
}

struct DetailView: View {
    @EnvironmentObject private var session: Session
    let item: Item

    @State private var full: Item?
    @State private var seasons: [Item] = []
    @State private var season: Item?
    @State private var episodes: [Item] = []
    @State private var nextUp: Item?
    @State private var versionsFor: VersionChoice?
    @State private var playing: PlayRequest?
    /// Waits for the version sheet to close, as one screen can't open over another closing.
    @State private var pendingPlay: PlayRequest?

    private var shown: Item { full ?? item }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RemoteImage(url: session.client?.backdrop(shown, height: 1080))
                .ignoresSafeArea()
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.95), .black.opacity(0.6), .clear], startPoint: .bottom, endPoint: .top)
                        .ignoresSafeArea()
                }
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                        .ignoresSafeArea()
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Spacer(minLength: 260)
                    header
                    actions
                    if shown.isSeries { seriesSection }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
        }
        .task { await load() }
        .sheet(item: $versionsFor, onDismiss: {
            if let request = pendingPlay {
                pendingPlay = nil
                playing = request
            }
        }) { choice in
            VersionsView(choice: choice) { request in
                pendingPlay = request
                versionsFor = nil
            }
            .environmentObject(session)
        }
        .fullScreenCover(item: $playing) { request in
            PlayerScreen(request: request) {
                playing = nil
                Task { await load() }
            }
            .environmentObject(session)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            if shown.isEpisode, let series = shown.seriesName {
                Text(series).font(.title3).foregroundStyle(.secondary)
            }
            Text(shown.isEpisode ? shown.displayTitle : (shown.name ?? ""))
                .font(.system(size: 64, weight: .bold))
                .lineLimit(2)
            HStack(spacing: 24) {
                if let year = shown.productionYear { Text(String(year)) }
                if let minutes = shown.runtimeMinutes { Text(minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m") }
                if let rating = shown.officialRating { Text(rating).padding(.horizontal, 8).overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary)) }
                if let score = shown.communityRating { Text(String(format: "★ %.1f", score)) }
                if let genres = shown.genres, !genres.isEmpty { Text(genres.prefix(3).joined(separator: ", ")) }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            if let overview = shown.overview {
                Text(overview)
                    .font(.callout)
                    .lineLimit(5)
                    .frame(maxWidth: 1200, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 30) {
            if shown.isSeries {
                if let next = nextUp {
                    Button {
                        versionsFor = VersionChoice(item: next, startMs: next.resumeMs)
                    } label: {
                        Label("Play \(next.displayTitle)", systemImage: "play.fill")
                    }
                }
            } else {
                if let resume = shown.resumeMs {
                    Button {
                        versionsFor = VersionChoice(item: shown, startMs: resume)
                    } label: {
                        Label("Resume from \(clock(resume))", systemImage: "play.fill")
                    }
                }
                Button {
                    versionsFor = VersionChoice(item: shown, startMs: nil)
                } label: {
                    Label(shown.resumeMs == nil ? "Play" : "Play from start", systemImage: shown.resumeMs == nil ? "play.fill" : "arrow.counterclockwise")
                }
            }
            Button {
                Task { await setPlayed(!(shown.userData?.played ?? false)) }
            } label: {
                Label(shown.userData?.played == true ? "Watched" : "Mark watched", systemImage: shown.userData?.played == true ? "checkmark.circle.fill" : "checkmark.circle")
            }
        }
        .focusSection()
    }

    @ViewBuilder private var seriesSection: some View {
        if !seasons.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(seasons) { candidate in
                        Button(candidate.name ?? "Season") {
                            season = candidate
                            Task { await loadEpisodes() }
                        }
                        .buttonStyle(.bordered)
                        .tint(candidate.id == season?.id ? .white : nil)
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
            .focusSection()
        }
        LazyVStack(alignment: .leading, spacing: 30) {
            ForEach(episodes) { episode in
                Button {
                    versionsFor = VersionChoice(item: episode, startMs: episode.resumeMs)
                } label: {
                    HStack(alignment: .top, spacing: 30) {
                        RemoteImage(url: session.client?.poster(episode, height: 360))
                            .frame(width: 400, height: 225)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(episode.displayTitle).font(.headline)
                                if episode.userData?.played == true {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                                }
                            }
                            if let minutes = episode.runtimeMinutes {
                                Text("\(minutes)m").font(.caption).foregroundStyle(.secondary)
                            }
                            if let overview = episode.overview {
                                Text(overview).font(.caption).lineLimit(3).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)
            }
        }
        .focusSection()
    }

    private func load() async {
        guard let client = session.client, let userId = session.userId else { return }
        let found: ItemsResult? = try? await client.get("/Items", [
            "userId": userId,
            "Ids": item.id,
            "Fields": "Genres,Overview,People,ProviderIds,Studios,Taglines,RemoteTrailers",
        ])
        if let first = found?.items?.first { full = first }
        guard shown.isSeries else { return }
        let next: ItemsResult? = try? await client.get("/Shows/NextUp", ["userId": userId, "SeriesId": item.id, "Limit": "1"])
        nextUp = next?.items?.first
        let list: ItemsResult? = try? await client.get("/Shows/\(item.id)/Seasons", ["userId": userId])
        seasons = list?.items ?? []
        // Opens on the season of the next episode, else the first one with something left to watch.
        if season == nil {
            season = seasons.first { $0.id == nextUp?.seasonId }
                ?? seasons.first { $0.userData?.played != true && ($0.indexNumber ?? 0) > 0 }
                ?? seasons.first
        }
        await loadEpisodes()
        if nextUp == nil { nextUp = episodes.first }
    }

    private func loadEpisodes() async {
        guard let client = session.client, let userId = session.userId, let season else { return }
        let list: ItemsResult? = try? await client.get("/Shows/\(item.id)/Episodes", [
            "userId": userId,
            "SeasonId": season.id,
            "Fields": "Overview",
        ])
        episodes = list?.items ?? []
    }

    private func setPlayed(_ played: Bool) async {
        guard let client = session.client, let userId = session.userId else { return }
        try? await client.call(played ? "POST" : "DELETE", "/UserPlayedItems/\(shown.id)", ["userId": userId])
        await load()
    }

    private func clock(_ ms: Double) -> String {
        let seconds = Int(ms / 1000)
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// An item whose versions are being picked, and where it would start.
struct VersionChoice: Identifiable {
    let id = UUID()
    let item: Item
    let startMs: Double?
}

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
