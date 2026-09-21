import Foundation

/// Walks the tidied tree once, in reading order, and produces the flat list of `Block`s the rest of the pipeline works on.
///
/// Nothing is detached from the tree and no XPath is evaluated per node (the spike did both and spent most of its time
/// there). For every container the walker remembers which slice of `blocks` it produced, which is all `ContentSelector`
/// needs to weigh containers against each other.
final class BlockWalker {
    struct Suspect { let range: Range<Int>; let isStrong: Bool }

    /// Loose text (not in a `<p>`, `<li>` or `<blockquote>`) shorter than this is a label or a button, not prose.
    static let minimumLooseTextLength = 40
    /// Blocks shorter than this say nothing about where the article is.
    static let minimumWeighedLength = 40
    /// Above this share of link text a block is navigation.
    static let maximumLinkShare = 0.6

    private(set) var blocks: [Block] = []
    private(set) var ranges: [ObjectIdentifier: Range<Int>] = [:]
    private(set) var suspects: [Suspect] = []

    private let deadline: Deadline
    private var visited = 0

    private static let blockTags: Set<String> = [
        "address", "blockquote", "body", "caption", "center", "dd", "dir", "div", "dl", "dt", "fieldset", "form", "h1", "h2", "h3",
        "h4", "h5", "h6", "html", "li", "menu", "ol", "p", "pre", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul",
    ]

    init(deadline: Deadline) { self.deadline = deadline }

    func walk(_ root: XMLElement) throws {
        try visitContainer(root, context: Context())
    }

    // MARK: Containers

    private struct Context { var inQuote = false; var inList = false
        var kind: Block.Kind { inQuote ? .quote : (inList ? .listItem : .paragraph) }
    }

    /// Text gathered from consecutive inline nodes that sit directly in a container.
    private struct InlineRun { var text = ""; var characters = 0; var linkedCharacters = 0; var images = 0
        mutating func append(_ string: String, linked: Bool) {
            text += string
            let visible = string.reduce(0) { $1.isWhitespace ? $0 : $0 + 1 }
            characters += visible
            if linked { linkedCharacters += visible }
        }
        var linkShare: Double { characters == 0 ? 0 : Double(linkedCharacters) / Double(characters) }
    }

