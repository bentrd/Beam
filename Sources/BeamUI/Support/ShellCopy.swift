import BeamModels
import Foundation

/// The shell's own words, from DESIGN.md section 6. Status sentences about runs come from the backend inside `Foot`;
/// what is here are labels, prompts, help tags, and the two foot sentences only the window can know about.
enum ShellCopy {
    static let searchPrompt = "Describe what you want to read"
    static let pinHelp = "Pin this sentence"
    static let unpinHelp = "Unpin this sentence"
    static let pinLabel = "Pin sentence"
    static let unpinLabel = "Unpin sentence"

    static let allItems = "All Items"
    static let pins = "Pins"
    static let sources = "Sources"
    static let addSource = "Add Source"

    /// Said after the key sheet is cancelled with a sentence still waiting in the field.
    static let addKeyFoot = Foot("Add a key to search.", actionTitle: "Open Settings", action: .openSettings, isProminent: true)
    /// Said until the next action when a tenth pin is asked for.
    static let ninePinsFoot = Foot("Nine pins maximum", isProminent: true)

    static let disclosure = "To judge meaning, Beam sends your sentences, your sources' titles and snippets, and paragraphs of articles you open, to TypeSafe with your key."
    static let disclosureWithTopThree = "To judge meaning, Beam sends your sentences, your sources' titles and snippets, and paragraphs of articles you open or that rank in the top three, to TypeSafe with your key."
    static let retentionLink = "How TypeSafe keeps data"
    static let getKeyLink = "Get a key"
    static let checkingKey = "Checking…"
    static let keyRejected = "TypeSafe rejected this key"
    static let keyUnreachable = "Can't reach TypeSafe. Check your connection."

    static func couldNotRefresh(_ reason: String) -> String { "Couldn't refresh: \(reason)" }
    /// The help tag on a pin whose items are still unchecked after retries.
    static let notChecked = "Not checked"

    /// The words of a foot or empty-state text button when the backend names the action but not its words.
    /// `.checkOlder` has none: its sentence carries the count ("Check 1,200 older"), so only the engine can write it,
    /// and a button with no words is not drawn.
    static func title(for action: FootAction) -> String? {
        switch action {
        case .retry: return "Retry"
        case .openSettings: return "Open Settings"
        case .checkOlder: return nil
        case .findNarrower: return "Find something narrower."
        case .addSource: return addSource
        }
    }
}

/// Where the sheet's and Settings' two links lead.
enum ShellLinks {
    static let dataRetention = URL(string: "https://typesafe.ai/legal/privacy-policy")
    static let getKey = URL(string: "https://console.typesafe.ai/")
}
