import SwiftUI

/// Something to play: an item, from where it would start. A show plays its next episode.
struct VersionChoice: Identifiable {
    let id = UUID()
    let item: Item
    let startMs: Double?
}

/// Lists a choice's versions, then plays the one picked, over whatever screen asked.
struct PlayFlow: ViewModifier {
    @EnvironmentObject private var session: Session
    @Binding var choice: VersionChoice?
    var finished: () -> Void = {}

    @State private var playing: PlayRequest?
    /// Waits for the version sheet to close, as one screen can't open over another closing.
    @State private var pendingPlay: PlayRequest?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $choice, onDismiss: {
                if let request = pendingPlay {
                    pendingPlay = nil
                    playing = request
                }
            }) { choice in
                VersionsView(choice: choice) { request in
                    pendingPlay = request
                    self.choice = nil
                }
                .environmentObject(session)
                // The page stays in sight, dimmed, behind the panel.
                .presentationBackground(.clear)
            }
            .fullScreenCover(item: $playing) { request in
                PlayerScreen(request: request) {
                    playing = nil
                    finished()
                }
                .environmentObject(session)
            }
    }
}

extension View {
    func playFlow(_ choice: Binding<VersionChoice?>, finished: @escaping () -> Void = {}) -> some View {
        modifier(PlayFlow(choice: choice, finished: finished))
    }
}

/// What playing a title means: a show's next episode, else the title from where it stopped.
@MainActor
func playChoice(for item: Item, session: Session) async -> VersionChoice? {
    guard item.isSeries else { return VersionChoice(item: item, startMs: item.resumeMs) }
    guard let client = session.client, let userId = session.userId else { return nil }
    let next: ItemsResult? = try? await client.get("/Shows/NextUp", ["userId": userId, "SeriesId": item.id, "Limit": "1"])
    if let episode = next?.items?.first { return VersionChoice(item: episode, startMs: episode.resumeMs) }
    let first: ItemsResult? = try? await client.get("/Shows/\(item.id)/Episodes", ["userId": userId, "Limit": "1"])
    return first?.items?.first.map { VersionChoice(item: $0, startMs: nil) }
}

/// Lets a page switch the rail's place, as the Continue watching row's Activity button does.
private struct OpenPlaceKey: EnvironmentKey {
    static let defaultValue: (Place) -> Void = { _ in }
}

extension EnvironmentValues {
    var openPlace: (Place) -> Void {
        get { self[OpenPlaceKey.self] }
        set { self[OpenPlaceKey.self] = newValue }
    }
}

/// What the player is asked to play: an item, from a position, in a chosen version.
struct PlayRequest: Identifiable {
    let id = UUID()
    let item: Item
    let source: MediaSource
    let playSessionId: String?
    let startMs: Double?
}
