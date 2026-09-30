import BeamFeeds
import BeamModels
import BeamStore
import Foundation

// Sources: the catalog, resolving what was typed or dropped, adding, removing with Undo, and fetching.
extension Engine {
    // MARK: The sidebar

    public func sidebar() -> AsyncStream<SidebarSnapshot> {
        sidebarContinuation?.finish()
        let (stream, continuation) = AsyncStream<SidebarSnapshot>.makeStream()
        sidebarContinuation = continuation
        publishSidebar()
        return stream
    }

    func publishSidebar() {
        let aDayAgo = environment.now().addingTimeInterval(-86_400)
        let snapshot = SidebarSnapshot(
            unreadInAll: unread.total,
            pins: pinSummaries,
            sources: context.sources.map { source in
                // Transient failures show nothing: only a source that has been failing for a day earns the glyph.
                SourceSummary(source: source, unread: unread.bySource[source.id] ?? 0,
                              showsWarning: source.failingSince.map { $0 < aDayAgo } ?? false)
            })
        sidebarContinuation?.yield(snapshot)
    }

    func reloadSidebar() async {
        await reloadSources()
        await reloadPins()
        await reloadUnread()
    }

    func reloadSources() async {
        do {
            context.sources = try await context.database.sources()
        } catch {
            EngineLog.failure("reading the sources", error)
        }
        publishSidebar()
    }

    func reloadUnread() async {
        do {
            unread = try await context.database.unreadCounts()
        } catch {
            EngineLog.failure("counting unread items", error)
        }
        publishSidebar()
    }

    // MARK: First launch

    /// A fresh install starts with three removable sources, so the first minute has something in it.
    /// It happens once: emptying the sidebar on purpose must not fill it again on the next launch.
    func seedStarterSources() async {
        do {
            guard try await context.database.meta(Self.seededKey) == nil else { return }
            for entry in environment.starters {
                _ = try await context.database.addSource(entry.candidate)
            }
            try await context.database.setMeta(Self.seededKey, to: "1")
        } catch {
            EngineLog.failure("adding the starter sources", error)
        }
    }

    // MARK: Adding

    public func catalog() -> [CatalogEntry] { environment.catalog }

    public func resolve(_ input: String) async -> ResolveOutcome {
        let candidates = await resolver.resolve(input)
        guard !candidates.isEmpty else { return .notFound }
        for candidate in candidates {
            if let existing = try? await context.database.source(feedURL: candidate.feedURL) {
                return .alreadyAdded(existing)
            }
        }
        return .found(candidates)
    }

    public func addSource(_ candidate: SourceCandidate) async -> AddOutcome {
        let outcome: AddOutcome
        do {
            outcome = try await context.database.addSource(candidate)
        } catch {
            EngineLog.failure("adding a source", error)
            return .failed(error.localizedDescription)
        }
        guard case let .added(source) = outcome else { return outcome }
        await reloadSources()
        // Its items are what the user asked for: fetch them now rather than at the next refresh.
        await fetch([source])
        return outcome
    }

    /// Removal has no alert. Undo restores the source with its items until Beam quits.
    public func removeSource(id: Int64) async {
        do {
            guard try await context.database.removeSource(id: id, at: environment.now()) != nil else { return }
        } catch {
            return EngineLog.failure("removing source \(id)", error)
        }
        await reloadSidebar()
        lists.reload()
        undoStack.push("Undo Remove Source") { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.context.database.restoreSource(id: id)
            } catch {
                EngineLog.failure("undoing Remove Source", error)
            }
        }
    }

    public func retrySource(id: Int64) async {
        guard let source = context.source(id) else { return }
        await fetch([source])
    }

    // MARK: Fetching

    /// ⌘R: fetch everything, then retry whatever was left not checked.
    public func refresh() async {
        await fetch(context.sources)
        // A 304 or unchanged feed can still have missing pin answers after an offline run or a keyless launch.
        // Cache hits make this free when the library is already checked.
        await refreshPins()
        lists.retry()
        reader.retry()
    }

    /// One fetch of the given sources. Errors are recorded against their source and never thrown: one bad feed
    /// must not stop the others, and the sidebar and the foot are where a failure shows.
    func fetch(_ sources: [Source]) async {
        guard !sources.isEmpty else { return }
        context.feedRefreshesInFlight += 1
        lists.reload()
        publishSidebar()
        var changed: [Int64] = []

        for await result in refresher.refresh(sources) {
            var arrived = false
            do {
                switch result.outcome {
                case let .items(items):
                    let upsert = try await context.database.upsertItems(items, sourceID: result.source.id,
                                                                        repoName: result.repoName, now: environment.now())
                    try await context.database.recordFetchSuccess(sourceID: result.source.id, at: environment.now())
                    changed += upsert.newIDs + upsert.editedIDs
                    arrived = !upsert.newIDs.isEmpty || !upsert.editedIDs.isEmpty
                case .notModified:
                    try await context.database.recordFetchSuccess(sourceID: result.source.id, at: environment.now())
                case let .failed(error):
                    try await context.database.recordFetchFailure(sourceID: result.source.id, error: error.reason,
                                                                  at: environment.now())
                }
            } catch {
                EngineLog.failure("storing what \(result.source.title) sent", error)
            }
            await reloadSources()
            if arrived { lists.reload() }
        }

        context.feedRefreshesInFlight -= 1
        await reloadUnread()
        lists.reload()
        await judgeForPins(itemIDs: changed)
    }
}
