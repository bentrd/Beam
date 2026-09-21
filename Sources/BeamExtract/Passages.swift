import BeamModels
import Foundation

/// Turns blocks into the passages Beam shows and judges (PRODUCT.md section 6).
///
/// The rules exist for the judge as much as for the page: a passage under 40 characters ("Why?") cannot be about
/// anything on its own, and one over 1,200 lights up half a screen for one relevant sentence. Headings and code are
/// kept for reading but are never judged (`Passage.isJudgeable` is false for their kinds).
public enum Passages {
    /// Judgeable passages shorter than this merge into a neighbour.
    public static let minimumLength = 40
    /// Judgeable passages longer than this are split at a sentence end.
    public static let maximumLength = 1200
    /// An article never has more passages than this; the rest of a very long page is left to Open Original.
    public static let maximumCount = 400

    /// Merged list items stay on their own lines. A line separator (not a newline) keeps the passage one paragraph
    /// for the text system, so it is still tinted and measured as one.
    static let listItemSeparator = "\u{2028}"

    /// Plain text from a feed (an arXiv abstract, a text-only entry): blank lines separate paragraphs, single
    /// newlines are hard wraps.
    public static func fromPlainText(_ text: String) -> [Passage] {
        var paragraphs: [String] = [""]
        for line in text.components(separatedBy: .newlines) {
            if line.allSatisfy(\.isWhitespace) { paragraphs.append("") } else { paragraphs[paragraphs.count - 1] += line + " " }
        }
        return assemble(paragraphs.map { Block(kind: .paragraph, text: TextCleaner.collapse($0), weight: 0) }.filter { !$0.text.isEmpty })
    }

    static func assemble(_ blocks: [Block], titles: [String] = []) -> [Passage] {
        var drafts = blocks.filter { $0.kind != .image && $0.kind != .table }
        drafts = droppingTitleHeadings(drafts, titles: titles)
        drafts = mergingShort(drafts)
        drafts = drafts.flatMap { block -> [Block] in
            guard block.isBody, block.kind != .code else { return [block] }
            return split(block.text).map { Block(kind: block.kind, text: $0, weight: 0) }
        }
        drafts = droppingEmptySections(drafts)
        if drafts.count > maximumCount { drafts = droppingEmptySections(Array(drafts.prefix(maximumCount))) }

        var section = ""
        return drafts.map { block in
            let passage = Passage(kind: kind(of: block), text: block.text, section: section)
            if case .heading = block.kind { section = block.text }
            return passage
        }
    }

    // MARK: Rules

    /// The reader already shows the item's title above the article; a first heading that repeats it is noise.
    private static func droppingTitleHeadings(_ blocks: [Block], titles: [String]) -> [Block] {
        let known = titles.map(normalized).filter { $0.count >= 8 }
        guard !known.isEmpty else { return blocks }
        let firstBody = blocks.firstIndex(where: \.isBody) ?? blocks.count
        return blocks.enumerated().filter { index, block in
            guard index < firstBody, case .heading = block.kind else { return true }
            let heading = normalized(block.text)
            return !(heading.count >= 8 && known.contains { $0 == heading || $0.contains(heading) || heading.contains($0) })
        }.map(\.element)
    }

    /// A short passage joins the next one of its kind; failing that the previous one; failing that it stands alone
    /// (a lone "Deprecated." under a heading is still the author's text). Headings and code are walls.
    /// Short paragraphs above the first heading or full passage are the exception: up there they are datelines and
    /// bylines ("31st December 2024", "July 2023"), and merged forward they would open the article's first paragraph.
    private static func mergingShort(_ blocks: [Block]) -> [Block] {
        let hasFullPassage = blocks.contains { $0.isBody && $0.text.count >= minimumLength }
        let lead = hasFullPassage ? blocks.firstIndex { !$0.isBody || $0.text.count >= minimumLength } ?? 0 : 0
        var result: [Block] = []
        var carried: Block?
        func joined(_ first: Block, _ second: Block) -> Block {
            Block(kind: first.kind, text: first.text + (first.kind == .listItem ? listItemSeparator : " ") + second.text, weight: 0)
        }
        func settle() {
            guard let short = carried else { return }
            carried = nil
            if let last = result.last, last.kind == short.kind, last.text.count + short.text.count < maximumLength { result[result.count - 1] = joined(last, short) }
            else { result.append(short) }
        }
        for (index, block) in blocks.enumerated() {
            guard block.isBody, block.kind != .code else { settle(); result.append(block); continue }
            if index < lead, block.kind == .paragraph { continue }
            var current = block
            if let short = carried {
                if short.kind == current.kind { current = joined(short, current); carried = nil } else { settle() }
            }
            if current.text.count < minimumLength { carried = current } else { result.append(current) }
        }
        settle()
        return result
    }

    /// Pieces of roughly equal size, each ending at a sentence end and none longer than `maximumLength`.
    static func split(_ text: String) -> [String] {
        guard text.count > maximumLength else { return [text] }
        let target = text.count / Int((Double(text.count) / Double(maximumLength)).rounded(.up)) + 1
        var pieces: [String] = [], current = ""
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences]) { sentence, _, _, _ in
            guard let sentence else { return }
            if !current.isEmpty, current.count + sentence.count > maximumLength { pieces.append(current); current = "" }
            for chunk in hardWrapped(sentence) {
                if !current.isEmpty, current.count + chunk.count > maximumLength { pieces.append(current); current = "" }
                current += chunk
            }
            if current.count >= target { pieces.append(current); current = "" }
        }
        if !current.isEmpty {
            // A short tail reads better attached to the piece before it than standing alone.
            if let last = pieces.last, current.count < minimumLength * 5, last.count + current.count <= maximumLength { pieces[pieces.count - 1] = last + current }
            else { pieces.append(current) }
        }
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// A single sentence longer than the limit (legal text, or text with no punctuation) breaks at a word boundary.
    private static func hardWrapped(_ sentence: String) -> [String] {
        guard sentence.count > maximumLength else { return [sentence] }
        var chunks: [String] = [], current = ""
        for word in sentence.split(separator: " ", omittingEmptySubsequences: false) {
            if current.count + word.count + 1 > maximumLength, !current.isEmpty { chunks.append(current); current = "" }
            current += word + " "
            while current.count > maximumLength { chunks.append(String(current.prefix(maximumLength))); current = String(current.dropFirst(maximumLength)) }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// A heading with nothing under it (its section was a reference list, a gallery, a table) would promise text that is not there.
    private static func droppingEmptySections(_ blocks: [Block]) -> [Block] {
        blocks.enumerated().filter { index, block in
            guard case let .heading(level) = block.kind else { return true }
            for later in blocks[(index + 1)...] {
                guard case let .heading(laterLevel) = later.kind else { return true }
                if laterLevel <= level { return false }
            }
            return false
        }.map(\.element)
    }

    private static func kind(of block: Block) -> Passage.Kind {
        switch block.kind {
        case .heading: return .heading
        case .quote: return .quote
        case .listItem: return .listItem
        case .code: return .code
        case .paragraph, .image, .table: return .paragraph
        }
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }
}
