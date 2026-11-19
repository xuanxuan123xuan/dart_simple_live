import Foundation

struct TVOSVersion: Comparable, Sendable {
    private let components: [UInt]

    init?(_ value: String) {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        let numbers = segments.compactMap { segment -> UInt? in
            guard !segment.isEmpty, segment.utf8.allSatisfy({ (48...57).contains($0) }) else {
                return nil
            }
            return UInt(segment)
        }
        guard numbers.count == segments.count else { return nil }
        components = numbers
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

struct TVOSRelease: Equatable, Sendable {
    private static let tagPrefix = "tvos-native-v"
    private let tag: String
    let version: TVOSVersion

    init?(stableTag tag: String) {
        guard tag.hasPrefix(Self.tagPrefix),
              let version = TVOSVersion(String(tag.dropFirst(Self.tagPrefix.count))) else { return nil }
        self.tag = tag
        self.version = version
    }

    var versionName: String { String(tag.dropFirst(Self.tagPrefix.count)) }
    var pageURL: URL { TVOSReleaseService.repositoryURL.appendingPathComponent("releases/tag/\(tag)") }
}

struct TVOSReleaseService: Sendable {
    private static let repository = "xuanxuan123xuan/dart_simple_live"
    fileprivate static let repositoryURL = URL(string: "https://github.com/\(repository)")!
    private static let releasesAPI = URL(string: "https://api.github.com/repos/\(repository)/releases")!

    private let load: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(session: URLSession = .shared) {
        self.init { request in try await session.data(for: request) }
    }

    init(load: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.load = load
    }

    func latestStableRelease() async throws -> TVOSRelease? {
        var page = 1
        var latest: TVOSRelease?
        while true {
            try Task.checkCancellation()
            var request = URLRequest(
                url: Self.releasesAPI.appending(queryItems: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page)),
                ]),
                timeoutInterval: 15
            )
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("SimpleLiveTVOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await load(request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            let candidate = releases.compactMap(\.stableTVOSRelease).max { $0.version < $1.version }
            if let candidate, latest.map({ $0.version < candidate.version }) ?? true {
                latest = candidate
            }
            guard response.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") == true else {
                return latest
            }
            page += 1
        }
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool

        var stableTVOSRelease: TVOSRelease? {
            guard !draft, !prerelease else { return nil }
            return TVOSRelease(stableTag: tag_name)
        }
    }
}
