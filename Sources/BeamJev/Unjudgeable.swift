import Foundation

/// What makes a sentence more than a topic. The judge reads one title or one paragraph literally:
/// it cannot subtract ("AI but not LLMs" lights LLM posts), compare a number ("under 3B parameters")
/// or know what day it is ("this week").
public enum UnjudgeableReason: String, Hashable, Sendable {
    case exclusion, amount, date
}

/// Local, deliberately conservative detection in English and French, the two languages the owner writes.
/// A miss sends a sentence the judge half-understands; a false trigger hides every result behind "unsure".
/// The second is worse, so rules match whole words only, never inside a compound ("sans-serif", "no-code"),
/// never inside a name ("Open Sans"), and amounts and years need a comparative beside them
/// ("iPhone 17" and "WWDC 2025" are topics).
enum Unjudgeable {
    static func reason(in cleaned: String) -> UnjudgeableReason? {
        let words = words(of: cleaned)
        let texts = words.map(\.text)
        if hasExclusion(words) { return .exclusion }
        if hasAmount(texts) { return .amount }
        if hasDate(texts) { return .date }
        return nil
    }

    // MARK: Words

    struct Word {
        /// Lowercased and accent-free, for matching.
        let text: String
        /// Written "Sans" or "No", as opposed to "sans", "no" or an emphatic "NOT".
        let isTitleCased: Bool
    }

