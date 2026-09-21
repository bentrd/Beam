import BeamExtract
import BeamModels
import Foundation

/// Every saved page yields sane passages, and the pages chosen for a specific hazard show that it is handled.
enum FixtureChecks {
    static func run(_ report: inout CheckReport) {
        report.section("Fixtures: every page yields sane passages")
        var timings: [Duration] = []
        for fixture in Fixture.all {
            guard case let .article(passageRange, wordRange) = fixture.expectation else { continue }
            guard let data = fixture.data else { report.expect(false, "\(fixture.file) is in the bundle"); continue }
            report.expect(data.count < 400_000, "\(fixture.file) is under 400 KB", detail: "\(data.count) bytes")
            let started = ContinuousClock.now
            guard let article = try? Readability.extract(data: data, httpCharset: fixture.httpCharset) else {
                report.expect(false, "\(fixture.file) extracts"); continue
            }
            let elapsed = ContinuousClock.now - started
            timings.append(elapsed)
            let summary = "\(article.passages.count) passages, \(article.wordCount) words, \(elapsed.formatted(.units(allowed: [.milliseconds])))"
            report.expect(passageRange.contains(article.passages.count) && wordRange.contains(article.wordCount),
                          "\(fixture.file): counts in range (\(summary))", detail: "expected \(passageRange) passages, \(wordRange) words")
            for problem in problems(in: article.passages) { report.expect(false, "\(fixture.file): \(problem)") }
        }
        if let slowest = timings.max() { report.note("slowest page: \(slowest.formatted(.units(allowed: [.milliseconds]))) (debug build)") }
        report.expect((timings.max() ?? .zero) < .seconds(2), "no page takes longer than 2 s to extract")

        encodings(&report)
        wikipedia(&report)
        structure(&report)
        embeddedBody(&report)
    }

    /// The invariants of PRODUCT.md section 6, checked on real text. An empty result means the passages are sane.
    static func problems(in passages: [Passage]) -> [String] {
        var found: [String] = []
        var section = ""
        if passages.count > Passages.maximumCount { found.append("more than \(Passages.maximumCount) passages") }
        for (index, passage) in passages.enumerated() {
            let label = "passage \(index) (\(passage.kind.rawValue))"
            if passage.text.isEmpty || passage.text != passage.text.trimmingCharacters(in: .whitespacesAndNewlines) { found.append("\(label) is empty or untrimmed") }
            if passage.section != section { found.append("\(label) has section \"\(passage.section)\", the heading above is \"\(section)\"") }
            if passage.kind == .heading { section = passage.text }
            if passage.isJudgeable != ![.heading, .code].contains(passage.kind) { found.append("\(label) has the wrong judgeability") }
            if ["Ã©", "Ã¨", "â€", "Â ", "\u{FFFD}"].contains(where: passage.text.contains) { found.append("\(label) has mojibake: \(passage.text.prefix(60))") }
            guard passage.isJudgeable else { continue }
            if passage.text.contains("\n") { found.append("\(label) contains a newline") }
            if passage.text.count > Passages.maximumLength { found.append("\(label) is \(passage.text.count) characters, over the split limit") }
            if ["</p>", "</div>", "<span", "&nbsp;", "&amp;"].contains(where: passage.text.contains) { found.append("\(label) has markup left in it") }
            if passage.text.count < Passages.minimumLength {
                let neighbours = [index - 1, index + 1].filter(passages.indices.contains).map { passages[$0] }
                if neighbours.contains(where: { $0.kind == passage.kind && $0.text.count + passage.text.count < Passages.maximumLength }) {
                    found.append("\(label) is short (\"\(passage.text)\") but has a neighbour it should have merged into")
                }
            }
        }
        return found
    }

    private static func encodings(_ report: inout CheckReport) {
        report.section("Fixtures: encodings")
        if let french = Fixture.named("wikipedia-fr.html")?.extracted() {
            let text = french.passages.map(\.text).joined(separator: " ")
            report.expect(text.contains("jeu vidéo indépendant") && text.contains("développé"), "French Wikipedia keeps its accents")
            report.expect(!["Ã", "â€", "\u{FFFD}"].contains(where: text.contains), "French Wikipedia has no mojibake")
        } else { report.expect(false, "wikipedia-fr.html extracts") }

        if let fixture = Fixture.named("news-elmundo-latin9.html"), let data = fixture.data,
           let byHeader = try? Readability.extract(data: data, httpCharset: fixture.httpCharset),
           let byMeta = try? Readability.extract(data: data, httpCharset: nil) {
            let text = byHeader.passages.map(\.text).joined(separator: " ")
            report.expect(text.contains("Almería") && text.contains("trombectomía"), "an ISO-8859-15 page decodes through its HTTP charset")
            report.expect(byMeta.passages == byHeader.passages, "the same page decodes identically through its <meta> charset alone")
        } else { report.expect(false, "news-elmundo-latin9.html extracts") }
    }