    private func visitContainer(_ element: XMLElement, context: Context) throws {
        let start = blocks.count
        var run = InlineRun()
        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else {
                if child.kind == .text, let string = child.stringValue { run.append(string, linked: false) }
                continue
            }
            let name = childElement.name?.lowercased() ?? ""
            if Self.blockTags.contains(name) || containsBlock(childElement) {
                flush(&run, context: context)
                try visitBlock(childElement, named: name, context: context)
            } else {
                gather(childElement, named: name, into: &run, linked: false)
            }
        }
        flush(&run, context: context)
        ranges[ObjectIdentifier(element)] = start..<blocks.count
    }

    private func visitBlock(_ element: XMLElement, named name: String, context: Context) throws {
        visited += 1
        if visited % 512 == 0 { try deadline.check() }

        let verdict = JunkFilter.verdict(for: element, named: name)
        if verdict == .skip { return }
        let start = blocks.count
        defer { if case let .suspect(isStrong) = verdict, blocks.count > start { suspects.append(Suspect(range: start..<blocks.count, isStrong: isStrong)) } }

        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            emitText(of: element, kind: .heading(level: Int(name.dropFirst()) ?? 2))
        case "p":
            emitText(of: element, kind: context.kind)
        case "pre":
            emitCode(of: element)
        case "li", "dt", "dd":
            var inner = context; inner.inList = true
            if containsBlock(element) { try visitContainer(element, context: inner) } else { emitText(of: element, kind: inner.kind) }
        case "blockquote":
            var inner = context; inner.inQuote = true
            try visitContainer(element, context: inner)
        case "table":
            // LaTeXML (arXiv) typesets display equations as tables. Shown as TeX, like code, they are readable and never judged.
            if (element.attribute(forName: "class")?.stringValue ?? "").contains("ltx_eqn") { emitCode(of: element) }
            else if isDataTable(element) { blocks.append(Block(kind: .table, text: "", weight: 0)) }
            else { try visitContainer(element, context: context) }
        default:
            try visitContainer(element, context: context)
        }
    }

    // MARK: Text

    /// Collects the text of one inline element, counting link text and images on the way.
    ///
    /// Only certain junk is dropped here. A *suspect* name on an inline element is ignored: inside a sentence it is part
    /// of the sentence, and inside `<pre>` (`isCode`) nothing is filtered at all, because syntax highlighters name
    /// their spans "comment" and "meta".
    private func gather(_ element: XMLElement, named name: String, into run: inout InlineRun, linked: Bool, isCode: Bool = false) {
        switch name {
        case "br": run.text.append(TextCleaner.lineBreak); return
        case "img": if JunkFilter.isCountable(image: element) { run.images += 1 }; return
        case "sup" where !isCode && JunkFilter.isNoteMarker(element): return
        default: break
        }
        if !isCode, JunkFilter.verdict(for: element, named: name) == .skip { return }
        let isLink = linked || (name == "a" && element.attribute(forName: "href") != nil)
        gatherChildren(of: element, into: &run, linked: isLink, isCode: isCode)
    }

    private func gatherChildren(of element: XMLElement, into run: inout InlineRun, linked: Bool = false, isCode: Bool = false) {
        for child in element.children ?? [] {
            if let childElement = child as? XMLElement {
                gather(childElement, named: childElement.name?.lowercased() ?? "", into: &run, linked: linked, isCode: isCode)
            } else if child.kind == .text, let string = child.stringValue {
                run.append(string, linked: linked)
            }
        }
    }

    private func emitText(of element: XMLElement, kind: Block.Kind) {
        var run = InlineRun()
        gatherChildren(of: element, into: &run)
        let text = TextCleaner.collapse(run.text)
        if case .heading = kind {
            // A "heading" that runs on for lines is a styled paragraph.
            if text.count > 200 { append(text, kind: .paragraph, linkShare: run.linkShare) }
            else if text.count >= 2 { blocks.append(Block(kind: kind, text: text, weight: 0)) }
        } else {
            append(text, kind: kind, linkShare: run.linkShare)
        }
        appendImages(run.images)
    }

    private func emitCode(of element: XMLElement) {
        var run = InlineRun()
        gatherChildren(of: element, into: &run, isCode: true)
        let text = TextCleaner.code(run.text)
        if !text.isEmpty { blocks.append(Block(kind: .code, text: text, weight: min(text.count, 400))) }
    }

    /// Loose inline content becomes paragraphs, split where the author wrote two or more `<br>` (older sites have no `<p>` at all).
    private func flush(_ run: inout InlineRun, context: Context) {
        defer { run = InlineRun() }
        appendImages(run.images)
        guard run.characters >= Self.minimumLooseTextLength else { return }
        for piece in TextCleaner.paragraphs(in: run.text) { append(piece, kind: context.kind, linkShare: run.linkShare) }
    }

    private func append(_ text: String, kind: Block.Kind, linkShare: Double) {
        guard !text.isEmpty, linkShare <= Self.maximumLinkShare, !JunkFilter.isLabel(text) else { return }
        let weight = text.count >= Self.minimumWeighedLength ? Int(Double(text.count) * (1 - linkShare)) : 0
        blocks.append(Block(kind: kind, text: text, weight: weight))
    }

    private func appendImages(_ count: Int) {
        for _ in 0..<count { blocks.append(Block(kind: .image, text: "", weight: 0)) }
    }

    // MARK: Structure tests

    /// True when an inline-looking element (`<span>`, `<font>`, `<a>`) wraps block content and must be walked as a container.
    private func containsBlock(_ element: XMLElement) -> Bool {
        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else { continue }
            if Self.blockTags.contains(childElement.name?.lowercased() ?? "") || containsBlock(childElement) { return true }
        }
        return false
    }

    /// Tables of data are counted and left out; tables used for page layout (older sites) are walked like any container.
    private func isDataTable(_ table: XMLElement) -> Bool {
        if table.attribute(forName: "role")?.stringValue == "presentation" { return false }
        var rows = 0, cells = 0, hasHeader = false
        func scan(_ element: XMLElement) {
            for child in element.children ?? [] {
                guard let childElement = child as? XMLElement else { continue }
                switch childElement.name?.lowercased() ?? "" {
                case "table": continue
                case "tr": rows += 1
                case "td": cells += 1
                case "th": cells += 1; hasHeader = true
                case "thead", "caption": hasHeader = true
                default: break
                }
                scan(childElement)
            }
        }
        scan(table)
        if hasHeader { return true }
        guard rows >= 2, cells >= 4 else { return false }
        // Short cells that are mostly links are navigation ("Previous: … Next: …"), which the link rule then drops.
        var run = InlineRun()
        gatherChildren(of: table, into: &run)
        return run.characters / cells < 150 && run.linkShare <= Self.maximumLinkShare
    }
}
