import BeamJev
import BeamModels
import Foundation

/// One text to judge: what it is to the caller, what keys its cached answers, and what is actually sent.
struct JudgeTarget<ID: Hashable & Sendable>: Sendable {
    let id: ID
    /// `Item.textHash` or `Passage.textHash`.
    let textHash: String
    /// The state of one request: `Item.judgedText` for an item, `Passage.judgedText` for a passage. Whatever is
    /// sent here is what `textHash` above must cover, or a judgment is answered for from a key that never knew
    /// about part of the text it was made on.
    let state: [String: String]
}

/// How a pass ended. Each case is one foot sentence (DESIGN.md section 6), so the caller never parses a message.
enum JudgePassOutcome: Sendable, Equatable {
    case completed
    case cancelled
    case missingKey
    case keyRejected
    case dailyLimit
    /// Ten consecutive failures, all of them "can't reach TypeSafe".
    case offline
    /// Ten consecutive failures of other kinds.
    case stopped
}

/// The one way Beam judges anything: cache first, then one request per text carrying every sentence that text
/// still lacks an answer for.
///
/// One request per text is measured, not incidental (EVIDENCE.md): packing several items into a request costs
/// quality, and all active sentences riding together is why keeping nine pins current costs the same one pass
/// over new items as keeping none.
///
/// Targets are judged in the order given, which is how the list spreads its requests round-robin across sources.
/// The judge's own limiter (64) paces them, so every queued request cancels cleanly when the run is replaced.
struct JudgePass<ID: Hashable & Sendable>: Sendable {
    let judge: Judge
    let cache: JudgmentCache
    let models: ModelRegistry
    let purpose: SpendMeter.Purpose
    let now: @Sendable () -> Date

    /// What one request came back with.
    private enum Answer: Sendable {
        case answered
        case refused(JevError)
    }

    /// Shared across the pass's requests: the failure streak that stops a run, and whatever ended it.
    ///
    /// "Ten consecutive failures" counts ten texts in a row **in the order the run asked about them**, not ten
    /// answers that happened to arrive together. Sixty-four requests are in flight at once and a failing one is
    /// retried five times, so failures always land in a clump after the successes they were sent beside: counting
    /// arrivals would stop a run that is merely three-in-ten unlucky, and PRODUCT.md MUST 6 asks for an honest
    /// count of what was not checked, not a run that gives up on a service that is answering.
    private actor State {
        var ending: JudgePassOutcome?
        var shouldStop: Bool { ending != nil }

        private var streak = FailureStreak()
        /// True while every failure of the current streak was "can't reach TypeSafe".
        private var allUnreachable = true
        /// Answers that have arrived out of order and are waiting for the ones before them.
        private var waiting: [Int: Answer] = [:]
        /// How far the reading in order has got.
        private var read = 0

        /// - Returns: true when this is what ended the pass, and so what must take its queue down with it.
        @discardableResult
        func end(_ outcome: JudgePassOutcome) -> Bool {
            guard ending == nil else { return false }
            ending = outcome
            return true
        }

        /// Reads every answer that is now in order, however out of order they arrived.
        /// - Parameter position: the target's place in the order the pass was given.
        /// - Returns: true when what it read ended the pass.
        func record(_ answer: Answer, at position: Int) -> Bool {
            waiting[position] = answer
            while let answer = waiting.removeValue(forKey: read) {
                read += 1
                switch answer {
                case .answered:
                    streak.recordSuccess()
                    allUnreachable = true
                case let .refused(error):
                    if case .unreachable = error {} else { allUnreachable = false }
                    streak.record(error)
                    if streak.shouldStop { return end(allUnreachable ? .offline : .stopped) }
                }
            }
            return false
        }
    }