    private static func wikipedia(_ report: inout CheckReport) {
        report.section("Fixtures: references and page furniture are dropped")
        for file in ["wikipedia-en.html", "wikipedia-fr.html"] {
            guard let article = Fixture.named(file)?.extracted() else { report.expect(false, "\(file) extracts"); continue }
            let texts = article.passages.map(\.text)
            report.expect(!texts.contains { $0.hasPrefix("↑") || $0.hasPrefix("^") }, "\(file): no reference-list lines (↑ / ^)")
            report.expect(texts.filter { $0.contains("Retrieved ") || $0.contains("Archived from") || $0.contains("consulté le") }.count <= 1, "\(file): no citation boilerplate")
            report.expect(!texts.contains { $0.contains("[edit]") || $0.contains("[modifier") }, "\(file): no section edit links")
            report.expect(!texts.contains { $0.range(of: #"\[\d+\]"#, options: .regularExpression) != nil }, "\(file): no [12] citation markers glued to sentences")
            report.expect(!article.passages.contains { $0.kind == .heading && ["References", "Références", "Notes et références"].contains($0.text) }, "\(file): the emptied References heading is gone")
        }
        if let english = Fixture.named("wikipedia-en.html")?.extracted() { report.expect(english.tables >= 1, "wikipedia-en.html: tables are counted, not shown (\(english.tables))") }
        if let readme = Fixture.named("github-readme.html")?.extracted() {
            let text = readme.passages.map(\.text).joined(separator: " ")
            report.expect(!text.contains("Pull requests") && !text.contains("Terms") && readme.passages.first?.text == "MLX", "github-readme.html: only the README, none of GitHub's chrome")
        }
    }

    private static func structure(_ report: inout CheckReport) {
        report.section("Fixtures: structure")
        if let willison = Fixture.named("blog-willison.html")?.extracted() {
            report.expect(willison.passages.first?.text.hasPrefix("A lot has happened") == true, "blog-willison.html: the dateline and the repeated title are not passages",
                          detail: String(willison.passages.first?.text.prefix(50) ?? ""))
            let kinds = Set(willison.passages.map(\.kind))
            report.expect(kinds.isSuperset(of: [.heading, .paragraph, .quote, .listItem, .code]), "blog-willison.html: all five passage kinds occur")
            report.expect(willison.passages.filter(\.isJudgeable).filter { !$0.section.isEmpty }.count > 140, "blog-willison.html: passages carry their section heading")
            report.expect(willison.images >= 1, "blog-willison.html: images are counted (\(willison.images))")
        }
        if let graham = Fixture.named("blog-paulgraham.html")?.extracted() {
            report.expect(graham.passages.first?.text.hasPrefix("If you collected lists of techniques") == true, "blog-paulgraham.html: a page with no <p>, only <br><br>, splits into paragraphs")
        }
        if let rust = Fixture.named("blog-rust.html")?.extracted() {
            let code = rust.passages.filter { $0.kind == .code }
            report.expect(code.count >= 5 && code.allSatisfy { !$0.isJudgeable }, "blog-rust.html: code blocks are kept and not judgeable (\(code.count))")
            report.expect(code.contains { $0.text.contains("\n") }, "blog-rust.html: code keeps its line breaks")
        }
        if let terms = Fixture.named("github-terms.html")?.extracted() {
            let governing = terms.passages.filter { $0.text.contains("governed by the federal laws") }
            report.expect(governing.count == 1 && governing.first?.section.contains("Governing Law") == true,
                          "github-terms.html: the governing-law paragraph exists once, under its heading", detail: governing.first?.section ?? "missing")
        }
        if let paper = Fixture.named("arxiv-html.html")?.extracted() {
            let sections = Set(paper.passages.map(\.section))
            report.expect(sections.isSuperset(of: ["Abstract", "1 Introduction", "3.2 Attention", "7 Conclusion"]),
                          "arxiv-html.html: every section of the paper is there, not just the longest")
            report.expect(paper.passages.contains { $0.kind == .code && $0.text.contains("\\mathrm{Attention}") }, "arxiv-html.html: display equations are TeX, shown as code, never judged")
            report.expect(!paper.passages.contains { $0.text.contains("arXiv preprint") }, "arxiv-html.html: the bibliography is dropped")
            report.expect(paper.tables >= 2, "arxiv-html.html: tables are counted (\(paper.tables))")
        }
    }

    private static func embeddedBody(_ report: inout CheckReport) {
        report.section("Fixtures: JSON-LD articleBody fallback")
        guard let article = Fixture.named("news-ctv-jsonld.html")?.extracted() else { report.expect(false, "news-ctv-jsonld.html extracts"); return }
        report.expect(article.usedEmbeddedBody, "a page whose markup holds no text is read from its JSON-LD articleBody")
        report.expect(article.passages.first?.text.hasPrefix("OTTAWA") == true, "the embedded body starts where the article starts")
        report.expect(article.passages.count >= 3 && article.passages.allSatisfy { $0.text.count <= Passages.maximumLength && ".”\"!?".contains($0.text.last ?? " ") },
                      "its one unbroken 3,000-character string is split at sentence ends")
        if let willison = Fixture.named("blog-willison.html")?.extracted() { report.expect(!willison.usedEmbeddedBody, "pages with readable markup never use the fallback") }
    }
}
