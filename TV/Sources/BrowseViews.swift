import SwiftUI

/// Where a tapped item leads: a title's page, or a library's grid.
enum Route: Hashable {
    case item(Item)
    case library(Item)
}

extension View {
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            Group {
                switch route {
                case .item(let item): DetailView(item: item)
                case .library(let view): LibraryView(view: view)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// What a library holds by its type; one without a type holds both.
func libraryTypes(_ view: Item) -> String {
    switch view.collectionType {
    case "movies": return "Movie"
    case "tvshows": return "Series"
    case "boxsets": return "BoxSet"
    default: return "Movie,Series"
    }
}

/// Live TV, music and the like aren't played here.
func isBrowsable(_ view: Item) -> Bool {
    !["livetv", "music", "musicvideos", "books", "photos", "playlists"].contains(view.collectionType ?? "")
}

/// The genre a library opens with: None where offered, which a catalog that needs a genre reads
/// as all of it, else the first when it needs one (the web app's `defaultGenre`).
func openingGenre(_ client: JellyfinClient, userId: String, view: Item) async -> String? {
    guard view.aiostreams?.genreRequired == true else { return nil }
    let genres: ItemsResult? = try? await client.get("/Genres", ["userId": userId, "ParentId": view.id])
    let list = genres?.items ?? []
    return (list.first { $0.name == "None" } ?? list.first)?.id
}

/// The page's own margin, beside the rail: 40 px.
let pageMargin = Theme.px(40)

/// A page's heading, as the web app's are.
struct PageTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.font(Theme.xl3, .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, pageMargin)
            .padding(.top, Theme.px(40))
    }
}

// MARK: - Home

struct HomeRow: Identifiable {
    let id: String
    let title: String
    let items: [Item]
    var library: Item?
    /// Stills rather than posters: what's under way.
    var wide = false
}

struct HomeView: View {
    @EnvironmentObject private var session: Session
    @State private var rows: [HomeRow] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.px(32)) {
                ForEach(rows) { row in
                    ItemRow(row: row)
                }
                if loading && rows.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.px(200))
                }
                if !loading && rows.isEmpty {
                    VStack(spacing: Theme.px(16)) {
                        Text(error ?? "Nothing here yet. Add catalogs to your configuration.")
                            .font(Theme.font(Theme.base))
                            .foregroundStyle(Theme.gray400)
                        Button("Try again") { Task { await load() } }
                            .buttonStyle(SoftPillStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.px(200))
                }
            }
            .padding(.vertical, Theme.px(40))
        }
        .scrollClipDisabled()
        .task { if rows.isEmpty { await load() } }
        .refreshOnReturn { await load() }
    }

    private func load() async {
        guard let client = session.client, let userId = session.userId else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            async let resume: ItemsResult = client.get("/UserItems/Resume", ["userId": userId, "Limit": "24", "MediaTypes": "Video"])
            async let nextUp: ItemsResult = client.get("/Shows/NextUp", ["userId": userId, "Limit": "24", "EnableResumable": "false"])
            async let views: ItemsResult = client.get("/UserViews", ["userId": userId])
            var built: [HomeRow] = []
            if let items = try? await resume.items, !items.isEmpty {
                built.append(HomeRow(id: "resume", title: "Continue watching", items: items, wide: true))
            }
            if let items = try? await nextUp.items, !items.isEmpty {
                built.append(HomeRow(id: "nextup", title: "Next up", items: items, wide: true))
            }
            rows = built
            let libraries = (try await views.items ?? []).filter(isBrowsable)
            // Each library's head, in the order the configuration lists them, as each arrives.
            await withTaskGroup(of: (Int, HomeRow?).self) { group in
                for (index, view) in libraries.enumerated() {
                    group.addTask {
                        let genre = await openingGenre(client, userId: userId, view: view)
                        let result: ItemsResult? = try? await client.get("/Items", [
                            "userId": userId,
                            "ParentId": view.id,
                            "IncludeItemTypes": libraryTypes(view),
                            "GenreIds": genre,
                            "Recursive": "true",
                            "Limit": "24",
                        ])
                        guard let items = result?.items, !items.isEmpty else { return (index, nil) }
                        return (index, HomeRow(id: view.id, title: view.name ?? "Library", items: items, library: view))
                    }
                }
                var heads: [Int: HomeRow] = [:]
                for await (index, row) in group {
                    heads[index] = row
                    rows = built + heads.keys.sorted().compactMap { heads[$0] }
                }
            }
        } catch let failure as JellyfinError where failure.status == 401 {
            session.expired()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ItemRow: View {
    let row: HomeRow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.px(12)) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).font(Theme.font(Theme.xl, .semibold))
                Spacer()
                if let library = row.library {
                    NavigationLink(value: Route.library(library)) {
                        Label("See all", systemImage: "chevron.right")
                            .labelStyle(TrailingIconLabel())
                    }
                    .buttonStyle(SoftPillStyle())
                }
            }
            .padding(.horizontal, pageMargin)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Theme.px(16)) {
                    ForEach(row.items) { item in
                        PosterLink(item: item, wide: row.wide)
                    }
                }
                .padding(.horizontal, pageMargin)
                .padding(.vertical, Theme.px(8))
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.px(6)) {
            configuration.title
            configuration.icon.font(.system(size: Theme.px(12), weight: .semibold))
        }
    }
}

