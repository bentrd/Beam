import AppKit
import BeamModels
import SwiftUI

/// The reader's one-line foot: the status sentence (or the ask field) on the left, the counter slot on the right.
/// It reads as the bottom edge of the page rather than as a bar over it.
struct ReaderFoot: View {
    let model: ReaderFootModel
    /// True when the foot is a bottom-aligned split-view accessory (DESIGN.md section 2): the system then owns the
    /// band — it fits it to the window's corners, and the paper behind the pane shows through it — so the foot draws
    /// no background and no hairline of its own. False in a window with no split view, where it draws both.
    var isAccessory = false
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
        .background { if !isAccessory { Color(nsColor: ReaderTheme.paper) } }
        .overlay(alignment: .top) { if !isAccessory { Divider() } }
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
                FootTextButton(title: title) { onButton(button) }
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
