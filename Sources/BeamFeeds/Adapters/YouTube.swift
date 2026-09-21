import BeamModels
import Foundation

/// A channel's uploads through YouTube's Atom feed. Only `/channel/UC…` addresses: @handle pages sit behind the
/// EU consent redirect (PRODUCT.md "V1 CUT"), though generic discovery still gets a try at them.
enum YouTube {
    /// The channel's name is only known once its feed has been read, so the candidate starts with a placeholder title.
    static func candidate(channelID: String) -> SourceCandidate? {
        guard let feedURL = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)") else { return nil }
        return SourceCandidate(kind: .youtube, title: "YouTube channel", feedURL: feedURL,
                               siteURL: URL(string: "https://www.youtube.com/channel/\(channelID)"))
    }

    static func channelID(in url: URL) -> String? {
        guard let host = url.bareHost, host == "youtube.com" || host == "m.youtube.com" else { return nil }
        let segments = url.pathSegments
        guard segments.count >= 2, segments[0] == "channel" else { return nil }
        let id = segments[1]
        let isValid = id.hasPrefix("UC") && id.count == 24 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return isValid ? id : nil
    }

    static func matches(feedURL: URL) -> Bool {
        feedURL.bareHost == "youtube.com" && feedURL.path == "/feeds/videos.xml"
    }
}
