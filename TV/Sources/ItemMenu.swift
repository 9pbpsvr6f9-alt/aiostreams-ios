import SwiftUI

// The web app's item menu (components/item-menu.tsx), which a TV opens by holding select
// on a card: play, go to the show or open the title, watched, watched up to here, remove
// from Continue watching, and favourite.

extension Notification.Name {
    /// Watched or favourite state changed, so pages showing it load again.
    static let watchStateChanged = Notification.Name("aiostreams.watchStateChanged")
}

private struct PlayItemKey: EnvironmentKey {
    static let defaultValue: (Item, PlayMode) -> Void = { _, _ in }
}

private struct OpenRouteKey: EnvironmentKey {
    static let defaultValue: (Route) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Plays a title from anywhere: its versions, or one straight away, then the player.
    var playItem: (Item, PlayMode) -> Void {
        get { self[PlayItemKey.self] }
        set { self[PlayItemKey.self] = newValue }
    }

    /// Opens a page on the current place's stack.
    var openRoute: (Route) -> Void {
        get { self[OpenRouteKey.self] }
        set { self[OpenRouteKey.self] = newValue }
    }
}

struct ItemMenu: ViewModifier {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.playItem) private var play
    @Environment(\.openRoute) private var openRoute
    let item: Item
    /// On the title's own page, where Open would lead nowhere.
    var onPage = false

    private var played: Bool { item.userData?.played == true }

    /// Whether Play would start a version without listing them.
    private var playsStraight: Bool {
        prefs.autoPlayFirst || (item.resumeMs != nil && LastVersions.get(item.id) != nil)
    }
    private var favourite: Bool { item.userData?.isFavorite == true }

    func body(content: Content) -> some View {
        content.contextMenu {
            if item.playable {
                Button { play(item, .usual) } label: {
                    Label(item.resumeMs != nil ? "Resume" : "Play", systemImage: "play.fill")
                }
                // The other way to start, as holding Play does in the web app.
                if playsStraight {
                    Button { play(item, .list) } label: {
                        Label("Choose a version", systemImage: "list.bullet")
                    }
                } else {
                    Button { play(item, .straight) } label: {
                        Label("Play straight away", systemImage: "forward.end")
                    }
                }
            }
            if item.isEpisode, let seriesId = item.seriesId {
                Button {
                    openRoute(.item(Item(id: seriesId, name: item.seriesName, type: "Series")))
                } label: {
                    Label("Go to show", systemImage: "tv")
                }
            } else if !onPage {
                Button {
                    openRoute(item.isFolder ? .library(item) : .item(item))
                } label: {
                    Label("Open", systemImage: "info.circle")
                }
            }
            if item.type != "BoxSet" {
                // Watched before but started again: marking it watched finishes this time through.
                if !played || item.resumeMs != nil {
                    Button {
                        act { client, userId in
                            try await client.call("POST", "/UserPlayedItems/\(item.id)", ["userId": userId])
                        }
                    } label: {
                        Label("Mark watched", systemImage: "checkmark")
                    }
                }
                if played {
                    Button {
                        act { client, userId in
                            try await client.call("DELETE", "/UserPlayedItems/\(item.id)", ["userId": userId])
                        }
                    } label: {
                        Label("Mark unwatched", systemImage: "arrow.uturn.backward")
                    }
                }
                if item.isEpisode, item.seriesId != nil {
                    Button {
                        act { client, userId in try await markUpTo(client: client, userId: userId) }
                    } label: {
                        Label("Mark watched up to here", systemImage: "checkmark.circle")
                    }
                }
                if item.resumeMs != nil {
                    Button {
                        act { client, userId in
                            let _: UserData? = try await client.post(
                                "/UserItems/\(item.id)/UserData",
                                ["userId": userId],
                                body: ["PlaybackPositionTicks": 0]
                            )
                        }
                    } label: {
                        Label("Remove from continue watching", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            if favourite || item.type == "Movie" || item.isSeries {
                Button {
                    act { client, userId in
                        try await client.call(favourite ? "DELETE" : "POST", "/UserFavoriteItems/\(item.id)", ["userId": userId])
                    }
                } label: {
                    Label(favourite ? "Remove favourite" : "Add favourite", systemImage: favourite ? "heart.slash" : "heart")
                }
            }
        }
    }

    private func act(_ change: @escaping (JellyfinClient, String) async throws -> Void) {
        guard let client = session.client, let userId = session.userId else { return }
        Task {
            do {
                try await change(client, userId)
            } catch {
                AppLog.warn("menu", "\(error.localizedDescription)")
            }
            NotificationCenter.default.post(name: .watchStateChanged, object: nil)
        }
    }

    /// The server's own endpoint where it has one; otherwise each aired episode up to this one.
    private func markUpTo(client: JellyfinClient, userId: String) async throws {
        do {
            try await client.call("POST", "/AIOStreams/PlayedUpTo/\(item.id)")
            return
        } catch let failure as JellyfinError where failure.status == 404 || failure.status == 405 {
            // An older server: mark them one by one.
        }
        guard let seriesId = item.seriesId else { return }
        let all: ItemsResult = try await client.get("/Shows/\(seriesId)/Episodes", ["userId": userId])
        let season = item.parentIndexNumber ?? 0
        let episode = item.indexNumber ?? 0
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wanted = (all.items ?? []).filter { candidate in
            guard candidate.userData?.played != true,
                  let s = candidate.parentIndexNumber, let e = candidate.indexNumber else { return false }
            let upTo = s == season ? e <= episode : (season > 0 && s > 0 && s < season)
            let aired = candidate.premiereDate.flatMap { iso.date(from: $0) }.map { $0 <= now } ?? true
            return upTo && aired
        }
        for candidate in wanted {
            try await client.call("POST", "/UserPlayedItems/\(candidate.id)", ["userId": userId])
        }
    }
}

extension View {
    func itemMenu(_ item: Item, onPage: Bool = false) -> some View {
        modifier(ItemMenu(item: item, onPage: onPage))
    }

    /// Loads again when a menu changes what's watched or favourite.
    func reloadOnWatchChange(_ action: @escaping () async -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .watchStateChanged)) { _ in
            Task { await action() }
        }
    }
}
