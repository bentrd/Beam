import BeamModels
import SwiftUI

/// The one-line foot under the list. One sentence at a time, 12 pt; plain status is secondary, errors and sentences
/// with a button are in the label colour. At narrow widths the button drops to a second line: a foot never truncates.
/// Opaque, with a hairline above: status lives nowhere else.
struct ListFootView: View {
    let foot: Foot
    let perform: (FootAction) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 4) { sentence; button }
            VStack(alignment: .leading, spacing: 0) { sentence; button }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .padding(.horizontal, 16)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .top) { Divider() }
        // The settled sentence cross-fades in over 120 ms; the height never changes between states.
        .animation(.easeInOut(duration: 0.12), value: foot)
        .accessibilityElement(children: .contain)
    }

    private var sentence: some View {
        Text(sentenceText)
            .foregroundStyle(foot.isProminent ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help(foot.help ?? "")
            .accessibilityValue(foot.help ?? "")
            .id(sentenceText)
            .transition(.opacity)
    }

    @ViewBuilder private var button: some View {
        if let action = foot.action, let title = foot.actionTitle ?? ShellCopy.title(for: action) {
            FootTextButton(title: title) { perform(action) }
        }
    }

    /// A backend may spell the whole sentence out in `text` ("31 not checked. Retry"); the button's words are never said twice.
    private var sentenceText: String {
        guard foot.action != nil, let title = foot.actionTitle, foot.text.hasSuffix(title) else { return foot.text }
        return String(foot.text.dropLast(title.count)).trimmingCharacters(in: .whitespaces)
    }
}
