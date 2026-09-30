import AppKit
import BeamJev
import BeamModels
import BeamStore
import Foundation

// Pins: a saved sentence that stays current by itself. Every new or edited item is judged once for all of them,
// which is one request per item however many pins there are (EVIDENCE.md).
extension Engine {
    // MARK: What the sidebar asks of it

    public func pin(sentence: String) async -> PinOutcome {
        let asked = Sentence(sentence)
        guard !asked.isEmpty else {
            EngineLog.note("refused to pin an empty sentence")
            return .limitReached
        }
        let outcome: PinOutcome
        do {
            // The cleaned sentence is what is judged, so it is also what the pin row shows.
            outcome = try await context.database.addPin(sentence: asked.cleaned, at: environment.now())
        } catch {
            EngineLog.failure("pinning a sentence", error)
            return .limitReached
        }
        guard case .pinned = outcome else { return outcome }
        await reloadPins()
        // A new pin fills its list by itself: the newest items are judged for it now.
        await judgeForPins(itemIDs: nil)
        return outcome
    }

    public func removePin(id: Int64) async {
        do {
            guard try await context.database.removePin(id: id, at: environment.now()) != nil else { return }
        } catch {
            return EngineLog.failure("removing pin \(id)", error)
        }
        await reloadPins()
        lists.reload()
        undoStack.push("Undo Remove Pin") { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.context.database.restorePin(id: id)
            } catch {
                EngineLog.failure("undoing Remove Pin", error)
            }
        }
    }

    public func movePin(id: Int64, by offset: Int) async {
        do {
            try await context.database.movePin(id: id, by: offset)
        } catch {
            return EngineLog.failure("moving pin \(id)", error)
        }
        await reloadPins()
    }

    /// Leaving a pin marks it viewed: its badge then counts what is found after this moment.
    public func markPinViewed(id: Int64) async {
        do {
            try await context.database.markPinViewed(id: id, at: environment.now())
        } catch {
            return EngineLog.failure("marking pin \(id) viewed", error)
        }
        await reloadPins()
    }

    // MARK: Staying current

    func reloadPins() async {
        do {
            context.pins = try await context.database.pins()
        } catch {
            EngineLog.failure("reading the pins", error)
        }
        await reloadPinSummaries()
    }

    /// The badge of each pin: found items that arrived since it was last viewed.
    func reloadPinSummaries() async {
        guard !context.pins.isEmpty else {
            pinSummaries = []
            return publishSidebar()
        }
        var items: [Item] = []
        do {
            items = try await context.database.newestItems(in: .all, limit: Windows.newest)
        } catch {
            EngineLog.failure("reading items for the pin badges", error)
        }
        let sentences = pinSentences()
        let known = await context.cache.answers(textHashes: items.map(\.textHash), sentences: sentences,
                                                model: context.models.current)
        pinSummaries = context.pins.map { pin in
            let framed = FramedSentence.item(Sentence(pin.sentence))
            let since = pin.lastViewed ?? .distantPast
            let newFound = items.filter { item in
                guard item.sortDate > since, let probability = known[item.textHash]?[framed.hash] else { return false }
                return Bands.list(framed.cappedForList(probability)) == .found
            }
            return PinSummary(pin: pin, newFound: newFound.count, hasUnchecked: pinsHaveUnchecked)
        }
        publishSidebar()
    }

    /// One pass over the items that changed, carrying every pin at once.
    ///
    /// - Parameter itemIDs: what a refresh reported as new or edited, or nil for the newest items (a pin that
    ///   has just been created has nothing of its own to catch up on but everything already here).
    func judgeForPins(itemIDs: [Int64]?) async {
        // Refresh, adding a pin and reconnecting can arrive together. Finish one pass before starting another:
        // its cached answers keep concurrent asks from charging for the same item twice.
        while let pending = pinRefreshTask {
            await pending.value
            guard !Task.isCancelled else { return }
        }
        let epoch = pinRefreshEpoch
        let work = Task { [weak self] in
            guard let self, !Task.isCancelled, epoch == self.pinRefreshEpoch else { return }
            await self.runPinRefresh(itemIDs: itemIDs)
            if epoch == self.pinRefreshEpoch { self.pinRefreshTask = nil }
        }
        pinRefreshTask = work
        await work.value
    }

    /// Retry missing answers for the stored library, including items fetched before a key was connected.
    func refreshPins() async { await judgeForPins(itemIDs: nil) }

    /// A credential change stops the owned pass, even when it was started by a feed refresh.
    func cancelPinRefresh() {
        pinRefreshEpoch += 1
        pinRefreshTask?.cancel()
        pinRefreshTask = nil
    }

    private func runPinRefresh(itemIDs: [Int64]?) async {
        let sentences = pinSentences()
        guard !sentences.isEmpty, context.canSend else { return await reloadPinSummaries() }
        var items: [Item] = []
        do {
            if let itemIDs {
                guard !itemIDs.isEmpty else { return }
                items = try await context.database.items(ids: itemIDs)
            } else {
                items = try await context.database.newestItems(in: .all, limit: Windows.newest)
            }
        } catch {
            EngineLog.failure("reading items to judge for the pins", error)
            return
        }
        guard !Task.isCancelled, !items.isEmpty else { return }

        let known = await context.cache.answers(textHashes: items.map(\.textHash), sentences: sentences,
                                                model: context.models.current)
        guard !Task.isCancelled, context.canSend else { return }
        let targets = ListController.roundRobin(items).compactMap { item -> JudgeTarget<Int64>? in
            guard sentences.contains(where: { known[item.textHash]?[$0.hash] == nil }) else { return nil }
            return JudgeTarget(id: item.id, textHash: item.textHash, state: item.judgedText)
        }
        guard !targets.isEmpty else {
            if itemIDs == nil { pinsHaveUnchecked = false }
            return await reloadPinSummaries()
        }

        let failures = Tally()
        let outcome = await context.itemPass().run(targets: targets, sentences: sentences, known: known,
                                                   answered: { _, _ in }, failed: { _ in failures.add() })
        guard !Task.isCancelled, outcome != .cancelled else { return }
        // The pin rows warn only once a pass has actually left items unjudged, never while one is still running.
        pinsHaveUnchecked = failures.count > 0 || outcome != .completed
        if outcome == .keyRejected { context.keyStatus = .rejected }
        await reloadPinSummaries()
        lists.reload()
    }

    func pinSentences() -> [FramedSentence] {
        context.pins.compactMap { pin in
            let sentence = Sentence(pin.sentence)
            return sentence.isEmpty ? nil : FramedSentence.item(sentence)
        }
    }

    // MARK: When it happens

    /// Pins are brought up to date at launch, on waking, and every 30 minutes (PRODUCT.md section 5).
    func startPinTimer() {
        guard let interval = environment.pinRefresh else { return }
        pinTimer?.cancel()
        pinTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    /// A Mac that was asleep for a day has a day of feeds waiting.
    func watchForWaking() {
        guard environment.refreshesOnWake, wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
    }
}
