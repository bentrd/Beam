import BeamModels
import Foundation

/// Every foot and empty sentence the fake backend can say, word for word from DESIGN.md section 6.
/// A sentence's text button is carried apart (`Foot.actionTitle`), so the text here never includes it.
enum FakeFeet {
    // MARK: List

    static let addKey = Foot("Add a key to search.", actionTitle: "Open Settings", action: .openSettings, isProminent: true)
    static let keyRejected = Foot("TypeSafe rejected this key.", actionTitle: "Open Settings", action: .openSettings, isProminent: true)
    static let dailyLimit = Foot("Daily limit reached. Resets at midnight.", isProminent: true)
    static let offline = Foot("Offline. Showing what was already checked.", isProminent: true)
    static let stopped = Foot("Stopped after repeated errors.", actionTitle: "Retry", action: .retry, isProminent: true)
    static let exclusions = Foot("Exclusions, amounts and dates aren't judged.")

    static func notChecked(_ count: Int) -> Foot {
        Foot("\(number(count)) not checked.", actionTitle: "Retry", action: .retry, isProminent: true)
    }
    static func couldNotRefresh(_ reason: String) -> Foot {
        Foot("Couldn't refresh: \(reason).", actionTitle: "Retry", action: .retry, isProminent: true)
    }
    static func items(_ count: Int, in source: String? = nil) -> Foot {
        Foot(plural(count, "item") + (source.map { " in \($0)" } ?? ""))
    }
    static func checking(_ count: Int) -> Foot { Foot("Checking \(plural(count, "item"))") }
    static func progress(_ checked: Int, of total: Int) -> Foot { Foot("\(number(checked)) of \(number(total)) checked") }
    static func checked(_ count: Int) -> Foot { Foot("\(plural(count, "item")) checked") }
    static func newest(_ checked: Int, of total: Int, older: Int) -> Foot {
        Foot("Newest \(number(checked)) of \(number(total)) checked.", actionTitle: "Check \(number(older)) older",
             action: .checkOlder, isProminent: true)
    }

    static func nothingFound(in checked: Int) -> String { "Nothing found in \(plural(checked, "item")) checked" }
    static let gettingSources = "Getting your sources"
    static let noSources = "No sources yet."
    static let noItems = "No items yet."

    // MARK: Reader

    static let returnToRead = Foot("Return to read")
    static let returnToOpenInBrowser = Foot("Return to open in your browser")
    static let codeNotChecked = "Code not checked."

    static func checkingParagraphs(_ count: Int) -> Foot { Foot("Checking \(plural(count, "paragraph"))") }
    static func paragraphProgress(_ checked: Int, of total: Int, retry: Bool) -> Foot {
        let text = "\(number(checked)) of \(number(total)) checked"
        return retry ? Foot(text + ".", actionTitle: "Retry", action: .retry, isProminent: true) : Foot(text)
    }
    static func found(_ found: Int, unsure: Int) -> String {
        [found > 0 ? "\(number(found)) found" : nil, unsure > 0 ? "\(number(unsure)) unsure" : nil].compactMap { $0 }.joined(separator: ", ")
    }
    static func nothingFound(inParagraphs checked: Int, matchedByTitle: Bool) -> String {
        (matchedByTitle ? "Matched by title. " : "") + "Nothing found in \(plural(checked, "paragraph")) checked"
    }
    /// The count lives in the help tag and the accessibility value, never in the sentence.
    static func saturated(found: Int, of checked: Int) -> Foot {
        Foot("Most of this article is about this.", actionTitle: "Find something narrower.", action: .findNarrower,
             isProminent: true, help: "\(number(found)) of \(plural(checked, "paragraph"))")
    }

    // The ask field's short forms: while it is open the status has the width of the counter slot.
    static let askChecking = Foot("Checking")
    static func askNothingFound(in checked: Int) -> Foot { Foot("Nothing found in \(number(checked)) checked") }
    static func askSaturated(found: Int, of checked: Int) -> Foot {
        Foot("Most of this article is about this", help: "\(number(found)) of \(plural(checked, "paragraph"))")
    }

    // MARK: Numbers

    private static let english = Locale(identifier: "en_US")
    static func number(_ value: Int) -> String { value.formatted(.number.locale(english)) }
    static func plural(_ count: Int, _ noun: String) -> String { "\(number(count)) \(count == 1 ? noun : noun + "s")" }
}
