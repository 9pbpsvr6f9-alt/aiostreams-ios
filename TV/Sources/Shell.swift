import SwiftUI

/// The places the rail leads to, in the web app's order (components/layout.tsx).
enum Place: String, CaseIterable, Identifiable {
    case account, home, discover, search, favourites, calendar, activity, settings

    var id: String { rawValue }

    static let main: [Place] = [.home, .discover, .search, .favourites, .calendar, .activity]

    var name: String {
        switch self {
        case .account: return "You"
        case .home: return "Home"
        case .discover: return "Discover"
        case .search: return "Search"
        case .favourites: return "Favourites"
        case .calendar: return "Calendar"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    /// SF Symbols standing in for the web app's BoxIcons.
    var icon: String {
        switch self {
        case .account: return "person.crop.circle"
        case .home: return "house"
        case .discover: return "safari"
        case .search: return "magnifyingglass"
        case .favourites: return "heart"
        case .calendar: return "calendar"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

/// The web app's TV layout with its default navigation, the docked rail: icons down the
/// side that open out with names, over a shade, while the rail has focus.
struct MainView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var prefs: Preferences
    @State private var place: Place = .home
    @State private var paths: [Place: NavigationPath] = [:]
    @FocusState private var railFocus: Place?
    /// What a card's menu asked to play, from any page.
    @State private var choice: VersionChoice?
    @Namespace private var railScope

    private var open: Bool { railFocus != nil }

    private func path(_ place: Place) -> Binding<NavigationPath> {
        Binding(get: { paths[place] ?? NavigationPath() }, set: { paths[place] = $0 })
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.background.ignoresSafeArea()

            NavigationStack(path: path(place)) {
                page(place)
                    .routes()
                    .toolbar(.hidden, for: .navigationBar)
            }
            .id(place)
            // One area the focus can move into from the rail, wherever on the page it lands.
            .focusSection()
            .environment(\.openPlace, { place = $0 })
            .environment(\.openRoute, { route in
                var path = paths[place] ?? NavigationPath()
                path.append(route)
                paths[place] = path
            })
            .environment(\.playItem, { item in
                Task { choice = await playChoice(for: item, session: session) }
            })
            .padding(.leading, Theme.px(80))

            // The rail's own column, which rows scrolled under it disappear beneath.
            Theme.background
                .frame(width: Theme.px(80))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // The open rail's shade over the page beside it.
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.85), location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: Theme.px(576))
            .opacity(open ? 1 : 0)
            .allowsHitTesting(false)
            .ignoresSafeArea()

            rail
        }
        .ignoresSafeArea()
        .font(Theme.font(Theme.base))
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.2), value: open)
        .playFlow($choice) { NotificationCenter.default.post(name: .watchStateChanged, object: nil) }
        .task {
            guard let client = session.client, let userId = session.userId else { return }
            await prefs.load(client: client, userId: userId)
        }
        // Back from another place's first page goes Home; from Home, it leaves the app.
        .onExitCommand(perform: place != .home && (paths[place]?.isEmpty ?? true) ? { place = .home } : nil)
    }

    @ViewBuilder private func page(_ place: Place) -> some View {
        switch place {
        case .home: HomeView()
        case .discover: LibrariesView()
        case .search: SearchView()
        case .favourites: FavouritesView()
        case .calendar: CalendarView()
        case .activity: ActivityView()
        case .account, .settings: SettingsView()
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: Theme.px(4)) {
            BrandLogo(height: Theme.px(32))
                .frame(width: Theme.px(24), height: Theme.px(32))
                .padding(.horizontal, Theme.px(14))
                .padding(.bottom, Theme.px(24))
            entry(.account)
            Rectangle().fill(.white.opacity(0.1)).frame(height: Theme.px(1))
                .padding(.horizontal, Theme.px(12))
                .padding(.vertical, Theme.px(4))
            ForEach(Place.main) { entry($0) }
            Spacer(minLength: 0)
            entry(.settings)
        }
        .padding(.horizontal, Theme.px(12))
        .padding(.vertical, Theme.px(32))
        // The rail keeps its icons' width when it opens: its names are drawn beside the buttons,
        // not in them, so the page stays to their right and a press right reaches it.
        .frame(width: Theme.px(80), alignment: .leading)
        .frame(maxHeight: .infinity)
        .focusSection()
        .focusScope(railScope)
    }

    private func entry(_ item: Place) -> some View {
        let current = item == place || (item == .settings && place == .account)
        return Button {
            if item == place {
                // Choosing the place you're on goes back to its first page.
                paths[item] = NavigationPath()
            }
            place = item
        } label: {
            RailEntry(item: item, current: current, open: open, avatar: avatarURL)
        }
        .buttonStyle(RailButtonStyle())
        .focused($railFocus, equals: item)
        .prefersDefaultFocus(current, in: railScope)
    }

    private var avatarURL: URL? {
        guard let client = session.client, let userId = session.userId else { return nil }
        return client.url("/Users/\(userId)/Images/Primary", ["fillHeight": "96", "quality": "90"])
    }
}

private struct RailButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// One rail button: 48 px high and fully rounded, the current place filled, the focused one lighter.
private struct RailEntry: View {
    @Environment(\.isFocused) private var focused
    let item: Place
    let current: Bool
    let open: Bool
    let avatar: URL?

    /// An open entry's pill, icon and name together, as the web app's open rail draws it.
    private static let openWidth = Theme.px(232)
    private static let width = Theme.px(56)

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if item == .account {
                    AsyncImage(url: avatar) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "person.crop.circle.fill").resizable()
                        }
                    }
                    .frame(width: Theme.px(24), height: Theme.px(24))
                    .clipShape(Circle())
                } else {
                    Image(systemName: item.icon)
                        .font(.system(size: Theme.px(20), weight: current ? .semibold : .regular))
                }
            }
            .frame(width: Theme.px(24))
        }
        .padding(.horizontal, Theme.px(16))
        .frame(width: Self.width, height: Theme.px(48), alignment: .leading)
        .foregroundStyle(current || focused ? Color.white : Theme.gray400)
        // Drawn past the button's own frame, which focus moves are measured from.
        .background(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity((current ? 0.1 : 0) + (focused ? 0.2 : 0)))
                .frame(width: open ? Self.openWidth : Self.width, height: Theme.px(48))
        }
        .overlay(alignment: .leading) {
            if open {
                Text(item.name)
                    .font(Theme.font(Theme.base, .medium))
                    .foregroundStyle(current || focused ? Color.white : Theme.gray400)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: Theme.px(56))
                    .transition(.opacity)
            }
        }
    }
}

/// A place whose page comes in a later build.
struct ComingSoonView: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.px(12)) {
            Text(title).font(Theme.font(Theme.xl3, .bold))
            Text(text).font(Theme.font(Theme.base)).foregroundStyle(Theme.gray400)
            Text("Coming in a later build.").font(Theme.font(Theme.sm)).foregroundStyle(Theme.gray500)
        }
        .padding(Theme.px(40))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Keeps focus somewhere on a page with nothing to press.
        .focusable()
    }
}
