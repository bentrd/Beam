import BeamExtract
import BeamModels
import Foundation

/// The passage rules of PRODUCT.md section 6 and the junk rules, on small hand-written pages where the right answer is obvious.
enum PassageChecks {
    private static let long = "This sentence is comfortably longer than forty characters, so it stands on its own."
    private static let other = "A second paragraph that is also long enough to be judged without any help at all."

    static func run(_ report: inout CheckReport) {
        merging(&report)
        splitting(&report)
        structure(&report)
        junk(&report)
        guards(&report)
    }

    private static func passages(_ html: String, title: String? = nil) -> [Passage] {
        (try? Readability.extractFragment(html, knownTitle: title))?.passages ?? []
    }

    private static func merging(_ report: inout CheckReport) {
        report.section("Passages: under 40 characters merges")
        report.expectEqual(passages("<p>\(long)</p><p>Why?</p><p>\(other)</p>").map(\.text), [long, "Why? \(other)"], "a short paragraph merges forward")
        report.expectEqual(passages("<p>\(long)</p><p>Thanks!</p><h2>Next</h2><p>\(other)</p>").map(\.text), ["\(long) Thanks!", "Next", other],
                           "with a heading in the way it merges backward, never across the heading")
        report.expectEqual(passages("<h2>Status</h2><p>Deprecated.</p><h2>Usage</h2><p>\(long)</p>").map(\.text), ["Usage", long],
                           "with nothing to merge into it is dropped, and the heading it emptied goes with it")
        let list = passages("<p>\(long)</p><ul><li>Fix crash on launch</li><li>Add dark mode</li><li>Update dependencies</li></ul>")
        report.expectEqual(list.last?.text, "Fix crash on launch\u{2028}Add dark mode\u{2028}Update dependencies", "short list items merge onto separate lines of one passage")
        report.expectEqual(list.last?.kind, .listItem, "and stay a list item")
        report.expectEqual(passages("<p>21 September 2026</p><p>By A. Writer</p><p>\(long)</p>").map(\.text), [long], "datelines and bylines above the first paragraph are dropped, not merged into it")
    }

    private static func splitting(_ report: inout CheckReport) {
        report.section("Passages: over 1,200 characters splits at a sentence end")
        let sentences = (1...60).map { "Sentence number \($0) says something of moderate length about the topic at hand." }
        let pieces = passages("<p>\(sentences.joined(separator: " "))</p>").map(\.text)
        report.expect(pieces.count >= 4 && pieces.allSatisfy { $0.count <= Passages.maximumLength }, "a 4,800-character paragraph becomes \(pieces.count) passages, none over the limit")
        report.expect(pieces.allSatisfy { $0.hasSuffix(".") && $0.hasPrefix("Sentence number") }, "every piece starts and ends on a sentence boundary")
        report.expectEqual(pieces.joined(separator: " "), sentences.joined(separator: " "), "no text is lost or duplicated by splitting")
        let sizes = pieces.map(\.count)
        report.expect((sizes.max() ?? 0) - (sizes.min() ?? 0) < 400, "pieces are of similar size (\(sizes))")

        let endless = passages("<p>\(String(repeating: "word ", count: 600))</p>").map(\.text)
        report.expect(endless.count >= 3 && endless.allSatisfy { $0.count <= Passages.maximumLength }, "text with no sentence end still splits, at word boundaries")
        let code = passages("<p>\(long)</p><pre>\(String(repeating: "let value = compute()\n", count: 100))</pre>")
        report.expect(code.last?.kind == .code && (code.last?.text.count ?? 0) > Passages.maximumLength, "code is never split")
    }

    private static func structure(_ report: inout CheckReport) {
        report.section("Passages: kinds, sections, cap")
        let page = passages("""
            <p>\(long)</p><h2>Alpha</h2><p>\(other)</p><blockquote><p>\(long)</p></blockquote>
            <h3>Beta</h3><ul><li>\(other)</li></ul><pre><code>let x = 1\n  let y = 2</code></pre><h2>Empty</h2><h2>Gamma</h2><p>\(long)</p>
            """)
        report.expectEqual(page.map(\.kind), [.paragraph, .heading, .paragraph, .quote, .heading, .listItem, .code, .heading, .paragraph], "paragraph, quote, list item, heading and code are told apart")
        report.expectEqual(page.map(\.section), ["", "", "Alpha", "Alpha", "Alpha", "Beta", "Beta", "Beta", "Gamma"], "every passage carries the nearest heading above it")
        report.expect(!page.contains { $0.text == "Empty" }, "a heading with nothing under it is dropped")
        report.expectEqual(page.filter { !$0.isJudgeable }.map(\.kind), [.heading, .heading, .code, .heading], "headings and code are kept but not judgeable")
        report.expectEqual(page.first { $0.kind == .code }?.text, "let x = 1\n  let y = 2", "code keeps its line breaks and indentation")

        let many = passages((1...500).map { "<p>Paragraph \($0): \(long)</p>" }.joined())
        report.expectEqual(many.count, Passages.maximumCount, "an article is capped at 400 passages")
        report.expectEqual(passages("<h1>A Fine Title For A Post</h1><p>\(long)</p>", title: "A Fine Title for a Post").map(\.text), [long], "a first heading that repeats the item's title is dropped")
        report.expectEqual(Passages.fromPlainText("We study\nattention.\n\n\(long)").map(\.text), [long], "plain text: blank lines separate paragraphs, hard wraps are joined, a leading fragment is dropped")
        report.expectEqual(passages("<p>Il a dit&nbsp;: «&nbsp;\(long)&nbsp;» &amp; rien d&rsquo;autre.</p>").first?.text,
                           "Il a dit\u{00A0}: «\u{00A0}\(long)\u{00A0}» & rien d’autre.", "entities are decoded and French non-breaking spaces survive")
    }

