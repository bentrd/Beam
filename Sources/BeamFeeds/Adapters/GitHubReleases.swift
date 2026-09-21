import BeamModels
import Foundation

/// A repository's releases through GitHub's own Atom feed.
public enum GitHubReleases {
    public static func candidate(owner: String, repository: String) -> SourceCandidate? {
        guard let site = URL(string: "https://github.com/\(owner)/\(repository)") else { return nil }
        return SourceCandidate(kind: .githubReleases, title: "\(repository) releases",
                               feedURL: site.appendingPathComponent("releases.atom"), siteURL: site)
    }

    /// The repository name of a releases feed, for `Item.repoName`: a release titled "v0.30.6" says nothing to the
    /// judge until it reads "mlx v0.30.6" (EVIDENCE.md, risk 1). `FeedItem` has no field for it, so whoever turns
    /// feed items into stored items asks here (or reads `SourceRefresh.repoName`).
    public static func repoName(feedURL: URL) -> String? {
        guard feedURL.bareHost == "github.com", feedURL.lastPathComponent == "releases.atom" else { return nil }
        return repository(in: feedURL)?.name
    }

    /// First path segments that are GitHub's own pages, not accounts.
    private static let reservedOwners: Set<String> = [
        "about", "collections", "enterprise", "explore", "features", "issues", "login", "marketplace", "notifications",
        "orgs", "pricing", "pulls", "search", "settings", "sponsors", "topics", "trending",
    ]

    /// `github.com/ml-explore/mlx`, with or without `.git`, `/releases`, `/tree/main/…` after it.
    static func repository(in url: URL) -> (owner: String, name: String)? {
        guard url.bareHost == "github.com" else { return nil }
        let segments = url.pathSegments
        guard segments.count >= 2, !reservedOwners.contains(segments[0].lowercased()) else { return nil }
        let name = segments[1].hasSuffix(".git") ? String(segments[1].dropLast(4)) : segments[1]
        return name.isEmpty ? nil : (segments[0], name)
    }
}