    /// Hyphenated compounds stay whole so they match no word list, and so do "yes/no" and "and/or".
    /// French elisions are dropped ("l'année" reads "annee") while "aujourd'hui" and "aren't" stay whole.
    static func words(of cleaned: String) -> [Word] {
        cleaned
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2010}", with: "-")
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .split(whereSeparator: { $0.isWhitespace || separators.contains($0) })
            .map { $0.trimmingCharacters(in: edgePunctuation) }
            .map { written in
                let folded = written.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                let rest = written.dropFirst()
                let isTitleCased = written.first?.isUppercase == true && rest.contains(where: \.isLowercase) && !rest.contains(where: \.isUppercase)
                return Word(text: droppingElision(folded), isTitleCased: isTitleCased)
            }
            .filter { !$0.text.isEmpty }
    }

    private static let separators: Set<Character> = [",", ";", ":", "(", ")", "[", "]", "{", "}", "!", "?", "|", "\u{2026}", "\u{00AB}", "\u{00BB}"]
    private static let edgePunctuation = CharacterSet(charactersIn: ".'")
    private static let elisions: Set<String> = ["l", "d", "j", "n", "s", "c", "m", "t", "qu"]

    private static func droppingElision(_ word: String) -> String {
        guard let apostrophe = word.firstIndex(of: "'"), elisions.contains(String(word[..<apostrophe])) else { return word }
        return String(word[word.index(after: apostrophe)...])
    }

    // MARK: Exclusions

    private static let exclusionWords: Set<String> = [
        "not", "no", "without", "except", "excluding", "exclude",
        "sans", "sauf", "pas", "non", "excepte", "hormis",
    ]
    private static let exclusionPhrases = [["other", "than"], ["autre", "que"], ["autres", "que"]]

    private static func hasExclusion(_ words: [Word]) -> Bool {
        let texts = words.map(\.text)
        for (index, word) in words.enumerated() {
            let text = word.text
            // The search-engine habit: "rust -crypto".
            if text.hasPrefix("-"), text.count > 2, text.dropFirst().allSatisfy(\.isLetter) { return true }
            // An exclusion needs something to exclude: "why not" and "Dr. No" end the sentence.
            guard index < words.count - 1 else { continue }
            if text.hasSuffix("n't") { return true }
            guard exclusionWords.contains(text) else { continue }
            // Capitalised in mid-sentence, or opening a run of capitalised words, it belongs to a name: "Open Sans", "No Man's Sky".
            if word.isTitleCased, index > 0 || words[index + 1].isTitleCased { continue }
            // "sans serif" written with a space is the typeface, not "without serif".
            if text == "sans", texts[index + 1].hasPrefix("serif") { continue }
            return true
        }
        return exclusionPhrases.contains { contains($0, in: texts) }
    }

    // MARK: Amounts

    private static let comparatives: Set<String> = ["under", "over", "below", "above", "between", "than", "exceeding", "entre"]
    private static let comparativePhrases = [
        ["at", "least"], ["at", "most"], ["up", "to"],
        ["moins", "de"], ["plus", "de"], ["au", "moins"], ["au", "plus"], ["jusqu'a"],
        ["inferieur", "a"], ["inferieure", "a"], ["inferieurs", "a"], ["inferieures", "a"],
        ["superieur", "a"], ["superieure", "a"], ["superieurs", "a"], ["superieures", "a"],
    ]
    private static let comparisonSigns: Set<Character> = ["<", ">", "\u{2264}", "\u{2265}", "="]

    private static func hasAmount(_ words: [String]) -> Bool {
        for (index, word) in words.enumerated() {
            let next = index + 1 < words.count ? words[index + 1] : ""
            if comparatives.contains(word), isNumber(next) { return true }
            // "10+ years"
            if word.hasSuffix("+"), word.count > 1, word.dropLast().allSatisfy(\.isNumber) { return true }
            // "<3B", "< 3B", ">= 10"; but "<3" alone is a heart, and "=>" is an arrow.
            if let first = word.first, first != "=", comparisonSigns.contains(first), word != "<3" {
                let rest = String(word.drop(while: comparisonSigns.contains))
                if isNumber(rest.isEmpty ? next : rest) { return true }
            }
        }
        return comparativePhrases.contains { phrase in
            starts(of: phrase, in: words).contains { $0 + phrase.count < words.count && isNumber(words[$0 + phrase.count]) }
        }
    }

    /// "3B", "$500", "8gb", "0.5": a digit, after at most one currency sign.
    private static func isNumber(_ word: String) -> Bool {
        let digits = word.first.map { "$\u{20AC}\u{00A3}\u{00A5}".contains($0) } == true ? word.dropFirst() : Substring(word)
        return digits.first?.isNumber == true
    }

    // MARK: Dates

    private static let dateWords: Set<String> = [
        "today", "yesterday", "tomorrow", "tonight", "latest", "newest", "recent", "recently", "lately", "ago",
        "aujourd'hui", "hier", "demain", "recente", "recents", "recentes", "recemment",
        "dernier", "derniere", "derniers", "dernieres",
    ]
    /// "this weekend" is left out on purpose: "things I can build this weekend" is a topic, and it ranked well (EVIDENCE.md).
    private static let datePhrases = [
        ["cette", "semaine"], ["ce", "mois"], ["ce", "mois-ci"], ["cette", "annee"],
        ["semaine", "prochaine"], ["mois", "prochain"], ["annee", "prochaine"], ["an", "prochain"],
    ]
    private static let relatives: Set<String> = ["this", "last", "past", "next", "previous"]
    private static let periods: Set<String> = ["week", "month", "year", "quarter", "decade"]
    private static let spans: Set<String> = ["hours", "days", "weeks", "months", "years"]
    private static let quantifiers: Set<String> = ["few", "couple", "several", "of"]
    private static let yearPrepositions: Set<String> = ["since", "from", "before", "after", "until", "depuis", "avant", "apres", "jusqu'en"]

    private static func hasDate(_ words: [String]) -> Bool {
        if words.contains(where: dateWords.contains) || datePhrases.contains(where: { contains($0, in: words) }) { return true }
        for (index, word) in words.enumerated() {
            let following = words[(index + 1)...]
            // "this week", "last year"
            if relatives.contains(word), let next = following.first, periods.contains(next) { return true }
            // "last 7 days", "past few weeks", "next couple of months"
            if relatives.contains(word), word != "this",
               let span = following.first(where: { !isNumber($0) && !quantifiers.contains($0) }), spans.contains(span) { return true }
            // "since 2023", "avant 2019": a year beside a date preposition. A bare year is part of a name ("WWDC 2025").
            if yearPrepositions.contains(word), let next = following.first, isYear(next) { return true }
        }
        // "il y a 2 ans"
        return starts(of: ["il", "y", "a"], in: words).contains { $0 + 3 < words.count && isNumber(words[$0 + 3]) }
    }

    private static func isYear(_ word: String) -> Bool {
        word.count == 4 && word.allSatisfy(\.isNumber) && (word.hasPrefix("19") || word.hasPrefix("20"))
    }

    // MARK: Phrases

    private static func contains(_ phrase: [String], in words: [String]) -> Bool { !starts(of: phrase, in: words).isEmpty }

    /// Every index at which `phrase` begins.
    private static func starts(of phrase: [String], in words: [String]) -> [Int] {
        guard !phrase.isEmpty, words.count >= phrase.count else { return [] }
        return (0...(words.count - phrase.count)).filter { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }
}
