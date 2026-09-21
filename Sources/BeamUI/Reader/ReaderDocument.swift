import AppKit
import BeamModels

/// The page as one immutable attributed string, plus where each passage landed in it.
///
/// The header (title and byline) is ordinary text in the storage, so it selects, copies and is read by VoiceOver in order.
/// A document is built once per article, phase and text size; the storage is never mutated afterwards,
/// which is what lets the text view cache paragraph frames once per layout pass.
struct ReaderDocument {
    struct Block {
        let passageIndex: Int
        let range: NSRange
        /// Headings and code are shown but never judged: no marks, no rails, not part of the viewport report.
        let isJudgeable: Bool
    }

    /// What decides whether a new document is needed. Judgments are not part of it: they never touch the storage.
    struct Identity: Equatable {
        let itemID: Int64
        let phase: ReaderPhase
        let title: String
        let byline: String
        let snippet: String
        let passages: [Passage]
        let metrics: ReaderMetrics
    }

    /// The value of the `.link` attribute on "Open Original". A marker, not a URL: the app decides what opening means.
    static let openOriginalLink = "beam-reader:open-original"

    let identity: Identity
    let text: NSAttributedString
    /// The hairline is drawn under this range; nil for pages without a byline (preview, failed, external).
    let bylineRange: NSRange?
    /// In document order.
    let blocks: [Block]

    static func identity(for snapshot: ReaderSnapshot, metrics: ReaderMetrics) -> Identity {
        Identity(itemID: snapshot.item.id, phase: snapshot.phase, title: snapshot.item.title,
                 byline: ReaderCopy.bylineLead(source: snapshot.sourceTitle, date: snapshot.item.published)
                    + (ReaderCopy.omitted(images: snapshot.omittedImages, tables: snapshot.omittedTables) ?? ""),
                 snippet: snapshot.item.snippet, passages: snapshot.phase == .ready ? snapshot.passages : [], metrics: metrics)
    }

    init(snapshot: ReaderSnapshot, metrics: ReaderMetrics) {
        let builder = ReaderDocumentBuilder(metrics: metrics)
        builder.addTitle(snapshot.item.title, isPreview: !Self.showsByline(in: snapshot.phase))
        var byline: NSRange?
        if Self.showsByline(in: snapshot.phase) {
            byline = builder.addByline(source: snapshot.sourceTitle, date: snapshot.item.published,
                                       omitted: ReaderCopy.omitted(images: snapshot.omittedImages, tables: snapshot.omittedTables))
        } else {
            builder.addSnippet(snapshot.item.snippet)
        }
        var blocks: [Block] = []
        if snapshot.phase == .ready {
            for (index, passage) in snapshot.passages.enumerated() {
                // Extractors often keep the page's own <h1>; the header already shows the title.
                if index == 0, passage.kind == .heading, passage.text.isSameTitle(as: snapshot.item.title) { continue }
                guard let range = builder.addPassage(passage) else { continue }
                blocks.append(Block(passageIndex: index, range: range, isJudgeable: passage.isJudgeable))
            }
        }
        identity = Self.identity(for: snapshot, metrics: metrics)
        text = builder.text
        bylineRange = byline
        self.blocks = blocks
    }

    /// An opened article carries "source · date · Open Original"; a preview or a failed article shows the snippet instead.
    private static func showsByline(in phase: ReaderPhase) -> Bool { phase == .loading || phase == .ready }
}

/// Appends styled paragraphs. Each paragraph style is fully specified here so the page never inherits a default.
private final class ReaderDocumentBuilder {
    let metrics: ReaderMetrics
    private let out = NSMutableAttributedString()

    init(metrics: ReaderMetrics) { self.metrics = metrics }

    var text: NSAttributedString { NSAttributedString(attributedString: out) }

    func addTitle(_ title: String, isPreview: Bool) {
        let font = ReaderTheme.serif(metrics.titleSize, weight: .semibold)
        let style = paragraphStyle(font: font, leading: font.naturalLineHeight + 3, after: isPreview ? metrics.previewSpacing : metrics.titleSpacingAfter)
        append(title, font: font, color: .labelColor, style: style)
    }

