import Foundation

/// One cancellable, deduplicated head start. It never loads or starts the next video.
@MainActor
final class NextEpisodePreloader {
    private let warm: @Sendable (URL, [String: String]) async -> Void
    private var task: Task<Void, Never>?
    private var address: String?
    private var headers: [String: String] = [:]

    init(warm: @escaping @Sendable (URL, [String: String]) async -> Void) {
        self.warm = warm
    }

    func prepare(_ address: String?, headers: [String: String], allowed: Bool) {
        guard allowed, let address, let url = URL(string: address),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { cancel(); return }
        guard address != self.address || headers != self.headers else { return }
        cancel()
        self.address = address
        self.headers = headers
        let warm = self.warm
        task = Task.detached(priority: .utility) { await warm(url, headers) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        address = nil
        headers = [:]
    }

    deinit { task?.cancel() }
}
