import Foundation

// The subset of the Jellyfin API an AIOStreams server speaks that the web app itself uses
// (packages/web/src/lib/queries.ts), with the server's `aiostreams` extension fields.

struct UserData: Decodable, Hashable {
    var playbackPositionTicks: Int64?
    var playedPercentage: Double?
    var played: Bool?
    var isFavorite: Bool?
    var unplayedItemCount: Int?
}

struct ItemExtension: Decodable, Hashable {
    var genreRequired: Bool?
}

struct Item: Decodable, Identifiable, Hashable {
    var id: String
    var name: String?
    var type: String?
    var seriesName: String?
    var seriesId: String?
    var seasonId: String?
    var indexNumber: Int?
    var parentIndexNumber: Int?
    var overview: String?
    var productionYear: Int?
    var runTimeTicks: Int64?
    var officialRating: String?
    var communityRating: Double?
    var genres: [String]?
    var collectionType: String?
    var imageTags: [String: String]?
    var backdropImageTags: [String]?
    var parentBackdropItemId: String?
    var parentBackdropImageTags: [String]?
    var seriesPrimaryImageTag: String?
    var parentThumbItemId: String?
    var parentThumbImageTag: String?
    var userData: UserData?
    var aiostreams: ItemExtension?

    /// An image tag by Jellyfin's type name. The decoder's key strategy also lowers the first
    /// letter of dictionary keys, so `ImageTags.Primary` arrives as `primary`.
    func tag(_ kind: String) -> String? {
        imageTags?[kind.prefix(1).lowercased() + kind.dropFirst()] ?? imageTags?[kind]
    }

    var isEpisode: Bool { type == "Episode" }
    var isSeries: Bool { type == "Series" }
    var isFolder: Bool { type == "CollectionFolder" || type == "BoxSet" || type == "Folder" }

    /// Where playback picks up, unless it was watched to the end.
    var resumeMs: Double? {
        guard userData?.played != true, let ticks = userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return Double(ticks) / 10_000
    }

    var runtimeMinutes: Int? {
        runTimeTicks.map { Int($0 / 600_000_000) }.flatMap { $0 > 0 ? $0 : nil }
    }

