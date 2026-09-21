import BeamExtract
import BeamModels
import Foundation

/// `check-extract probe <url-or-file>… [--dump]`: what Beam's reader would get for a page. A development aid for
/// judging extraction by eye (PRODUCT.md risk 2); it is not part of the pass/fail run.
enum Probe {
    static func run(_ arguments: [String]) async -> Int32 {
        let dump = arguments.contains("--dump")
        for target in arguments where !target.hasPrefix("--") {
            print("\n== \(target)")
            let started = ContinuousClock.now
            if let url = URL(string: target), url.scheme?.hasPrefix("http") == true {
                let item = Item(sourceID: 0, guid: target, url: url, title: "", snippet: "")
                report(await ArticleLoader().load(item: item, sourceKind: .feed), dump: dump)
            } else if let data = FileManager.default.contents(atPath: target) {
                do { report(try Readability.extract(data: data, httpCharset: nil), dump: dump) } catch { print("   error: \(error)") }
            } else {
                print("   not a URL or a readable file")
            }
            print("   \((ContinuousClock.now - started).formatted(.units(allowed: [.milliseconds])))")
        }
        return 0
    }

    private static func report(_ content: ArticleContent, dump: Bool) {
        switch content {
        case let .ready(passages, images, tables): summarise(passages, images: images, tables: tables, dump: dump)
        case let .unavailable(reason): print("   unavailable: \(reason)")
        case .external: print("   external")
        }
    }

    private static func report(_ article: ExtractedArticle, dump: Bool) {
        print("   title: \(article.title)\n   words: \(article.wordCount)  embedded: \(article.usedEmbeddedBody)  paywall: \(article.declaresPaywall)  javascript: \(article.needsJavaScript)")
        summarise(article.passages, images: article.images, tables: article.tables, dump: dump)
    }

    private static func summarise(_ passages: [Passage], images: Int, tables: Int, dump: Bool) {
        let kinds = Dictionary(grouping: passages, by: \.kind).map { "\($0.key.rawValue) \($0.value.count)" }.sorted().joined(separator: ", ")
        print("   \(passages.count) passages (\(kinds)); \(images) images, \(tables) tables")
        let shown = dump || passages.count <= 9 ? passages[...] : passages.prefix(6) + passages.suffix(3)
        for passage in shown {
            let text = passage.text.replacingOccurrences(of: "\n", with: "⏎")
            print("   [\(passage.kind.rawValue.prefix(4))] \(dump ? text : String(text.prefix(110)))")
        }
    }
}
