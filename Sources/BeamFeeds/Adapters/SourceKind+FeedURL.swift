import BeamModels
import Foundation

extension SourceKind {
    /// What kind of source a feed address is. The kind decides how a source is fetched, read and opened, so a
    /// feed URL pasted directly must get the same kind as the same feed found from its site.
    public init(feedURL: URL) {
        if HackerNews.matches(feedURL) { self = .hackerNews }
        else if Arxiv.matches(feedURL: feedURL) { self = .arxiv }
        else if GitHubReleases.repoName(feedURL: feedURL) != nil { self = .githubReleases }
        else if YouTube.matches(feedURL: feedURL) { self = .youtube }
        else if Reddit.matches(feedURL: feedURL) { self = .reddit }
        else { self = .feed }
    }
}