    func addByline(source: String, date: Date?, omitted: String?) -> NSRange {
        let font = NSFont.systemFont(ofSize: metrics.bylineSize)
        let style = paragraphStyle(font: font, leading: font.naturalLineHeight, after: metrics.headerSpacingAfter)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style]
        let start = out.length
        out.append(NSAttributedString(string: ReaderCopy.bylineLead(source: source, date: date), attributes: attributes))
        var link = attributes
        link[.link] = ReaderDocument.openOriginalLink
        out.append(NSAttributedString(string: ReaderCopy.openOriginal, attributes: link))
        if let omitted { out.append(NSAttributedString(string: " " + omitted, attributes: attributes)) }
        out.append(NSAttributedString(string: "\n", attributes: attributes))
        return NSRange(location: start, length: out.length - start)
    }

    func addSnippet(_ snippet: String) {
        let text = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let font = ReaderTheme.serif(metrics.textSize)
        append(text, font: font, color: .labelColor, style: paragraphStyle(font: font, leading: metrics.bodyLeading, after: metrics.paragraphSpacing))
    }

    /// Returns where the passage landed, or nil for a passage with no text.
    func addPassage(_ passage: Passage) -> NSRange? {
        let text = passage.text.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return nil }
        let start = out.length
        switch passage.kind {
        case .heading:
            let font = ReaderTheme.serif(metrics.headingSize, weight: .semibold)
            append(text, font: font, color: .labelColor,
                   style: paragraphStyle(font: font, leading: font.naturalLineHeight + 3, after: metrics.headingSpacingAfter, before: metrics.headingSpacingBefore))
        case .paragraph:
            let font = ReaderTheme.serif(metrics.textSize)
            append(text, font: font, color: .labelColor, style: paragraphStyle(font: font, leading: metrics.bodyLeading, after: metrics.paragraphSpacing))
        case .quote:
            // Indented, with no bar: a bar in the margin would read as a mark.
            let font = ReaderTheme.serif(metrics.textSize)
            append(text, font: font, color: .labelColor,
                   style: paragraphStyle(font: font, leading: metrics.bodyLeading, after: metrics.paragraphSpacing, indent: metrics.quoteIndent))
        case .listItem:
            let font = ReaderTheme.serif(metrics.textSize)
            let style = paragraphStyle(font: font, leading: metrics.bodyLeading, after: metrics.paragraphSpacing, indent: metrics.listIndent, firstLineIndent: 0)
            style.tabStops = [NSTextTab(textAlignment: .left, location: metrics.listIndent)]
            append("•\t" + text, font: font, color: .labelColor, style: style)
        case .code:
            // No box: the face alone says code.
            let font = ReaderTheme.mono(metrics.codeSize)
            append(text, font: font, color: .labelColor, style: paragraphStyle(font: font, leading: metrics.codeLeading, after: metrics.paragraphSpacing))
        }
        return NSRange(location: start, length: out.length - start)
    }

    /// A passage may hold line breaks (code always does). Every line becomes a real paragraph so copied text keeps
    /// plain newlines, but only the first carries the space before and only the last the space after.
    private func append(_ string: String, font: NSFont, color: NSColor, style: NSMutableParagraphStyle) {
        let lines = string.components(separatedBy: "\n")
        for (offset, line) in lines.enumerated() {
            var lineStyle: NSParagraphStyle = style
            if lines.count > 1, let copy = style.mutableCopy() as? NSMutableParagraphStyle {
                if offset > 0 { copy.paragraphSpacingBefore = 0 }
                if offset < lines.count - 1 { copy.paragraphSpacing = 0 }
                lineStyle = copy
            }
            out.append(NSAttributedString(string: line + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: lineStyle]))
        }
    }

    /// `leading` is the distance from baseline to baseline. It is reached with line spacing, not a fixed line height,
    /// so the text rect of a paragraph ends at its last descender and the tint outsets stay even above and below.
    /// `after` is the clear space between this paragraph's text and the next one's: TextKit adds the line spacing
    /// under the last line too, so it is taken back out. At 17 pt that leaves 14 pt, and two 5 pt tint outsets keep a 4 pt gap.
    private func paragraphStyle(font: NSFont, leading: CGFloat, after: CGFloat, before: CGFloat = 0,
                                indent: CGFloat = 0, firstLineIndent: CGFloat? = nil) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = max(leading - font.naturalLineHeight, 0)
        style.paragraphSpacing = max(after - style.lineSpacing, 0)
        style.paragraphSpacingBefore = before
        style.headIndent = indent
        style.firstLineHeadIndent = firstLineIndent ?? indent
        style.lineBreakStrategy = .standard
        return style
    }
}

private extension NSFont {
    /// What TextKit gives one line of this face before any line spacing.
    var naturalLineHeight: CGFloat { ascender - descender + leading }
}

private extension String {
    func isSameTitle(as other: String) -> Bool {
        func folded(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return folded(self) == folded(other)
    }
}
