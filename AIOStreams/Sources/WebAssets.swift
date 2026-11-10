import Foundation
import WebKit

/// Serves the bundled web app at `aiostreams://localhost/`, the origin the Mac app gives it too.
final class WebAssets: NSObject, WKURLSchemeHandler {
    static let scheme = "aiostreams"
    static let origin = "aiostreams://localhost"
    static let startURL = URL(string: "\(origin)/index.html")!

    private let root: URL?
    private let thumbnails: ThumbnailStore

    init(thumbnails: ThumbnailStore) {
        root = Bundle.main.resourceURL?.appendingPathComponent("web", isDirectory: true).standardizedFileURL
        self.thumbnails = thumbnails
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            return task.didFailWithError(URLError(.badURL))
        }
        let path = url.path.isEmpty ? "/" : url.path
        if path.hasPrefix("/thumbnail/"), let data = thumbnails.get(path) {
            return respond(task, url: url, status: 200, type: "image/jpeg", data: data)
        }
        guard let root else {
            return respond(task, url: url, status: 500, type: "text/plain", data: Data("The web app is missing from this build.".utf8))
        }
        var relative = String(path.drop(while: { $0 == "/" }))
        if relative.isEmpty { relative = "index.html" }
        var file = root.appendingPathComponent(relative).standardizedFileURL
        // Nothing outside the bundled folder is served.
        guard file.path.hasPrefix(root.path + "/") else {
            return respond(task, url: url, status: 403, type: "text/plain", data: Data())
        }
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) || isDirectory.boolValue {
            // A route the page draws itself rather than a file.
            guard file.pathExtension.isEmpty else {
                return respond(task, url: url, status: 404, type: "text/plain", data: Data())
            }
            file = root.appendingPathComponent("index.html")
        }
        guard let data = try? Data(contentsOf: file) else {
            return respond(task, url: url, status: 404, type: "text/plain", data: Data())
        }
        respond(task, url: url, status: 200, type: Self.mimeType(file.pathExtension), data: data)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, type: String, data: Data) {
        let headers = [
            "Content-Type": type,
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
            "Access-Control-Allow-Origin": "*",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            return task.didFailWithError(URLError(.cannotParseResponse))
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private static func mimeType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "map": return "application/json"
        case "webmanifest": return "application/manifest+json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "wasm": return "application/wasm"
        case "txt": return "text/plain; charset=utf-8"
        case "mp3": return "audio/mpeg"
        case "ogg": return "audio/ogg"
        case "wav": return "audio/wav"
        default: return "application/octet-stream"
        }
    }
}
