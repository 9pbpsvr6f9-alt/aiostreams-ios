import Foundation

/// Screenshot mode, for the README's pictures: launched with these arguments, the web app finds
/// itself signed in to the demo server (tools/demo-server) and opens one page, so a simulator can
/// photograph it.
///
///     -demoServer http://127.0.0.1:8096/jellyfin -demoServerId <id> -demoUserId <id> -demoToken <token>
///     -demoRoute /item/<id>          a page of the web app, as its address after the #
///
/// Without `-demoServer` none of this runs.
enum DemoMode {
    private static var defaults: UserDefaults { .standard }

    /// Saves the demo server and its sign-in where the web app keeps them (lib/servers.ts,
    /// lib/credentials.ts), before the page reads them.
    static var storageScript: String? {
        guard let server = defaults.string(forKey: "demoServer"),
              let serverId = defaults.string(forKey: "demoServerId"),
              let userId = defaults.string(forKey: "demoUserId"),
              let token = defaults.string(forKey: "demoToken") else { return nil }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let servers: [[String: Any]] = [["base": server, "name": "Demo Server", "logo": NSNull(), "lastUsed": now]]
        let credentials: [String: Any] = ["Servers": [[
            "Id": serverId, "ManualAddress": server, "AccessToken": token, "UserId": userId,
            "DateLastAccessed": now, "LastConnectionMode": 2,
        ]]]
        guard let serversJSON = JSON.encode(["v": servers]), let credentialsJSON = JSON.encode(credentials),
              let serverJSON = JSON.encode(["v": server]) else { return nil }
        return """
        (() => {
          try {
            localStorage.setItem('aiostreams-web-servers', JSON.stringify(\(serversJSON).v));
            localStorage.setItem('aiostreams-web-server', JSON.stringify(\(serverJSON).v));
            localStorage.setItem('jellyfin_credentials', JSON.stringify(\(credentialsJSON)));
          } catch {}
        })();
        """
    }

    /// The bundled page at the route the launch asked for.
    static var startURL: URL? {
        guard defaults.string(forKey: "demoServer") != nil else { return nil }
        let route = defaults.string(forKey: "demoRoute") ?? "/"
        return URL(string: "\(WebAssets.startURL.absoluteString)#\(route)")
    }
}
