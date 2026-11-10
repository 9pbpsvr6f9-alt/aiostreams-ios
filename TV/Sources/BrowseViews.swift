import SwiftUI

/// Where a tapped item leads: a title's page, or a library's grid.
enum Route: Hashable {
    case item(Item)
    case library(Item)
}

struct MainView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        TabView {
            NavigationStack { HomeView().routes() }
                .tabItem { Text("Home") }
            NavigationStack { SearchView().routes() }
                .tabItem { Text("Search") }
            NavigationStack { LibrariesView().routes() }
                .tabItem { Text("Libraries") }
            NavigationStack { SettingsView() }
                .tabItem { Text("Settings") }
        }
    }
}

extension View {
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .item(let item): DetailView(item: item)
            case .library(let view): LibraryView(view: view)
            }
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

// MARK: - Home

struct HomeRow: Identifiable {
    let id: String
    let title: String
    let items: [Item]
    var library: Item?
}

struct HomeView: View {
    @EnvironmentObject private var session: Session
    @State private var rows: [HomeRow] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                ForEach(rows) { row in
                    ItemRow(row: row)
                }
                if loading && rows.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                if !loading && rows.isEmpty {
                    VStack(spacing: 20) {
                        Text(error ?? "Nothing here yet. Add catalogs to your configuration.")
                            .foregroundStyle(.secondary)
                        Button("Try again") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 40)
        }
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
                built.append(HomeRow(id: "resume", title: "Continue Watching", items: items))
            }
            if let items = try? await nextUp.items, !items.isEmpty {
                built.append(HomeRow(id: "nextup", title: "Next Up", items: items))
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(row.title).font(.title3).bold()
                if let library = row.library {
                    NavigationLink(value: Route.library(library)) {
                        Text("See all").font(.callout)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 40) {
                    ForEach(row.items) { item in
                        PosterLink(item: item)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

/// A title's poster, or an episode's still, that opens its page.
struct PosterLink: View {
    @EnvironmentObject private var session: Session
    let item: Item

    private var wide: Bool { item.isEpisode }
    private var size: CGSize { wide ? CGSize(width: 480, height: 270) : CGSize(width: 250, height: 375) }

    var body: some View {
        NavigationLink(value: item.isFolder ? Route.library(item) : Route.item(item)) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: session.client?.poster(item, height: Int(size.height * 2)))
                    .frame(width: size.width, height: size.height)
                if let progress = item.userData?.playedPercentage, progress > 0, item.userData?.played != true {
                    GeometryReader { geometry in
                        Capsule().fill(.white.opacity(0.3))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white).frame(width: geometry.size.width * progress / 100)
                            }
                    }
                    .frame(height: 6)
                    .padding(12)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .buttonStyle(.card)
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.isEpisode ? (item.seriesName ?? item.displayTitle) : (item.name ?? ""))
                    .font(.caption)
                    .lineLimit(1)
                if item.isEpisode {
                    Text(item.displayTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: size.width, alignment: .leading)
            .offset(y: item.isEpisode ? 70 : 44)
        }
        .padding(.bottom, item.isEpisode ? 70 : 44)
    }
}

/// An image that fills its frame, with a plain card while it loads or where there is none.
struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle().fill(Color.white.opacity(0.08))
                    .overlay { Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary) }
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

// MARK: - Libraries

struct LibrariesView: View {
    @EnvironmentObject private var session: Session
    @State private var views: [Item] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 40), count: 4), spacing: 40) {
                ForEach(views) { view in
                    NavigationLink(value: Route.library(view)) {
                        Text(view.name ?? "Library")
                            .font(.title3)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(80)
        }
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
            Text(view.name ?? "Library").font(.title2).bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 80)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(250), spacing: 50), count: 6), spacing: 60) {
                ForEach(items) { item in
                    PosterLink(item: item)
                        .onAppear { if item.id == items.last?.id { Task { await more() } } }
                }
            }
            .padding(60)
            if loading { ProgressView() }
            if !loading && started && items.isEmpty {
                Text("Nothing in this library.").foregroundStyle(.secondary)
            }
        }
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

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject private var session: Session
    @State private var term = ""
    @State private var results: [Item] = []
    @State private var searching = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(250), spacing: 50), count: 6), spacing: 60) {
                ForEach(results) { item in PosterLink(item: item) }
            }
            .padding(60)
            if searching { ProgressView() }
            if !searching && term.count >= 2 && results.isEmpty {
                Text("No results for “\(term)”.").foregroundStyle(.secondary)
            }
        }
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
        List {
            Section("Account") {
                LabeledContent("Server", value: session.serverName ?? session.client?.base.host ?? "")
                LabeledContent("Signed in as", value: session.userName ?? "")
                Button("Sign out") { session.signOut() }
                Button("Use a different server", role: .destructive) { session.forgetServer() }
            }
            Section("About") {
                LabeledContent("App", value: "AIOStreams tvOS \(AppInfo.version)")
                LabeledContent("Player", value: AppInfo.player)
                Text("An unofficial app, not affiliated with AIOStreams or AetherEngine. AGPL-3.0; AetherEngine is LGPL-3.0 and FFmpeg LGPL-2.1+.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 1200)
    }
}
