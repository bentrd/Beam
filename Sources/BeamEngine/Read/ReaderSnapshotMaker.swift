import BeamModels
import Foundation

/// Turns an open article into the one immutable thing the reader draws: which paragraphs are found, unsure,
/// nothing or not checked, whether the sentence describes the whole article, and the one status sentence.
@MainActor
enum ReaderSnapshotMaker {
    static func snapshot(_ run: ReaderRun, context: EngineContext) -> (snapshot: ReaderSnapshot, isSaturated: Bool) {
        var snapshot = ReaderSnapshot(item: run.item, sourceTitle: run.sourceTitle, phase: run.phase,
                                      passages: run.passages, omittedImages: run.images, omittedTables: run.tables,
                                      sentence: run.sentence?.raw, isFindActive: run.isFindActive, isRunning: run.isRunning)
        switch run.phase {
        case .preview:
            snapshot.foot = Feet.returnToRead
            return (snapshot, run.isSaturated)
        case .external:
            snapshot.foot = Feet.returnToOpenInBrowser
            return (snapshot, run.isSaturated)
        case .loading:
            // A load that answers within a second says nothing at all.
            if run.isSlowToLoad { snapshot.foot = Feet.gettingArticle }
            return (snapshot, run.isSaturated)
        case .unavailable:
            // "Beam couldn't get the article text. Open Original." ends in the reader's own action, not a foot one,
            // so the view writes that line.
            return (snapshot, run.isSaturated)
        case .ready:
            break
        }

        let framed = run.sentence.map(FramedSentence.passage)
        let answers = run.answers(for: framed)
        let judgeable = run.judgeable
        // Saturation cannot be told from fewer than 24 answers (or all of them, in a short article).
        let canTellSaturation = answers.count >= min(Bands.saturationMinimumChecked, judgeable.count)
        // While the run is going that is also the bar for drawing anything, because marks that appear and then
        // vanish are worse than marks that arrive late. A settled run has nothing more coming: what was checked
        // is final and is shown, however little of it there is. Holding it back would make an article whose
        // requests mostly failed report every paragraph "not checked" while its own foot counts the ones that
        // were — and MUST 6 is that exactly the refused paragraphs read "not checked".
        let isRevealed = !run.isRunning || canTellSaturation

        if let framed {
            for index in judgeable {
                if isRevealed, let probability = answers[index] {
                    snapshot.checks[index] = .judged(framed.cappedForPassage(probability))
                } else {
                    snapshot.checks[index] = run.failed.contains(index) && !run.isRunning ? .failed : .pending
                }
            }
        }

        let bands = answers.values.map { Bands.passage(framed?.cappedForPassage($0) ?? $0) }
        let found = bands.filter { $0 == .found }.count
        let unsure = bands.filter { $0 == .unsure }.count
        // Saturation is what a carried sentence does to an article that is entirely about it, and the one way out
        // of it is this field: "Find something narrower." invites a question, so a question must always be allowed
        // to show its answer. Were it swallowed the same way, the only action a saturated article offers would
        // lead to another blank article (PRODUCT.md addendum).
        let isOverTheLine = !run.isFindActive && canTellSaturation && !answers.isEmpty
            && Double(found) / Double(answers.count) > Bands.saturationShare
        // Sticky while the run lasts, decided for good when it settles.
        let isSaturated = run.isRunning ? (run.isSaturated || isOverTheLine) : isOverTheLine

        snapshot.isSaturated = isSaturated
        if isRevealed, !isSaturated {
            snapshot.hits = judgeable.filter { snapshot.band(at: $0) != .nothing }
        }
        snapshot.foot = foot(run, context: context, judgeable: judgeable.count, checked: answers.count,
                             found: found, unsure: unsure, isSaturated: isSaturated)
        return (snapshot, isSaturated)
    }

    /// The reader's status line, in the same spirit as the list's: never "nothing" about what was not checked.
    static func foot(_ run: ReaderRun, context: EngineContext, judgeable: Int, checked: Int,
                     found: Int, unsure: Int, isSaturated: Bool) -> Foot {
        guard run.sentence != nil, judgeable > 0 else {
            return run.hasCode && judgeable == 0 ? Foot(Feet.codeNotChecked) : .blank
        }
        if run.isRunning {
            if run.isFindActive { return Feet.askChecking }
            return run.failed.isEmpty ? Feet.checkingParagraphs(judgeable) : Feet.paragraphProgress(checked, of: judgeable, retry: false)
        }
        switch context.keyStatus {
        case .missing: return Feet.addKey
        case .rejected: return Feet.keyRejected
        case .storageError: return Feet.keyStorageError
        case .valid, .unreachable: break
        }
        switch run.outcome {
        case .dailyLimit: return Feet.dailyLimit
        case .offline: return Feet.offline
        case .stopped: return Feet.stopped
        default: break
        }
        if checked < judgeable { return Feet.paragraphProgress(checked, of: judgeable, retry: true) }
        if isSaturated { return Feet.saturated(found: found, of: checked) }
        if found + unsure == 0, run.isFindActive { return Feet.askNothingFound(in: checked) }

        let sentence = found + unsure == 0
            ? Feet.nothingFound(inParagraphs: checked, matchedByTitle: run.matchedByTitle)
            : Feet.found(found, unsure: unsure)
        return Foot(run.hasCode ? sentence + ". " + Feet.codeNotChecked : sentence)
    }
}
