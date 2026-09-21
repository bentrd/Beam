import BeamJev
import BeamModels
import Foundation

/// One text to judge: what it is to the caller, what keys its cached answers, and what is actually sent.
struct JudgeTarget<ID: Hashable & Sendable>: Sendable {
    let id: ID
    /// `Item.textHash` or `Passage.textHash`.
    let textHash: String
    /// The state of one request: `{title, snippet}` for an item, `{article, section_heading, passage}` for a passage.
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

    /// Shared across the pass's requests: the failure streak that stops a run, and whatever ended it.
    private actor State {
        var streak = FailureStreak()
        var ending: JudgePassOutcome?
        /// True while every failure of the current streak was "can't reach TypeSafe".
        var allUnreachable = true

        var shouldStop: Bool { ending != nil }

        func end(_ outcome: JudgePassOutcome) { if ending == nil { ending = outcome } }

        func recordSuccess() {
            streak.recordSuccess()
            allUnreachable = true
        }

        /// - Returns: true when this failure was the tenth in a row and the pass must stop.
        func record(_ error: JevError) -> Bool {
            if case .unreachable = error {} else { allUnreachable = false }
            streak.record(error)
            guard streak.shouldStop else { return false }
            end(allUnreachable ? .offline : .stopped)
            return true
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
        let state = State()

        await withTaskGroup(of: Void.self) { group in
            for target in targets {
                let missing = sentences.filter { known[target.textHash]?[$0.hash] == nil }
                guard !missing.isEmpty else { continue }
                group.addTask {
                    // Checked here rather than before the group: ten failures may have landed while this one queued.
                    guard await state.shouldStop == false else { return }
                    await self.judgeOne(target, sentences: missing, state: state, answered: answered, failed: failed)
                }
            }
            await group.waitForAll()
        }
        await cache.flush()
        if Task.isCancelled { return .cancelled }
        return (await state.ending) ?? .completed
    }

    private func judgeOne(_ target: JudgeTarget<ID>, sentences: [FramedSentence], state: State,
                          answered: @escaping @MainActor @Sendable (ID, [String: Double]) -> Void,
                          failed: @escaping @MainActor @Sendable (ID) -> Void) async {
        do {
            let judgments = try await judge.judge(state: target.state, frames: sentences.map(\.frame), for: purpose)
            await state.recordSuccess()
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
        } catch is CancellationError {
            await state.end(.cancelled)
        } catch let error as JevError {
            switch error {
            case .missingKey: await state.end(.missingKey)
            case .unauthorized: await state.end(.keyRejected)
            case .dailyLimitReached: await state.end(.dailyLimit)
            default: _ = await state.record(error)
            }
            await failed(target.id)
        } catch {
            _ = await state.record(.unreachable(error.localizedDescription))
            await failed(target.id)
        }
    }
}
