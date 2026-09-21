import Foundation

/// Chooses which slice of the walked blocks is the article.
///
/// The spike scored each paragraph's parent and picked the best one, which returns a single `<section>` of a page
/// whose article is divided into sections (every arXiv HTML paper, most documentation). Beam instead starts from the
/// widest trustworthy scope and narrows while one child still holds nearly all of the text, so the failure mode is a
/// little furniture around a complete article, never a clean fragment of one. PRODUCT.md measures extraction by
/// how much of the reference text is kept, which is the same preference.
struct ContentSelector {
    /// A child must hold this share of its parent's text for the parent to be given up in its favour.
    static let narrowingShare = 0.7
    /// Paragraphs sitting directly in a container, beside its child containers, mean the container *is* the article:
    /// above this share of its text, or this much text outright (a standfirst, a short post above long footnotes).
    static let directTextShare = 0.05
    static let directTextWeight = 200
    /// About 150 words: less than this is not an article scope.
    static let minimumScopeWeight = 900
    /// A weak suspect is dropped only while it is smaller than this share of the page.
    static let weakSuspectShare = 0.25

    private let blocks: [Block]
    private let ranges: [ObjectIdentifier: Range<Int>]
    /// Prefix sums of kept block weights, so any container is weighed in O(1).
    private var sums: [Int] = []
    private(set) var isKept: [Bool]

    init(blocks: [Block], ranges: [ObjectIdentifier: Range<Int>], suspects: [BlockWalker.Suspect]) {
        self.blocks = blocks; self.ranges = ranges
        isKept = Array(repeating: true, count: blocks.count)
        rebuildSums()
        resolve(suspects)
    }

    func weight(of range: Range<Int>) -> Int { sums[range.upperBound] - sums[range.lowerBound] }
    func weight(of node: XMLNode) -> Int { ranges[ObjectIdentifier(node)].map(weight(of:)) ?? 0 }

    /// Strong suspects ("comments") go unless nothing readable would remain; weak ones ("share", "meta") go only while
    /// small. Outermost first: when a wrapper with an unlucky name is kept, the suspects inside it are still judged.
    private mutating func resolve(_ suspects: [BlockWalker.Suspect]) {
        let pageWeight = weight(of: 0..<blocks.count)
        let ordered = suspects.sorted { ($0.range.lowerBound, $1.range.upperBound) < ($1.range.lowerBound, $0.range.upperBound) }
        var removedUpTo = 0
        for suspect in ordered where suspect.range.lowerBound >= removedUpTo {
            let own = weight(of: suspect.range)
            let remaining = weight(of: 0..<blocks.count) - own
            let drop = suspect.isStrong ? remaining >= Self.minimumScopeWeight
                                        : Double(own) < Double(pageWeight) * Self.weakSuspectShare
            guard drop else { continue }
            for index in suspect.range { isKept[index] = false }
            removedUpTo = suspect.range.upperBound
            rebuildSums()
        }
    }

    private mutating func rebuildSums() {
        sums = [0]
        sums.reserveCapacity(blocks.count + 1)
        for (index, block) in blocks.enumerated() { sums.append(sums[index] + (isKept[index] ? block.weight : 0)) }
    }

    // MARK: Selection

    func select(in document: XMLDocument, body: XMLElement) -> Range<Int> {
        var current: XMLNode = scope(in: document, body: body)
        while let next = narrowed(from: current) { current = next }
        return ranges[ObjectIdentifier(current)] ?? 0..<blocks.count
    }

    /// The widest container worth trusting: schema.org's `articleBody`, the page's one dominant `<article>`, `<main>`, else `<body>`.
    private func scope(in document: XMLDocument, body: XMLElement) -> XMLNode {
        func nodes(_ xpath: String) -> [XMLNode] { ((try? document.nodes(forXPath: xpath)) ?? []).filter { ranges[ObjectIdentifier($0)] != nil } }
        let marker = HTMLPreprocessor.markerAttribute

        let bodies = nodes("//*[@itemprop='articleBody']")
        if bodies.count == 1, weight(of: bodies[0]) >= Self.minimumScopeWeight { return bodies[0] }

        let articles = nodes("//*[@\(marker)='article'][not(ancestor::*[@\(marker)='article'])]").sorted { weight(of: $0) > weight(of: $1) }
        if let first = articles.first, weight(of: first) >= Self.minimumScopeWeight,
           weight(of: first) * 4 >= weight(of: body),
           articles.count == 1 || weight(of: first) >= 2 * weight(of: articles[1]) { return first }

        if let main = nodes("//*[@\(marker)='main' or @role='main']").max(by: { weight(of: $0) < weight(of: $1) }),
           weight(of: main) >= Self.minimumScopeWeight, weight(of: main) * 2 >= weight(of: body) { return main }
        return body
    }

    private func narrowed(from node: XMLNode) -> XMLNode? {
        let total = weight(of: node)
        let children = (node.children ?? []).filter { ranges[ObjectIdentifier($0)] != nil && weight(of: $0) > 0 }
        guard total > 0, let heaviest = children.max(by: { weight(of: $0) < weight(of: $1) }) else { return nil }
        guard Double(weight(of: heaviest)) >= Double(total) * Self.narrowingShare else { return nil }

        let direct = total - children.reduce(0) { $0 + weight(of: $1) }
        if direct >= Self.directTextWeight || Double(direct) >= Double(total) * Self.directTextShare { return nil }
        // Notes can outweigh the post they belong to, but they are never the article on their own.
        if Self.appendixNames.contains(where: signature(heaviest).names.contains) { return nil }
        // Siblings built the same way (section after section) are parts of one article, however uneven their sizes.
        let shape = signature(heaviest)
        if shape.hasClassOrMarker, children.contains(where: { $0 !== heaviest && signature($0).isBuiltLike(shape) }) { return nil }
        return heaviest
    }

    private static let appendixNames = ["footnote", "endnote", "appendix"]

    private struct Signature { let name: String; let classes: String; let identifier: String; let marker: String
        var hasClassOrMarker: Bool { !classes.isEmpty || !marker.isEmpty }
        var names: String { (classes + " " + identifier).lowercased() }
        func isBuiltLike(_ other: Signature) -> Bool { name == other.name && classes == other.classes && marker == other.marker }
    }

    private func signature(_ node: XMLNode) -> Signature {
        let element = node as? XMLElement
        return Signature(name: node.name?.lowercased() ?? "",
                         classes: element?.attribute(forName: "class")?.stringValue ?? "",
                         identifier: element?.attribute(forName: "id")?.stringValue ?? "",
                         marker: element?.attribute(forName: HTMLPreprocessor.markerAttribute)?.stringValue ?? "")
    }
}
