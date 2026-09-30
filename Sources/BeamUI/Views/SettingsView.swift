import AppKit
import BeamModels
import SwiftUI

/// The Settings scene: explicit connection controls, what is sent, the privacy toggle, and today's spend.
/// A secure draft is always empty initially; editing it never replaces or removes a saved connection.
public struct SettingsView: View {
    @Bindable var model: AppModel

    @State private var key = ""
    @State private var status = ""
    @State private var isChecking = false
    @State private var prejudgesTopResults = false
    @State private var dollarsToday = 0.0
    @FocusState private var isKeyFocused: Bool

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        Form {
            LabeledContent("TypeSafe:") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ShellCopy.connectionStatus(model.keyStatus))
                    Text("Jev powers search by meaning and matching article passages.")
                        .foregroundStyle(.secondary)
                    if let url = ShellLinks.getKey { Link(ShellCopy.getKeyLink, destination: url) }
                    SecureField(model.keyStatus == .valid ? "Paste a replacement API key" : "Paste your TypeSafe API key", text: $key)
                        .labelsHidden()
                        .writingToolsBehavior(.disabled)
                        .focused($isKeyFocused)
                        .disabled(isChecking)
                        .onSubmit(connect)
                        .accessibilityLabel("TypeSafe API key")
                    HStack {
                        Button(model.keyStatus == .valid ? "Replace Key" : "Connect", action: connect)
                            .disabled(trimmedKey.isEmpty || isChecking)
                        if model.keyStatus != .missing {
                            Button("Disconnect", action: disconnect).disabled(isChecking)
                        }
                    }
                    if !status.isEmpty {
                        Text(status).foregroundStyle(isChecking ? .secondary : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Keys you connect here are stored securely in your macOS Keychain.")
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
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
                    Text("Usage is billed to your TypeSafe account. Beam stops at $0.50 a day.").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Appearance:") {
                Picker("Highlight color", selection: Binding(get: { model.preferences.highlightColor },
                                                               set: { model.preferences.highlightColor = $0 })) {
                    ForEach(HighlightColor.allCases) { color in
                        Text(color.title).tag(color)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Highlight color")
            }
        }
        .formStyle(.columns)
        .padding(20)
        .frame(width: 560)
        .navigationTitle("Beam Settings")
        .background(SettingsWindowButtons())
        .task {
            await model.refreshConnectionStatus()
            prejudgesTopResults = model.backend.prejudgesTopResults
            dollarsToday = await model.backend.dollarsToday()
        }
        .onChange(of: prejudgesTopResults) { model.backend.prejudgesTopResults = prejudgesTopResults }
        .onChange(of: key) { if !isChecking { status = "" } }
        .onChange(of: status) { Announcer.say(status) }
        .onDisappear { key = ""; status = "" }
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func connect() {
        guard !trimmedKey.isEmpty, !isChecking else { return }
        isChecking = true
        status = ShellCopy.checkingKey
        let submittedKey = trimmedKey
        Task {
            let result = await model.setKey(submittedKey)
            status = ShellCopy.connectionStatus(result)
            if result == .valid { key = "" }
            isChecking = false
            dollarsToday = await model.backend.dollarsToday()
        }
    }

    private func disconnect() {
        guard !isChecking else { return }
        isChecking = true
        status = "Disconnecting…"
        Task {
            let result = await model.setKey(nil)
            switch result {
            case .missing:
                key = ""
                status = "Disconnected. Your feeds and saved articles remain available."
            case .valid:
                key = ""
                status = "Saved key removed. Beam is still using a development environment key."
            default: status = ShellCopy.connectionStatus(result)
            }
            isChecking = false
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
