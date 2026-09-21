import AppKit
import BeamModels
import SwiftUI

/// The reader's one-line foot: the status sentence (or the ask field) on the left, the counter slot on the right.
/// Opaque paper under a hairline, so it reads as the bottom edge of the page rather than as a bar over it.
struct ReaderFoot: View {
    let model: ReaderFootModel
    let isAskOpen: Bool
    let askOpeningText: String
    let askPrefill: String?
    let canStep: Bool
    var onButton: (ReaderFootModel.Button) -> Void
    var onAsk: (String) -> Void
    var onCloseAsk: (_ returnsFocus: Bool) -> Void
    var onStep: (Int) -> Void

    private static let swap = Animation.easeInOut(duration: 0.12)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .leading) {
                if isAskOpen {
                    ReaderAskField(openingText: askOpeningText, prefill: askPrefill, onAsk: onAsk, onNext: { onStep(1) }, onClose: onCloseAsk)
                        .frame(minWidth: 120, idealWidth: 300, maxWidth: 300)
                        .transition(.opacity)
                } else {
                    status.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            counter
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        // One line is 30 pt. A narrow pane wraps the sentence to two lines and the foot grows; it never truncates.
        .frame(minHeight: 30)
        .background(Color(nsColor: ReaderTheme.paper))
        .overlay(alignment: .top) { Divider() }
        .animation(Self.swap, value: isAskOpen)
        .animation(Self.swap, value: model)
    }

    /// The sentence, with its text button as the tail of the same line.
    private var status: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            if !model.status.isEmpty {
                Text(model.status)
                    .foregroundStyle(model.isProminent ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.disabled)
            }
            if let title = model.buttonTitle, let button = model.button {
                ReaderTextButton(title: title) { onButton(button) }
            }
        }
        .help(model.help ?? "")
        .accessibilityElement(children: .contain)
        .accessibilityValue(model.help ?? "")
    }

    @ViewBuilder private var counter: some View {
        if let text = model.counter {
            HStack(spacing: 8) {
                Text(text)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
                    .help(model.counterHelp ?? "")
                    .accessibilityValue(model.counterHelp ?? "")
                if model.showsChevrons {
                    ReaderStepper(isEnabled: canStep, onPrevious: { onStep(-1) }, onNext: { onStep(1) })
                }
            }
            .transition(.opacity)
        }
    }
}

/// A sentence's button: plain text in the accent colour, a real button in the key loop with a 24 pt hit height.
struct ReaderTextButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let needsUnderline = differentiateWithoutColor || ReaderAccent.isGraphiteOrYellow
        Button(action: action) {
            Text(title)
                .underline(needsUnderline)
                // Yellow belongs to hits alone, and graphite cannot be told from status text: both fall back to ink.
                .foregroundStyle(ReaderAccent.isGraphiteOrYellow ? Color(nsColor: .labelColor) : Color.accentColor)
                .fixedSize()
                .frame(minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Colour alone marks a text button, unless the user's accent cannot carry that.
enum ReaderAccent {
    static var isGraphiteOrYellow: Bool {
        guard let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return false }
        return accent.saturationComponent < 0.15 || ReaderSelection.isYellow(accent)
    }
}
