import BeamExtract
import Foundation

/// One saved page. All were fetched with curl and Beam's Safari User-Agent on 2026-09-21 and are stored byte for
/// byte, except `news-ctv-jsonld.html`, whose inline scripts (other than JSON-LD) and styles were removed to fit the
/// 400 KB cap; Beam strips those before parsing anyway, so the extraction is unchanged.
struct Fixture {
    enum Expectation {
        case article(passages: ClosedRange<Int>, words: ClosedRange<Int>)
        /// The loader must answer `.unavailable` with a reason containing this.
        case unavailable(reasonContains: String)
    }

    let file: String
    let url: String
    /// The charset of the HTTP `Content-Type` header the page was served with.
    let httpCharset: String?
    let expectation: Expectation

    var data: Data? {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil).flatMap { try? Data(contentsOf: $0.appendingPathComponent(file)) }
    }

    static let all: [Fixture] = [
        // A maths-heavy post: KaTeX leaves both a rendered copy and the TeX source in the page.
        Fixture(file: "math-katex.html", url: "https://gregorygundersen.com/blog/2018/04/15/backprop/", httpCharset: "utf-8",
                expectation: .article(passages: 15...40, words: 900...2500)),
        Fixture(file: "blog-willison.html", url: "https://simonwillison.net/2024/Dec/31/llms-in-2024/", httpCharset: "utf-8",
                expectation: .article(passages: 150...220, words: 5000...7000)),
        Fixture(file: "blog-daringfireball.html", url: "https://daringfireball.net/2025/03/something_is_rotten_in_the_state_of_cupertino", httpCharset: "UTF-8",
                expectation: .article(passages: 40...70, words: 3500...5000)),
        Fixture(file: "blog-paulgraham.html", url: "https://paulgraham.com/greatwork.html", httpCharset: nil,
                expectation: .article(passages: 200...260, words: 10000...13000)),
        Fixture(file: "blog-rust.html", url: "https://blog.rust-lang.org/2024/11/28/Rust-1.83.0/", httpCharset: "utf-8",
                expectation: .article(passages: 20...40, words: 300...600)),
        Fixture(file: "substack-oneusefulthing.html", url: "https://www.oneusefulthing.org/p/15-times-to-use-ai-and-5-not-to", httpCharset: "utf-8",
                expectation: .article(passages: 20...35, words: 1200...1800)),
        Fixture(file: "news-bbc.html", url: "https://www.bbc.com/news/articles/c20veglyjp8o", httpCharset: "utf-8",
                expectation: .article(passages: 22...40, words: 450...700)),
        Fixture(file: "news-elmundo-latin9.html", url: "https://www.elmundo.es/andalucia/2026/09/20/6aaf8f3be85ecead788b459f.html", httpCharset: "iso-8859-15",
                expectation: .article(passages: 5...12, words: 350...500)),
        Fixture(file: "news-ctv-jsonld.html", url: "https://www.ctvnews.ca/politics/article/major-legislation-promised-as-commons-returns-from-summer-break/", httpCharset: "utf-8",
                expectation: .article(passages: 2...8, words: 400...650)),
        Fixture(file: "wikipedia-en.html", url: "https://en.wikipedia.org/wiki/RSS", httpCharset: "UTF-8",
                expectation: .article(passages: 45...80, words: 2000...3000)),
        Fixture(file: "wikipedia-fr.html", url: "https://fr.wikipedia.org/wiki/Balatro", httpCharset: "UTF-8",
                expectation: .article(passages: 22...40, words: 800...1200)),
        Fixture(file: "github-readme.html", url: "https://github.com/ml-explore/mlx", httpCharset: "utf-8",
                expectation: .article(passages: 25...40, words: 350...550)),
        Fixture(file: "github-terms.html", url: "https://docs.github.com/en/site-policy/github-terms/github-terms-of-service", httpCharset: "utf-8",
                expectation: .article(passages: 180...240, words: 6000...7500)),
        Fixture(file: "arxiv-abs.html", url: "https://arxiv.org/abs/1706.03762", httpCharset: "utf-8",
                expectation: .article(passages: 1...3, words: 150...220)),
        Fixture(file: "arxiv-html.html", url: "https://arxiv.org/html/1706.03762", httpCharset: "utf-8",
                expectation: .article(passages: 80...130, words: 3500...4500)),
        Fixture(file: "paywall-mediapart.html", url: "https://www.mediapart.fr/journal/culture-et-idees/190926/l-ia-cree-un-debat-existentiel-sur-l-usage-des-mathematiques", httpCharset: "UTF-8",
                expectation: .unavailable(reasonContains: "Paywalled")),
        Fixture(file: "shell-bluesky.html", url: "https://bsky.app/profile/bsky.app", httpCharset: "UTF-8",
                expectation: .unavailable(reasonContains: "JavaScript")),
    ]

    static func named(_ file: String) -> Fixture? { all.first { $0.file == file } }

    /// The page as the reader would get it, or nil (after a recorded failure in the caller) when it cannot be read or parsed.
    func extracted() -> ExtractedArticle? {
        data.flatMap { try? Readability.extract(data: $0, httpCharset: httpCharset) }
    }
}