/// A title's poster, or a still for what's under way, that opens its page.
struct PosterLink: View {
    @EnvironmentObject private var session: Session
    let item: Item
    var wide: Bool = false

    private var stillWide: Bool { wide || item.isEpisode }
    /// The web app's TV rows: 304 × 171 stills, 152 × 228 posters.
    private var size: CGSize {
        stillWide ? CGSize(width: Theme.px(304), height: Theme.px(171)) : CGSize(width: Theme.px(152), height: Theme.px(228))
    }

    private var imageURL: URL? {
        guard let client = session.client else { return nil }
        if stillWide, !item.isEpisode, let backdrop = client.backdrop(item, height: Int(size.height * 2)) {
            return backdrop
        }
        return client.poster(item, height: Int(size.height * 2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.px(8)) {
            NavigationLink(value: item.isFolder ? Route.library(item) : Route.item(item)) {
                ZStack(alignment: .bottom) {
                    RemoteImage(url: imageURL)
                        .frame(width: size.width, height: size.height)
                    if let progress = item.userData?.playedPercentage, progress > 0, item.userData?.played != true {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.white.opacity(0.3))
                                Rectangle().fill(Theme.brand500).frame(width: geometry.size.width * progress / 100)
                            }
                        }
                        .frame(height: Theme.px(4))
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.px(8), style: .continuous))
            }
            .buttonStyle(CardStyle())
            if stillWide {
                VStack(alignment: .leading, spacing: Theme.px(2)) {
                    Text(item.isEpisode ? (item.seriesName ?? item.displayTitle) : (item.name ?? ""))
                        .font(Theme.font(Theme.sm, .medium))
                        .lineLimit(1)
                    if item.isEpisode {
                        Text(item.displayTitle)
                            .font(Theme.font(Theme.xs))
                            .foregroundStyle(Theme.gray400)
                            .lineLimit(1)
                    }
                }
                .frame(width: size.width, alignment: .leading)
            }
        }
    }
}

/// An image that fills its frame, with a plain card while it loads or where there is none.
struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle().fill(Theme.gray900)
            }
        }
        .clipped()
    }
}

extension View {
    /// Loads again when the screen comes back, as watch state may have moved.
    func refreshOnReturn(_ action: @escaping () async -> Void) -> some View {
        modifier(RefreshOnReturn(action: action))
    }
}

private struct RefreshOnReturn: ViewModifier {
    let action: () async -> Void
    @State private var appeared = false

    func body(content: Content) -> some View {
        content.onAppear {
            if appeared { Task { await action() } }
            appeared = true
        }
    }
}

/// Posters in rows of six, which a page of items shows.
struct PosterGrid: View {
    let items: [Item]
    var onLast: (() -> Void)? = nil

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(Theme.px(152)), spacing: Theme.px(24)), count: 6),
            alignment: .leading,
            spacing: Theme.px(28)
        ) {
            ForEach(items) { item in
                PosterLink(item: item)
                    .onAppear { if item.id == items.last?.id { onLast?() } }
            }
        }
        .padding(.horizontal, pageMargin)
        .padding(.vertical, Theme.px(16))
    }
}

// MARK: - Discover

struct LibrariesView: View {
    @EnvironmentObject private var session: Session
    @State private var views: [Item] = []