    /// "S1:E4 · Name" for an episode, the name otherwise.
    var displayTitle: String {
        guard isEpisode else { return name ?? "" }
        var prefix = ""
        if let season = parentIndexNumber, let episode = indexNumber { prefix = "S\(season):E\(episode)" }
        else if let episode = indexNumber { prefix = "E\(episode)" }
        return [prefix, name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct ItemsResult: Decodable {
    var items: [Item]?
    var totalRecordCount: Int?
}

struct SourceExtension: Decodable, Hashable {
    /// The version's own id; the first version otherwise carries the item's.
    var id: String?
    var name: String?
    var description: String?
    var ytId: String?
}

struct MediaStream: Decodable, Hashable {
    var type: String?
    var index: Int?
    var displayTitle: String?
    var title: String?
    var language: String?
    var codec: String?
    var isExternal: Bool?
    var isForced: Bool?
    var deliveryUrl: String?
}

struct MediaSource: Decodable, Identifiable, Hashable {
    var id: String
    var name: String?
    var path: String?
    var size: Int64?
    var container: String?
    var requiredHttpHeaders: [String: String]?
    var mediaStreams: [MediaStream]?
    var aiostreams: SourceExtension?

    /// The web app keys every version by its own id.
    var ownId: String { aiostreams?.id ?? id }
    var label: String { aiostreams?.name ?? name ?? "Version" }
}

struct PlaybackInfo: Decodable {
    var mediaSources: [MediaSource]?
    var playSessionId: String?
    var errorCode: String?
}

struct PublicSystemInfo: Decodable {
    var serverName: String?
    var version: String?
}

struct PublicUser: Decodable, Identifiable, Hashable {
    var id: String
    var name: String?
    var hasPassword: Bool?
    var primaryImageTag: String?
}

struct AuthResult: Decodable {
    struct User: Decodable {
        var id: String
        var name: String?
    }

    var accessToken: String
    var user: User
}

struct QuickConnectState: Decodable {
    var secret: String
    var code: String?
    var authenticated: Bool?
}

struct JellyfinError: LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { message }
}

/// A minimal client for the Jellyfin API this server speaks.
struct JellyfinClient: Sendable {
    let base: URL
    var token: String?
    let deviceId: String
    let deviceName: String

    static let clientName = "AIOStreams tvOS"
    static let ticksPerMs: Double = 10_000

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Jellyfin names fields in PascalCase.
        decoder.keyDecodingStrategy = .custom { path in
            let key = path.last!.stringValue
            return AnyKey(key.prefix(1).lowercased() + key.dropFirst())
        }
        return decoder
    }()

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// What a person types: a bare host, a full address, or the web app's own `/web` page.
    static func normalize(_ address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text), components.host != nil else { return nil }
        // Kept encoded: a picker address carries an encrypted password that may hold an encoded slash.
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased().hasSuffix("/web") { path.removeLast(4) }
        // A server's root holds the API under /jellyfin, as the web app reads it.
        components.percentEncodedPath = path.isEmpty ? "/jellyfin" : path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    var authorization: String {
        var parts = [
            "Client=\"\(Self.clientName)\"",
            "Device=\"\(deviceName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "AppleTV")\"",
            "DeviceId=\"\(deviceId)\"",
            "Version=\"\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")\"",
        ]
        if let token { parts.append("Token=\"\(token)\"") }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    func url(_ path: String, _ query: [String: String?] = [:]) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath += path
        let items = query.compactMap { key, value in value.flatMap { $0.isEmpty ? nil : URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        return components.url!
    }

    func get<T: Decodable>(_ path: String, _ query: [String: String?] = [:]) async throws -> T {
        try await send("GET", path, query: query, body: nil)
    }

    func post<T: Decodable>(_ path: String, _ query: [String: String?] = [:], body: [String: Any]? = nil) async throws -> T {
        try await send("POST", path, query: query, body: body)
    }

    /// A request whose answer has no body worth reading.
    func call(_ method: String, _ path: String, _ query: [String: String?] = [:]) async throws {
        _ = try await raw(method, path, query: query, body: nil)
    }

    /// For reports whose answer nobody reads.
    func fire(_ path: String, body: [String: Any]) async {
        _ = try? await raw("POST", path, query: [:], body: body)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, query: [String: String?], body: [String: Any]?) async throws -> T {
        let data = try await raw(method, path, query: query, body: body)
        do {
            return try Self.decoder.decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
        } catch {
            AppLog.warn("api", "\(path): could not read the answer: \(error)")
            throw JellyfinError(status: 0, message: "The server sent something unexpected.")
        }
    }

    private func raw(_ method: String, _ path: String, query: [String: String?], body: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: url(path, query))
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw JellyfinError(status: 0, message: "Can't reach the server.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message: String
            switch status {
            case 401: message = "Signed out. Sign in again."
            case 403: message = "The server refused this."
            case 404: message = "Not found on this server."
            case 429: message = "Too many requests. Try again shortly."
            default: message = "Request failed (\(status))."
            }
            throw JellyfinError(status: status, message: message)
        }
        return data
    }

    // MARK: - Images

    enum ImageKind: String { case primary = "Primary", backdrop = "Backdrop", thumb = "Thumb" }

    func image(_ itemId: String, _ kind: ImageKind, tag: String?, height: Int) -> URL {
        let path = kind == .backdrop ? "/Items/\(itemId)/Images/Backdrop/0" : "/Items/\(itemId)/Images/\(kind.rawValue)"
        return url(path, ["tag": tag, "fillHeight": String(height), "quality": "90"])
    }

    /// A portrait poster for titles, a still for episodes.
    func poster(_ item: Item, height: Int) -> URL? {
        if item.isEpisode {
            if let tag = item.tag("Primary") { return image(item.id, .primary, tag: tag, height: height) }
            if let id = item.parentThumbItemId { return image(id, .thumb, tag: item.parentThumbImageTag, height: height) }
            if let id = item.seriesId { return image(id, .primary, tag: item.seriesPrimaryImageTag, height: height) }
            return nil
        }
        return image(item.id, .primary, tag: item.tag("Primary"), height: height)
    }

    func backdrop(_ item: Item, height: Int) -> URL? {
        if let tag = item.backdropImageTags?.first { return image(item.id, .backdrop, tag: tag, height: height) }
        if let id = item.parentBackdropItemId { return image(id, .backdrop, tag: item.parentBackdropImageTags?.first, height: height) }
        if let id = item.seriesId { return image(id, .backdrop, tag: nil, height: height) }
        return nil
    }

    // MARK: - Playback

    /// Every file plays as it is; text subtitles come as WebVTT addresses.
    private static let deviceProfile: [String: Any] = [
        "DirectPlayProfiles": [["Type": "Video"]],
        "SubtitleProfiles": [["Format": "vtt", "Method": "External"]],
    ]

    /// The version list, or with `sourceId` one version with its subtitles from subtitle addons.
    func playbackInfo(userId: String, itemId: String, sourceId: String? = nil, refresh: Bool = false) async throws -> PlaybackInfo {
        var body: [String: Any] = [
            "UserId": userId,
            "DeviceProfile": Self.deviceProfile,
            "EnableRequiredHttpHeaders": true,
        ]
        if let sourceId {
            body["MediaSourceId"] = sourceId
        } else {
            body["Fresh"] = true
            body["SkipSubtitles"] = true
        }
        if refresh { body["Refresh"] = true }
        return try await post("/Items/\(itemId)/PlaybackInfo", ["userId": userId], body: body)
    }

    /// The version's own address where it has one, which outlives this session; the stream route otherwise.
    func streamURL(itemId: String, source: MediaSource) -> URL? {
        if let path = source.path, let url = URL(string: path), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }
        return url("/Videos/\(itemId)/stream", ["static": "true", "MediaSourceId": source.ownId, "ApiKey": token])
    }

    /// A subtitle's address, which the server gives relative to its API.
    func absolute(_ deliveryUrl: String) -> URL? {
        if let url = URL(string: deliveryUrl), url.scheme != nil { return url }
        var text = base.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text + (deliveryUrl.hasPrefix("/") ? "" : "/") + deliveryUrl)
    }
}
