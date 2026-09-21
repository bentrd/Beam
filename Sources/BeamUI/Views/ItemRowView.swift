import BeamModels
import SwiftUI

/// One result: the mark, the title (two lines at most), then "source · age". No badges, percentages, hover or accessories.
/// Unread titles are in the label colour and read ones in the secondary label colour; nothing else tells them apart.
struct ItemRowView: View {
    let row: Row
    /// 1-based rank in the list, spoken by VoiceOver ("3 of 38"). A probability never is.
    let position: Int
    let count: Int
    /// A row that just arrived fades in over 150 ms; opacity is the only motion in the list.
    let isFresh: Bool

    @Environment(\.backgroundProminence) private var backgroundProminence
    @State private var hasAppeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(markColor)
                .frame(width: 4, height: 12)
                .padding(.top, 2.5)
                .opacity(row.isMarked ? 1 : 0)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.item.title)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(row.item.read ? .secondary : .primary)
                Text(byline)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isFresh && !hasAppeared ? 0 : 1)
        .onAppear {
            guard isFresh else { return }
            withAnimation(.easeOut(duration: 0.15)) { hasAppeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The mark is `hitInk` at full strength, and takes the selected text colour on an emphasised selection.
    private var markColor: Color {
        backgroundProminence == .increased ? Color(nsColor: .alternateSelectedControlTextColor) : Color(nsColor: ReaderTheme.hitInk)
    }

    /// "Hacker News · 2h"; with no date the source stands alone.
    private var byline: String {
        guard let published = row.item.published else { return row.sourceTitle }
        return "\(row.sourceTitle) · \(Age.short(since: published))"
    }

    /// "{title}, {source}, {age}, 3 of 38", then "unread" where it applies.
    private var accessibilityLabel: String {
        var parts = [row.item.title, row.sourceTitle]
        if let published = row.item.published { parts.append(Age.spoken(since: published)) }
        parts.append("\(position) of \(count)")
        if !row.item.read { parts.append("unread") }
        return parts.joined(separator: ", ")
    }
}
