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
    static let getKeyLink = "Sign in to TypeSafe and create a key"
    static let checkingKey = "Checking your key…"
    static let keyRejected = "TypeSafe rejected this key. Create a new API key and try again."
    static let keyUnreachable = "Can't reach TypeSafe. Check your connection."
    static let welcomeIntroduction = "Beam brings your feeds and articles into one quiet reader. Describe what you want to read, then open articles with matching paragraphs highlighted."
    static let connectionInstructions = "Connect with an API key from your TypeSafe account to use Jev for search by meaning. Sign in or create an account, create a key, then paste it below."
    static let plainReader = "You can read and follow sources without connecting. Add a key later in Beam Settings."
    static let keyStorage = "Keys you connect here are stored securely in your macOS Keychain. Usage is billed to your TypeSafe account; Beam stops at $0.50 a day."

    static func connectionStatus(_ status: KeyStatus) -> String {
        switch status {
        case .valid: return "Connected to TypeSafe."
        case .missing: return "Not connected. Beam works as a plain reader."
        case .rejected: return keyRejected
        case .unreachable: return keyUnreachable
        case .storageError(let message): return "Can't access your Keychain. \(message)"
        }
    }

    static func couldNotRefresh(_ reason: String) -> String { "Couldn't refresh: \(reason)" }

    /// Beam's copy is English wherever it is read, so its groupings are: "1,200 items", never "1 200 items".
    /// The backends pin their own counts the same way, and a spoken count must match the foot beside it.
    private static let english = Locale(identifier: "en_US")
    static func number(_ value: Int) -> String { value.formatted(.number.locale(english)) }
    static func plural(_ count: Int, _ noun: String) -> String { "\(number(count)) \(count == 1 ? noun : noun + "s")" }

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
    static let getKey = URL(string: "https://console.typesafe.ai/keys")
}