    var body: some View {
        ScrollView {
            PageTitle(text: "Discover")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.px(16)), count: 4), spacing: Theme.px(16)) {
                ForEach(views) { view in
                    NavigationLink(value: Route.library(view)) {
                        Text(view.name ?? "Library")
                            .font(Theme.font(Theme.lg, .semibold))
                            .multilineTextAlignment(.center)
                            .padding(Theme.px(16))
                            .frame(maxWidth: .infinity, minHeight: Theme.px(96))
                    }
                    .buttonStyle(RowStyle())
                }
            }
            .padding(pageMargin)
        }
        .scrollClipDisabled()
        .task {
            guard let client = session.client, let userId = session.userId, views.isEmpty else { return }
            let result: ItemsResult? = try? await client.get("/UserViews", ["userId": userId])
            views = (result?.items ?? []).filter(isBrowsable)
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var session: Session
    let view: Item
    @State private var items: [Item] = []
    @State private var total = Int.max
    @State private var genre: String?
    @State private var loading = false
    @State private var started = false

    private static let page = 60

    var body: some View {
        ScrollView {
            PageTitle(text: view.name ?? "Library")
            PosterGrid(items: items) { Task { await more() } }
            if loading { ProgressView().padding() }
            if !loading && started && items.isEmpty {
                Text("Nothing in this library.").foregroundStyle(Theme.gray400)
            }
        }
        .scrollClipDisabled()
        .task {
            guard !started, let client = session.client, let userId = session.userId else { return }
            started = true
            genre = await openingGenre(client, userId: userId, view: view)
            await more()
        }
    }

    private func more() async {
        guard !loading, items.count < total, let client = session.client, let userId = session.userId else { return }
        loading = true
        defer { loading = false }
        let result: ItemsResult? = try? await client.get("/Items", [
            "userId": userId,
            "ParentId": view.id,
            "StartIndex": String(items.count),
            "Limit": String(Self.page),
            "IncludeItemTypes": view.type == "BoxSet" ? nil : libraryTypes(view),
            "GenreIds": genre,
            "Recursive": "true",
            "EnableTotalRecordCount": "true",
        ])
        let page = result?.items ?? []
        items.append(contentsOf: page.filter { new in !items.contains { $0.id == new.id } })
        total = page.isEmpty ? items.count : (result?.totalRecordCount ?? Int.max)
    }
}

// MARK: - Favourites

struct FavouritesView: View {
    @EnvironmentObject private var session: Session
    @State private var items: [Item] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            PageTitle(text: "Favourites")
            if loaded && items.isEmpty {
                Text("Titles you favourite show here.")
                    .font(Theme.font(Theme.base))
                    .foregroundStyle(Theme.gray400)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(pageMargin)
                    .focusable()
            }
            PosterGrid(items: items)
        }
        .scrollClipDisabled()
        .task { await load() }
        .refreshOnReturn { await load() }
    }

    private func load() async {
        guard let client = session.client, let userId = session.userId else { return }
        let result: ItemsResult? = try? await client.get("/Items", [
            "userId": userId,
            "Filters": "IsFavorite",
            "Recursive": "true",
            "IncludeItemTypes": "Movie,Series,Episode",
            "SortBy": "DatePlayed,SortName",
            "SortOrder": "Descending",
        ])
        items = result?.items ?? []
        loaded = true
    }
}

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject private var session: Session
    @State private var term = ""
    @State private var results: [Item] = []
    @State private var searching = false

    var body: some View {
        ScrollView {
            PosterGrid(items: results)
            if searching { ProgressView() }
            if !searching && term.count >= 2 && results.isEmpty {
                Text("No results for “\(term)”.").font(Theme.font(Theme.base)).foregroundStyle(Theme.gray400)
            }
        }
        .scrollClipDisabled()
        .searchable(text: $term, prompt: "Movies and shows")
        .task(id: term) {
            guard term.count >= 2 else {
                results = []
                return
            }
            // Waits for typing to pause.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let client = session.client, let userId = session.userId else { return }
            searching = true
            defer { searching = false }
            let result: ItemsResult? = try? await client.get("/Items", [
                "userId": userId,
                "SearchTerm": term,
                "Recursive": "true",
                "IncludeItemTypes": "Movie,Series",
                "Limit": "48",
            ])
            if !Task.isCancelled { results = result?.items ?? [] }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.px(24)) {
                PageTitle(text: "Settings").padding(.horizontal, -pageMargin)
                section("Account") {
                    fact("Server", session.serverName ?? session.client?.base.host ?? "")
                    fact("Signed in as", session.userName ?? "")
                    HStack(spacing: Theme.px(12)) {
                        Button("Sign out") { session.signOut() }.buttonStyle(SoftPillStyle())
                        Button("Change server") { session.forgetServer() }.buttonStyle(SoftPillStyle())
                    }
                }
                section("About") {
                    fact("App", "AIOStreams tvOS \(AppInfo.version)")
                    fact("Player", AppInfo.player)
                    Text("An unofficial app, not affiliated with AIOStreams or AetherEngine. AGPL-3.0; AetherEngine is LGPL-3.0, FFmpeg LGPL-2.1+, and the Inter font is under the SIL Open Font License.")
                        .font(Theme.font(Theme.sm))
                        .foregroundStyle(Theme.gray400)
                }
            }
            .padding(.horizontal, pageMargin)
            .frame(maxWidth: Theme.px(760), alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.px(12)) {
            Text(title).font(Theme.font(Theme.sm, .semibold)).foregroundStyle(Theme.gray400)
            VStack(alignment: .leading, spacing: Theme.px(12)) { content() }
                .padding(Theme.px(20))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.px(12)).fill(Theme.gray900))
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.gray400)
            Spacer()
            Text(value)
        }
        .font(Theme.font(Theme.base))
    }
}
