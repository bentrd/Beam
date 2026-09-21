import BeamExtract
import BeamModels
import Foundation

/// Maths and code in the reader.
///
/// Beam has no renderer: the reading view is text. A page's maths therefore has to arrive as characters a person
/// can read, and the two things the page offers are both wrong on their own — the visual markup collapses to
/// `x2x^2`, and the TeX source reads as `\frac{\partial f}{\partial v}`. These checks hold the conversion to the
/// promise: real symbols, real sub- and superscripts, and no backslash left anywhere near the reader.
enum MathChecks {
    static func run(_ report: inout CheckReport) {
        report.section("TeX becomes readable maths")
        conversions(&report)

        report.section("A real KaTeX page")
        katexPage(&report)

        report.section("JSON wearing a page's Content-Type")
        jsonPages(&report)

        report.section("Code is shown, and never judged")
        code(&report)
    }

    private static func conversions(_ report: inout CheckReport) {
        func check(_ source: String, _ expected: String, _ what: String) {
            report.expectEqual(TeX.readable(source), expected, what)
        }
        check(#"\frac{\partial f}{\partial v}"#, "∂f/∂v", "a derivative becomes ∂f/∂v")
        check(#"\theta_1"#, "θ₁", "a subscripted greek letter becomes θ₁")
        check(#"\theta_i"#, "θᵢ", "a lettered subscript becomes θᵢ")
        check(#"x^2"#, "x²", "a power becomes x²")
        check(#"\sigma(u)"#, "σ(u)", "a function keeps its brackets")
        check(#"\sum_{j} \frac{\partial f}{\partial w_j}"#, "∑ⱼ ∂f/∂wⱼ", "a sum keeps its index")
        check(#"\frac{a+b}{c}"#, "(a+b)/c", "a compound numerator keeps its brackets")
        check(#"\sqrt{2}"#, "√2", "a root of one term needs no brackets")
        check(#"\sqrt{a+b}"#, "√(a+b)", "a root of a sum keeps them")
        check(#"\frac{QK^T}{\sqrt{d_k}}"#, "QK^T/√dₖ", "a fraction over a root reads inside-out")
        check(#"\dots"#, "…", "an ellipsis is one character")
        check(#"\mathbb{R}^n"#, "ℝⁿ", "blackboard letters survive")
        check(#"\text{if } x > 0"#, "if x > 0", "words inside maths stay words")
        check(#"\begin{aligned} u &= 1 \\ v &= 2 \end{aligned}"#, "u = 1 v = 2", "an aligned block loses its scaffolding")
        check("u &amp;= 1", "u = 1", "an escaped ampersand does not leave 'amp;' behind")
        check(#"\Big( \frac{1}{2} \Big)"#, "( 1/2 )", "sizing commands disappear")
        check(#"\color{red}{x}"#, "x", "a colour command keeps only its content")
        check(#"\theta_{ij}"#, "θᵢⱼ", "a two-letter subscript converts")
        check(#"x^{2n}"#, "x²ⁿ", "a two-character power converts")
        check(#"\frac{\partial f}{\partial z_k}"#, "∂f/∂zₖ", "a subscript inside a fraction converts")
        // A brace annotation labels the brace, not a power: once the brace is gone the label reads as nonsense.
        check(#"\overbrace{a+b}^{\text{Repeated terms}}"#, "a+b", "a brace annotation is dropped, not inlined")
        check(#"\underbrace{x}_{\text{the residual}}"#, "x", "an underbrace label goes the same way")

        // The promise that matters most: nothing with a backslash ever reaches the reader.
        let awkward = [#"\wibble{x}"#, #"\frac{\partial^2 f}{\partial x \partial y}"#, #"\left[ \begin{matrix} a \\ b \end{matrix} \right]"#]
        for source in awkward {
            let out = TeX.readable(source)
            report.expect(!out.contains("\\"), "no backslash survives \(source.prefix(28))…", detail: out)
            report.expect(!out.contains("{") && !out.contains("}"), "no braces survive \(source.prefix(28))…", detail: out)
        }
        report.expectEqual(TeX.readable(""), "", "empty source stays empty")
        report.expect(!TeX.isMeaningful(#"\,"#), "a lone spacing command is not worth showing")
    }

    private static func katexPage(_ report: inout CheckReport) {
        guard let data = Fixture.named("math-katex.html")?.data,
              let article = try? Readability.extract(data: data, httpCharset: "utf-8") else {
            report.expect(false, "the KaTeX fixture extracts")
            return
        }
        let body = article.passages.filter(\.isJudgeable)
        let all = body.map(\.text).joined(separator: " ")

        report.expect(!all.contains("\\"), "no TeX source reaches the reader",
                      detail: body.first { $0.text.contains("\\") }.map { String($0.text.prefix(80)) } ?? "")
        report.expect(!all.contains("amp;"), "no half-decoded entities reach the reader")
        report.expect(!all.contains("begin{") && !all.contains("aligned"), "no environment names reach the reader")
        report.expect(all.contains("∂"), "derivatives are drawn as ∂")
        report.expect(all.contains("θ₁") || all.contains("θᵢ"), "subscripts are real characters")
        report.expect(all.contains("σ"), "greek letters are greek letters")
        report.expect(all.contains("∂f/∂v") || all.contains("∂f/∂θ₁"), "a derivative reads as a derivative",
                      detail: body.first { $0.text.contains("∂") }.map { String($0.text.prefix(90)) } ?? "")

        // KaTeX puts the formula in the page twice; only one copy may survive.
        report.expect(!all.contains("x2x^2"), "the presentation copy is not doubled into the text")
    }

    /// A response that is JSON wearing a page's Content-Type. The header cannot be trusted, so the body is sniffed.
    private static func jsonPages(_ report: inout CheckReport) {
        guard let data = Fixture.named("activitypub-json.html")?.data,
              let article = try? Readability.extract(data: data, httpCharset: "utf-8") else {
            report.expect(false, "the ActivityPub fixture extracts")
            return
        }
        let body = article.passages.filter(\.isJudgeable)
        let all = body.map(\.text).joined(separator: " ")
        report.expect(!all.contains("@context") && !all.contains("activitystreams"),
                      "no raw JSON reaches the reader", detail: String(all.prefix(70)))
        report.expect(!all.contains("\\u003C"), "the post's own escapes are decoded, not shown")
        report.expect(all.contains("NEC V20") || all.contains("8088"),
                      "the post itself is read out of the JSON", detail: String(all.prefix(90)))
        report.expect(body.count >= 3, "and split into paragraphs", detail: "\(body.count)")

        // JSON with nothing readable in it is not a page, and must say so rather than showing its keys.
        let envelope = "{\"status\":\"ok\",\"items\":[{\"id\":1},{\"id\":2}]}"
        do {
            _ = try Readability.extract(html: envelope)
            report.expect(false, "an API envelope is refused")
        } catch {
            report.expectEqual("\(error)", "\(ExtractionError.notAPage)", "an API envelope is refused as not a page")
        }
        report.expect(JSONPage.body(of: "<!doctype html><p>ordinary</p>") == nil,
                      "an ordinary page is not mistaken for JSON")
    }

    private static func code(_ report: inout CheckReport) {
        for name in ["blog-rust.html", "github-readme.html"] {
            guard let data = Fixture.named(name)?.data,
                  let article = try? Readability.extract(data: data, httpCharset: "utf-8") else {
                report.expect(false, "\(name) extracts")
                continue
            }
            let code = article.passages.filter { $0.kind == .code }
            report.expect(!code.isEmpty, "\(name) keeps its code blocks", detail: "\(code.count) blocks")
            report.expect(code.allSatisfy { !$0.isJudgeable },
                          "\(name): code is never sent to be judged")
            report.expect(code.allSatisfy { !$0.text.isEmpty }, "\(name): no code block is empty")
            // Code is the one place where a line break carries meaning, so it must not be flattened away.
            if name == "blog-rust.html" {
                report.expect(code.contains { $0.text.contains("\n") },
                              "a multi-line snippet keeps its line breaks",
                              detail: code.first.map { String($0.text.prefix(60)) } ?? "")
            }
        }
    }
}
