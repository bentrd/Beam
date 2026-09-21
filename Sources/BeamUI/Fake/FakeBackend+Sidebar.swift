import BeamModels
import Foundation

// Sources and pins: everything the sidebar shows and changes.
extension FakeBackend {
    public func sidebar() -> AsyncStream<SidebarSnapshot> {
        sidebarContinuation?.finish()
        let (stream, continuation) = AsyncStream<SidebarSnapshot>.makeStream()
        sidebarContinuation = continuation
        publishSidebar()
        return stream
    }

    func publishSidebar() { sidebarContinuation?.yield(sidebarSnapshot()) }

    func sidebarSnapshot() -> SidebarSnapshot {
        let dayAgo = Date().addingTimeInterval(-86_400)
        return SidebarSnapshot(
            unreadInAll: items.filter { !$0.read }.count,
            pins: pins.map { pin in
                let checks = itemChecks[FakeJudge.normalise(pin.sentence)] ?? [:]
                let viewed = pin.lastViewed ?? .distantPast
                let fresh = items.filter { $0.sortDate > viewed && (checks[$0.id] ?? 0) >= Bands.listFound }
                return PinSummary(pin: pin, newFound: fresh.count)
            },
            sources: sources.sorted { $0.position < $1.position }.map { source in
                SourceSummary(source: source, unread: items.filter { $0.sourceID == source.id && !$0.read }.count,
                              showsWarning: source.failingSince.map { $0 < dayAgo } ?? false)
            })
    }

    // MARK: Sources

    public func catalog() -> [CatalogEntry] { FakeSources.catalog }

    public func resolve(_ input: String) async -> ResolveOutcome {
        try? await Task.sleep(for: .milliseconds(700))               // long enough to read "Looking for a feed"
        let wanted = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let known = FakeSources.catalog.map(\.candidate).first { candidate in
            [candidate.feedURL.absoluteString, candidate.siteURL?.absoluteString, candidate.siteURL?.host, candidate.title]
                .compactMap { $0?.lowercased() }.contains { $0 == wanted || $0.contains(wanted) || wanted.contains($0) }
        }
        // Nothing is fetched here: an address outside the catalog is taken at its word when it names a host.
        guard let candidate = known ?? guessedCandidate(from: wanted) else { return .notFound }
        if let existing = sources.first(where: { $0.feedURL == candidate.feedURL }) { return .alreadyAdded(existing) }
        return .found([candidate])
    }

    private func guessedCandidate(from input: String) -> SourceCandidate? {
        let address = input.contains("://") ? input : "https://" + input
        guard input.contains("."), !input.contains(" "), let url = URL(string: address), let host = url.host else { return nil }
        return SourceCandidate(kind: .feed, title: host.replacingOccurrences(of: "www.", with: ""),
                               feedURL: url.appendingPathComponent("feed"), siteURL: url)
    }

    public func addSource(_ candidate: SourceCandidate) async -> AddOutcome {
        guard !sources.contains(where: { $0.feedURL == candidate.feedURL }) else { return .alreadyAdded }
        let source = Source(id: newID(), kind: candidate.kind, title: candidate.title, feedURL: candidate.feedURL, siteURL: candidate.siteURL,
                            position: (sources.map(\.position).max() ?? -1) + 1, lastFetch: Date())
        sources.append(source)
        publishEverything()
        return .added(source)
    }

    public func removeSource(id: Int64) async {
        guard let source = sources.first(where: { $0.id == id }) else { return }
        let removed = items.filter { $0.sourceID == id }
        sources.removeAll { $0.id == id }
        items.removeAll { $0.sourceID == id }
        undoStack.append(UndoEntry(title: "Undo Remove Source") { [weak self] in
            guard let self else { return }
            self.sources.append(source)
            self.items = (self.items + removed).sorted { $0.sortDate > $1.sortDate }
        })
        publishEverything()
    }

    public func retrySource(id: Int64) async {
        try? await Task.sleep(for: .milliseconds(400))
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].lastError = nil
        sources[index].failingSince = nil
        sources[index].lastFetch = Date()
        publishEverything()
    }

    // MARK: Pins

    public func pin(sentence: String) async -> PinOutcome {
        let key = FakeJudge.normalise(sentence)
        if let existing = pins.first(where: { FakeJudge.normalise($0.sentence) == key }) { return .alreadyPinned(existing) }
        guard pins.count < Pin.maximum else { return .limitReached }
        let cleaned = sentence.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let pin = Pin(id: newID(), sentence: cleaned, position: (pins.map(\.position).max() ?? -1) + 1, lastViewed: Date())
        pins.append(pin)
        judgeEverything(about: cleaned)
        publishEverything()
        return .pinned(pin)
    }

    public func removePin(id: Int64) async {
        guard let pin = pins.first(where: { $0.id == id }) else { return }
        pins.removeAll { $0.id == id }
        undoStack.append(UndoEntry(title: "Undo Remove Pin") { [weak self] in
            guard let self else { return }
            self.pins.insert(pin, at: min(pin.position, self.pins.count))
            self.renumberPins()
        })
        renumberPins()
        publishEverything()
    }

    public func movePin(id: Int64, by offset: Int) async {
        guard let from = pins.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(from + offset, 0), pins.count - 1)
        guard to != from else { return }
        pins.insert(pins.remove(at: from), at: to)
        renumberPins()
        publishSidebar()
    }

    public func markPinViewed(id: Int64) async {
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[index].lastViewed = Date()
        publishSidebar()
    }

    /// `pins` is kept in sidebar order; positions decide ⌘1 to ⌘9, so they stay dense.
    private func renumberPins() {
        for index in pins.indices { pins[index].position = index }
    }
}
