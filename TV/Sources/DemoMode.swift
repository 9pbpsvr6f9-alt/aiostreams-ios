import SwiftUI

/// Screenshot mode, for the README's pictures: launched with these arguments, the app signs in to
/// the demo server (tools/demo-server) and opens one screen, so a simulator can photograph it
/// without anyone holding a remote.
///
///     -demoServer http://127.0.0.1:8096/jellyfin -demoScreen home|rail|title|movie|versions|player|settings|signin
///     -demoItem <id>        the title a screen opens
///     -demoUser Alex        who signs in
///
/// Without `-demoServer` none of this runs.
enum DemoMode {
    static var server: String? { UserDefaults.standard.string(forKey: "demoServer") }
    static var screen: String { UserDefaults.standard.string(forKey: "demoScreen") ?? "home" }
    static var itemId: String? { UserDefaults.standard.string(forKey: "demoItem") }
    static var user: String { UserDefaults.standard.string(forKey: "demoUser") ?? "Alex" }

    static var active: Bool { server != nil }

    /// Keeps the player's controls in sight for the photograph.
    static var holdsControls: Bool { active && screen == "player" }

    /// Connects to the demo server and, unless the screen is the sign-in, signs in.
    @MainActor
    static func start(_ session: Session) async {
        guard let server else { return }
        session.forgetServer()
        do {
            try await session.connect(to: server)
            guard screen != "signin", let client = session.client else { return }
            let result: AuthResult = try await client.post("/Users/AuthenticateByName", body: ["Username": user, "Pw": ""])
            session.signIn(result)
        } catch {
            AppLog.warn("demo", "couldn't reach the demo server: \(error.localizedDescription)")
        }
    }

    /// The title the screen opens, from the demo server.
    @MainActor
    static func item(_ session: Session) async -> Item? {
        guard let itemId, let client = session.client, let userId = session.userId else { return nil }
        let found: ItemsResult? = try? await client.get("/Items", ["userId": userId, "Ids": itemId])
        return found?.items?.first
    }
}
