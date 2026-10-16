import AppKit
import SwiftUI

/// Fetches and caches site logos keyed by host. Disk cache lives next to the data file.
@MainActor
final class IconCache: ObservableObject {
    static let shared = IconCache()

    @Published private(set) var images: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private let dir: URL

    private init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextCharge/icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func image(for host: String) -> NSImage? { images[host] }

    func load(_ host: String) {
        guard host.contains("."), images[host] == nil, !inFlight.contains(host), !failed.contains(host) else { return }
        let file = dir.appendingPathComponent(host + ".png")
        if let img = NSImage(contentsOf: file) {
            images[host] = img
            return
        }
        inFlight.insert(host)
        Task {
            let data = await Self.fetchIcon(host: host)
            inFlight.remove(host)
            if let data, let img = NSImage(data: data) {
                images[host] = img
                if let png = Self.pngData(img) { try? png.write(to: file, options: .atomic) }
            } else {
                failed.insert(host)
            }
        }
    }

    // MARK: Fetching

    nonisolated private static func fetchIcon(host: String) async -> Data? {
        var hosts = [host]
        let root = registrableDomain(host)
        if root != host { hosts.append(root) }

        for h in hosts {
            // 1. Icons the page declares, best first.
            for url in await declaredIcons(host: h) {
                if let d = await fetchImage(url, minSide: 32) { return d }
            }
            // 2. Conventional location.
            if let d = await fetchImage(URL(string: "https://\(h)/apple-touch-icon.png")!, minSide: 32) { return d }
        }
        // 3. Google's favicon service, then plain favicon.ico.
        for h in hosts {
            if let d = await fetchImage(URL(string: "https://www.google.com/s2/favicons?domain=\(h)&sz=128")!, minSide: 32) { return d }
        }
        for h in hosts {
            if let d = await fetchImage(URL(string: "https://\(h)/favicon.ico")!, minSide: 16) { return d }
        }
        return nil
    }

    nonisolated private static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 8)
        r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                   forHTTPHeaderField: "User-Agent")
        return r
    }

    nonisolated private static func fetchImage(_ url: URL, minSide: CGFloat) async -> Data? {
        guard let (data, resp) = try? await URLSession.shared.data(for: request(url)),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let img = NSImage(data: data) else { return nil }
        let side = img.representations.map { CGFloat(max($0.pixelsWide, $0.pixelsHigh)) }.max() ?? img.size.width
        return side >= minSide ? data : nil
    }

    nonisolated private static func declaredIcons(host: String) async -> [URL] {
        guard let base = URL(string: "https://\(host)/"),
              let (data, resp) = try? await URLSession.shared.data(for: request(base)),
              let html = String(data: data.prefix(300_000), encoding: .utf8) else { return [] }
        let finalURL = resp.url ?? base

        guard let tagRe = try? NSRegularExpression(pattern: "<link[^>]+>", options: .caseInsensitive) else { return [] }
        var found: [(score: Int, url: URL)] = []
        for m in tagRe.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(m.range, in: html) else { continue }
            let tag = String(html[r])
            guard let rel = attr("rel", in: tag)?.lowercased(), rel.contains("icon"),
                  !rel.contains("mask"),
                  let href = attr("href", in: tag), !href.hasPrefix("data:"),
                  let url = URL(string: href, relativeTo: finalURL)?.absoluteURL else { continue }
            if href.lowercased().hasSuffix(".svg") { continue }  // NSImage SVG support is spotty
            var score = rel.contains("apple-touch") ? 1000 : 0
            if let sizes = attr("sizes", in: tag), let n = Int(sizes.split(separator: "x").first ?? "") { score += n }
            found.append((score, url))
        }
        return found.sorted { $0.score > $1.score }.map(\.url)
    }

    nonisolated private static func attr(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for i in 1...3 {
            if let r = Range(m.range(at: i), in: tag) { return String(tag[r]) }
        }
        return nil
    }

    /// "dash.cloudflare.com" -> "cloudflare.com", "www.coupang.co.kr" -> "coupang.co.kr"
    nonisolated static func registrableDomain(_ host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count > 2 else { return host }
        let secondLevel: Set<String> = ["co", "or", "go", "ac", "ne", "re", "com", "net", "org"]
        let keep = (parts.last!.count == 2 && secondLevel.contains(parts[parts.count - 2])) ? 3 : 2
        return parts.suffix(keep).joined(separator: ".")
    }

    nonisolated private static func pngData(_ img: NSImage) -> Data? {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Site logo when available, otherwise a colored first-letter badge.
struct SubscriptionIcon: View {
    @ObservedObject private var cache = IconCache.shared
    let sub: Subscription
    var size: CGFloat = 30

    var body: some View {
        let host = sub.logoHost
        Group {
            if let host, let img = cache.image(for: host) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08)))
                    .opacity(sub.status == .cancelled ? 0.4 : 1)
            } else {
                Monogram(name: sub.name, dimmed: sub.status == .cancelled, size: size)
            }
        }
        .task(id: host) { if let host { cache.load(host) } }
    }
}