    private static func junk(_ report: inout CheckReport) {
        report.section("Readability: what is never article text")
        let page = """
            <html><head><title>Post</title><style>p { color: red }</style></head><body>
            <header><nav><ul><li><a href="/">Home page of this site, with a long label</a></li></ul></nav></header>
            <main><article>
              <p>\(long)<sup class="reference"><a href="#n1">[1]</a></sup> And it continues after the marker for a while.</p>
              \((1...10).map { "<p>Paragraph \($0). \(other)</p>" }.joined())
              <p hidden>This hidden paragraph is long enough to count but must never be shown to anyone.</p>
              <div style="display: none">This invisible block is long enough to count but must never be shown either.</div>
              <aside><p>Subscribe to the newsletter, it is long enough to look like a paragraph of prose.</p></aside>
              <figure><img src="chart.png" width="640" height="480"><figcaption>A caption long enough to look like a paragraph of real prose.</figcaption></figure>
              <img src="pixel.gif" width="1" height="1">
              <table><tr><th>Year</th><th>Users</th></tr><tr><td>2024</td><td>10</td></tr></table>
              <p>\(other)</p>
              <div class="comments"><p>First! This comment is long enough to look like a paragraph of real prose.</p></div>
              <ol class="references"><li>↑ Someone, <i>A Book Long Enough To Look Like Prose</i>, Publisher, 2024, p. 12.</li></ol>
              <script>document.write("<p>Injected text that is long enough to look like a paragraph.</p>")</script>
            </article></main>
            <footer><p>Copyright 2026 Example Corp. All rights reserved, in a sentence long enough to count.</p></footer>
            </body></html>
            """
        guard let article = try? Readability.extract(html: page) else { report.expect(false, "the junk page extracts"); return }
        let expected = ["\(long) And it continues after the marker for a while."] + (1...10).map { "Paragraph \($0). \(other)" } + [other]
        report.expectEqual(article.passages.map(\.text), expected, "nav, footer, aside, hidden, comments, references, captions, scripts and citation markers are all gone")
        report.expectEqual([article.images, article.tables], [1, 1], "one real image and one data table are counted; the tracking pixel is not")
        report.expectEqual(article.title, "Post", "the page title is reported")

        let sphinx = passages("<p>See the <a class=\"reference internal\" href=\"x.html\">installation guide</a> before going any further with this.</p>")
        report.expectEqual(sphinx.first?.text, "See the installation guide before going any further with this.", "prose links classed \"reference\" (Sphinx) keep their text")
        let highlighted = passages("<p>\(long)</p><pre><span class=\"hljs-comment\">// explain</span>\nrun()</pre>")
        report.expectEqual(highlighted.last?.text, "// explain\nrun()", "syntax-highlighter spans named \"comment\" are not mistaken for a comments section")
        let wrapper = passages("<div class=\"content-sidebar-wrap\"><p>\(long)</p><p>\(other)</p></div>")
        report.expectEqual(wrapper.count, 2, "a wrapper with an unlucky class name (\"content-sidebar-wrap\") is kept when nothing else would remain")
        let links = passages("<p>\(long)</p><ul><li><a href=\"/a\">A related story with a long enough headline to count</a></li></ul>")
        report.expectEqual(links.count, 1, "list items that are nothing but a link are navigation")
    }

    private static func guards(_ report: inout CheckReport) {
        report.section("Readability: guards against huge pages")
        let huge = Data(repeating: 0x20, count: Readability.maximumBytes + 1)
        report.expect(throwsError(.tooLarge(bytes: huge.count)) { _ = try Readability.extract(data: huge, httpCharset: nil) }, "bodies over 5 MB are refused before any parsing")
        let big = "<html><body>" + (1...4000).map { "<div><p>Paragraph \($0): \(long)</p></div>" }.joined() + "</body></html>"
        report.expect(throwsError(.timedOut) { _ = try Readability.extract(html: big, timeBudget: .milliseconds(1)) }, "processing stops when its time budget runs out")
        report.expect((try? Readability.extract(html: big))?.passages.count == Passages.maximumCount, "the same page inside the default budget is simply capped")
        report.expectEqual((try? Readability.extract(html: ""))?.passages.count, 0, "an empty body is an empty article, not a crash")
        report.expectEqual((try? Readability.extract(html: "<<<>>> not html at all & <p"))?.wordCount, 0, "garbage is an empty article, not a crash")
    }

    private static func throwsError(_ expected: ExtractionError, _ body: () throws -> Void) -> Bool {
        do { try body(); return false } catch let error as ExtractionError { return error == expected } catch { return false }
    }
}
