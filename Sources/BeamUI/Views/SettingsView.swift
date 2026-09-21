import AppKit
import BeamModels
import SwiftUI

/// The Settings scene, "Beam Settings": the key with its status, what is sent and the one privacy toggle, and today's spend.
/// A columns form with no boxed groups and no symbols. The key commits when editing ends; clearing the field removes it.
public struct SettingsView: View {
    @Bindable var model: AppModel

    /// Stands in for a stored key, which Beam never reads back out of the Keychain to show.
    private static let storedKeyMask = String(repeating: "•", count: 24)

    @State private var key = ""
    @State private var isChecking = false
    @State private var prejudgesTopResults = false
    @State private var dollarsToday = 0.0
    @FocusState private var isKeyFocused: Bool

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        Form {
            LabeledContent("TypeSafe key:") {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField("TypeSafe key", text: $key)
                        .labelsHidden()
                        .writingToolsBehavior(.disabled)
                        .focused($isKeyFocused)
                        .onSubmit(commitKey)
                        .frame(width: 300)
                    Text(keyStatusLine).foregroundStyle(.secondary)
                    if model.keyStatus != .missing { Text("Clear the field to remove the key.").foregroundStyle(.secondary) }
                }
            }
            LabeledContent("Privacy:") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(prejudgesTopResults ? ShellCopy.disclosureWithTopThree : ShellCopy.disclosure)
                    if let url = ShellLinks.dataRetention { Link(ShellCopy.retentionLink, destination: url) }
                    Toggle("Light up top results before I open them", isOn: $prejudgesTopResults)
                        .toggleStyle(.checkbox)
                        .padding(.top, 4)
                    Text("Sends paragraphs of the top three results before you open them.").foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Usage:") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About \(dollarsToday.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))) today")
                    Text("Beam stops at $0.50 a day.").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.columns)
        .padding(20)
        .frame(width: 520)
        .navigationTitle("Beam Settings")
        .background(SettingsWindowButtons())
        .task {
            prejudgesTopResults = model.backend.prejudgesTopResults
            dollarsToday = await model.backend.dollarsToday()
            key = model.keyStatus == .missing ? "" : Self.storedKeyMask
        }
        .onChange(of: prejudgesTopResults) { model.backend.prejudgesTopResults = prejudgesTopResults }
        .onChange(of: isKeyFocused) { if !isKeyFocused { commitKey() } }
        .onChange(of: key) { old, new in
            // Typing into the mask means a new key, not an addition to twenty-four bullets.
            guard old == Self.storedKeyMask, new != old else { return }
            key = new.hasPrefix(old) ? String(new.dropFirst(old.count)) : (old.hasPrefix(new) ? "" : new)
        }
        .onChange(of: keyStatusLine) { Announcer.say(keyStatusLine) }
    }

    private var keyStatusLine: String {
        if isChecking { return ShellCopy.checkingKey }
        switch model.keyStatus {
        case .valid: return "Key works. Stored in your Keychain."
        case .missing: return "No key. Beam works as a plain reader."
        case .rejected: return ShellCopy.keyRejected
        case .unreachable: return ShellCopy.keyUnreachable
        }
    }

    private func commitKey() {
        guard key != Self.storedKeyMask, !isChecking, !(key.isEmpty && model.keyStatus == .missing) else { return }
        isChecking = true
        Task {
            let status = await model.setKey(key.isEmpty ? nil : key)
            isChecking = false
            if status != .missing { key = Self.storedKeyMask }
        }
    }
}

/// A Settings window has no use for minimise or zoom.
private struct SettingsWindowButtons: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.standardWindowButton(.miniaturizeButton)?.isEnabled = false
            view.window?.standardWindowButton(.zoomButton)?.isEnabled = false
        }
    }
}
