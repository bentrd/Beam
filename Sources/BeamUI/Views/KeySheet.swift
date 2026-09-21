import BeamModels
import SwiftUI

/// Raised by Return in the search field when there is no key: what Beam will send, where to read how it is kept,
/// a secure field, and nothing else. Continue validates the key; on success the sheet closes and the waiting sentence runs.
struct KeySheet: View {
    @Bindable var model: AppModel

    @State private var key = ""
    @State private var status = ""
    @State private var isChecking = false
    @FocusState private var isKeyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add your TypeSafe key").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                // The top-three clause appears only when the Settings toggle is on.
                Text(model.backend.prejudgesTopResults ? ShellCopy.disclosureWithTopThree : ShellCopy.disclosure)
                Text("Nothing has been sent yet.")
                if let url = ShellLinks.dataRetention { Link(ShellCopy.retentionLink, destination: url) }
            }
            .fixedSize(horizontal: false, vertical: true)

            SecureField("TypeSafe key", text: $key)
                .textFieldStyle(.roundedBorder)
                .writingToolsBehavior(.disabled)
                .focused($isKeyFocused)
                .onSubmit(validate)
            HStack(alignment: .firstTextBaseline) {
                Text(status).foregroundStyle(.secondary)
                Spacer()
                if let url = ShellLinks.getKey { Link(ShellCopy.getKeyLink, destination: url) }
            }
            .font(.callout)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelKeySheet() }.keyboardShortcut(.cancelAction)
                Button("Continue", action: validate).keyboardShortcut(.defaultAction).disabled(key.isEmpty || isChecking)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { isKeyFocused = true }
        .onChange(of: status) { Announcer.say(status) }
    }

    private func validate() {
        guard !key.isEmpty, !isChecking else { return }
        isChecking = true
        status = ShellCopy.checkingKey
        Task {
            // On success the model closes the sheet and runs the sentence that was waiting in the field.
            switch await model.setKey(key) {
            case .valid: model.isKeySheetPresented = false
            case .rejected, .missing: status = ShellCopy.keyRejected
            case .unreachable: status = ShellCopy.keyUnreachable
            }
            isChecking = false
        }
    }
}
