import BeamModels
import SwiftUI

/// First-launch setup and the connection prompt raised by a submitted search. Connecting validates and saves the
/// key; skipping keeps the chronological reader usable and leaves a waiting search in its field.
struct KeySheet: View {
    @Bindable var model: AppModel

    @State private var key = ""
    @State private var status = ""
    @State private var isChecking = false
    @FocusState private var isKeyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.isWelcomeKeySheet ? "Welcome to Beam" : "Connect to TypeSafe").font(.title2.weight(.semibold))
            if model.isWelcomeKeySheet {
                Text(ShellCopy.welcomeIntroduction)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(ShellCopy.connectionInstructions)
                if let url = ShellLinks.getKey { Link(ShellCopy.getKeyLink, destination: url) }
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.backend.prejudgesTopResults ? ShellCopy.disclosureWithTopThree : ShellCopy.disclosure)
                if let url = ShellLinks.dataRetention { Link(ShellCopy.retentionLink, destination: url) }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            SecureField("Paste your TypeSafe API key", text: $key)
                .textFieldStyle(.roundedBorder)
                .writingToolsBehavior(.disabled)
                .focused($isKeyFocused)
                .disabled(isChecking)
                .onSubmit(validate)
                .accessibilityLabel("TypeSafe API key")
            if !status.isEmpty {
                Text(status)
                    .foregroundStyle(isChecking ? .secondary : .primary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(ShellCopy.keyStorage).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(ShellCopy.plainReader).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(model.isWelcomeKeySheet ? "Use as a Reader" : "Not Now", role: .cancel) { model.cancelKeySheet() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isChecking)
                Button("Connect", action: validate).keyboardShortcut(.defaultAction).disabled(trimmedKey.isEmpty || isChecking)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            isKeyFocused = true
            if model.keyStatus != .missing { status = ShellCopy.connectionStatus(model.keyStatus) }
        }
        .onDisappear { key = "" }
        .onChange(of: key) { if !isChecking { status = "" } }
        .onChange(of: status) { Announcer.say(status) }
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func validate() {
        guard !trimmedKey.isEmpty, !isChecking else { return }
        isChecking = true
        status = ShellCopy.checkingKey
        let submittedKey = trimmedKey
        Task {
            // Only a validated and saved key closes setup and runs the sentence waiting in the field.
            let result = await model.setKey(submittedKey)
            status = ShellCopy.connectionStatus(result)
            if result == .valid { key = "" }
            isChecking = false
        }
    }
}