    /// Judges every target that is missing an answer for at least one sentence.
    ///
    /// - Parameter known: answers already in hand, `[text hash: [sentence hash: probability]]`. Whatever is in
    ///   here is never sent again.
    /// - Parameter answered: called on the main actor with the raw probabilities of one text, by sentence hash.
    /// - Parameter failed: called on the main actor for a text that could not be judged at all. A sentence absent
    ///   from an `answered` dictionary was not judged either: both are "not checked", never "nothing".
    func run(targets: [JudgeTarget<ID>], sentences: [FramedSentence], known: [String: [String: Double]],
             answered: @escaping @MainActor @Sendable (ID, [String: Double]) -> Void,
             failed: @escaping @MainActor @Sendable (ID) -> Void) async -> JudgePassOutcome {
        guard !targets.isEmpty, !sentences.isEmpty else { return .completed }
        // Only what is actually asked about takes a place in the order: a target the cache already answers must
        // not leave a hole in it, since a hole would hold up the reading that decides when to stop.
        let asked = targets.compactMap { target -> (target: JudgeTarget<ID>, sentences: [FramedSentence])? in
            let missing = sentences.filter { known[target.textHash]?[$0.hash] == nil }
            return missing.isEmpty ? nil : (target, missing)
        }
        guard !asked.isEmpty else { return .completed }
        let state = State()

        await withTaskGroup(of: Bool.self) { group in
            for (position, ask) in asked.enumerated() {
                group.addTask {
                    // Checked here rather than before the group: ten failures may have landed while this one queued.
                    guard await state.shouldStop == false else { return true }
                    return await self.judgeOne(ask.target, sentences: ask.sentences, at: position, state: state,
                                               answered: answered, failed: failed)
                }
            }
            // A run that has stopped takes its queue with it. The rest cannot succeed where ten in a row failed,
            // and every one of them would otherwise still be sent, retried five times, and waited for.
            for await mustStop in group where mustStop {
                group.cancelAll()
                break
            }
        }
        await cache.flush()
        if Task.isCancelled { return .cancelled }
        return (await state.ending) ?? .completed
    }

    /// - Returns: true when this request is the one that ended the pass.
    private func judgeOne(_ target: JudgeTarget<ID>, sentences: [FramedSentence], at position: Int, state: State,
                          answered: @escaping @MainActor @Sendable (ID, [String: Double]) -> Void,
                          failed: @escaping @MainActor @Sendable (ID) -> Void) async -> Bool {
        do {
            let judgments = try await judge.judge(state: target.state, frames: sentences.map(\.frame), for: purpose)
            let hasEnded = await state.record(.answered, at: position)
            await MainActor.run { models.saw(judgments.model) }

            let at = now()
            var probabilities: [String: Double] = [:]
            for (index, sentence) in sentences.enumerated() {
                // A missing or invalid answer leaves that sentence unchecked for this text; the others still count.
                guard index < judgments.probabilities.count, let probability = judgments.probabilities[index] else { continue }
                probabilities[sentence.hash] = probability
                await cache.remember(textHash: target.textHash, sentenceHash: sentence.hash, model: judgments.model,
                                     probability: probability, at: at)
            }
            // A request that answered nothing usable is a failure; one that answered some sentences and not
            // others hands back what it has, and the caller reads a missing sentence as "not checked".
            if probabilities.isEmpty { await failed(target.id) } else { await answered(target.id, probabilities) }
            return hasEnded
        } catch is CancellationError {
            return await state.end(.cancelled)
        } catch let error as JevError {
            let hasEnded: Bool
            switch error {
            case .missingKey: hasEnded = await state.end(.missingKey)
            case .unauthorized: hasEnded = await state.end(.keyRejected)
            case .dailyLimitReached: hasEnded = await state.end(.dailyLimit)
            default: hasEnded = await state.record(.refused(error), at: position)
            }
            await failed(target.id)
            return hasEnded
        } catch {
            let hasEnded = await state.record(.refused(.unreachable(error.localizedDescription)), at: position)
            await failed(target.id)
            return hasEnded
        }
    }
}
