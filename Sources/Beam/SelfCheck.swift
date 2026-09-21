import BeamModels
import BeamUI
import Foundation

/// The shell lane's check (`Beam -selfcheck YES`): there is no XCTest here, and a window cannot be asserted on.
/// It covers what can go wrong without pixels: the list streaming policy, and the fake backend keeping the promises
/// the views are built on (timing, ordering, exact copy, read state, pins, undo, saturation, viewport first).
@MainActor
enum SelfCheck {
    nonisolated static func runAndExit() -> Never {
        Task { @MainActor in
            var report = CheckReport("ui-shell")
            do {
                try await checkStreamingPolicy(&report)
                try await checkLists(&report)
                try await checkReader(&report)
                try await checkSidebar(&report)
                try await checkScenarios(&report)
            } catch {
                report.expect(false, "checks ran to the end", detail: "\(error)")
            }
            exit(report.finish())
        }
        Task {
            try? await Task.sleep(for: .seconds(90))
            FileHandle.standardError.write(Data("ui-shell: timed out waiting for a snapshot\n".utf8))
            exit(2)
        }
        dispatchMain()
    }

    // MARK: Streaming policy

    private static func checkStreamingPolicy(_ report: inout CheckReport) async throws {
        report.section("List streaming (DESIGN.md section 5)")
        func row(_ id: Int64) -> Row { Row(item: Item(id: id, sourceID: 1, guid: "\(id)", url: nil, title: "Item \(id)", snippet: ""), sourceTitle: "S") }
        func snapshot(_ ids: [Int64], running: Bool, sentence: String? = "q") -> ListSnapshot {
            ListSnapshot(request: ListRequest(sentence: sentence), rows: ids.map(row), isRunning: running)
        }

        var policy = ListStreaming()
        report.expectEqual(policy.receive(snapshot([1, 2, 3], running: false, sentence: nil)), .replace, "a plain list paints at once")

        policy.begin(ranked: true, holdsUntilSettled: false)
        report.expectEqual(policy.receive(snapshot([10, 11], running: true)), .none, "fewer than 8 rows before 350 ms: the old list holds")
        report.expectEqual(policy.rows.map(\.id), [1, 2, 3], "the old list is still what is drawn")
        report.expectEqual(policy.firstPaintDeadlinePassed(), .firstPaint, "at 350 ms whatever is listable paints")
        report.expectEqual(policy.rows.map(\.id), [10, 11], "first paint shows the new rows")

        report.expectEqual(policy.receive(snapshot([10, 11, 12], running: true)), .append([12]), "a row ranking below everything on screen appears at once")
        report.expectEqual(policy.receive(snapshot([9, 10, 11, 12, 13], running: true)), .append([13]), "a row ranking above is held; one below still appends")
        report.expectEqual(policy.rows.map(\.id), [10, 11, 12, 13], "rows on screen never reorder during a run")
        report.expectEqual(policy.receive(snapshot([9, 10, 11, 12, 13], running: false)), .merge([9]), "one merge when the run settles")
        report.expectEqual(policy.rows.map(\.id), [9, 10, 11, 12, 13], "the merge shows the final order")

        policy.begin(ranked: true, holdsUntilSettled: false)
        report.expectEqual(policy.receive(snapshot(Array(20..<28), running: true)), .firstPaint, "8 listable rows paint before the deadline")
        policy.begin(ranked: true, holdsUntilSettled: false)
        report.expectEqual(policy.receive(snapshot([30, 31], running: false)), .replace, "a cached sentence repaints at once")
        policy.begin(ranked: true, holdsUntilSettled: false)
        _ = policy.firstPaintDeadlinePassed()
        report.expectEqual(policy.receive(snapshot([], running: true)), .none, "nothing listable at 350 ms: keep waiting")
        report.expectEqual(policy.receive(snapshot([40], running: true)), .firstPaint, "then the first listable row paints")
        policy.begin(ranked: true, holdsUntilSettled: true)
        report.expectEqual(policy.receive(snapshot(Array(50..<60), running: true)), .none, "with VoiceOver on, nothing applies while running")
        report.expectEqual(policy.receive(snapshot(Array(50..<60), running: false)), .firstPaint, "and the whole list applies at settle")
    }

    // MARK: Lists

    private static func checkLists(_ report: inout CheckReport) async throws {
        report.section("Fake backend: lists")
        let backend = try FakeBackend()
        var plain = backend.list(ListRequest()).makeAsyncIterator()
        let all = await settled(&plain)
        report.expectEqual(all.last?.foot.text ?? "", "203 items", "All Items counts its rows")
        report.expect(all.last?.rows.first?.isMarked == true, "this week's pin hits come first, marked")
        let dates = (all.last?.rows ?? []).filter { !$0.isMarked }.map(\.item.sortDate)
        report.expect(dates == dates.sorted(by: >), "the rest follow by date")

        let started = Date()
        var search = backend.list(ListRequest(sentence: "A sentence nobody pinned about apple silicon")).makeAsyncIterator()
        let run = await settled(&search)
        let seconds = Date().timeIntervalSince(started)
        report.expect(run.first?.isRunning == true && run.first?.foot.text == "Checking 150 items", "a new sentence starts \"Checking 150 items\"",
                      detail: run.first?.foot.text ?? "")
        report.expect(run.count >= 6 && (1.0...2.6).contains(seconds), "rows stream in over about 1.5 s", detail: "\(run.count) snapshots in \(seconds) s")
        if let last = run.last {
            let ps = last.rows.compactMap { $0.check?.probability }
            report.expect(ps.allSatisfy { $0 >= Bands.listUnsure }, "only rows at p >= 0.45 are listed")
            report.expect(last.rows.allSatisfy { $0.isMarked == (($0.check?.probability ?? 0) >= Bands.listFound) }, "the mark is on rows at p >= 0.60 and never below")
            report.expect(ps.map { ($0 * 20).rounded() } == ps.map { ($0 * 20).rounded() }.sorted(by: >), "ordered by probability rounded to 0.05")
            report.expectEqual(last.foot.text, "Newest 150 of 203 checked.", "the settled foot says what was covered")
            report.expectEqual(last.foot.actionTitle ?? "", "Check 53 older", "and offers the older items")
        }
        backend.checkOlder()
        let widened = await settled(&search)
        report.expectEqual(widened.last?.foot.text ?? "", "203 items checked", "Check older extends the run to everything")

        var cached = backend.list(ListRequest(sentence: "running models locally on a laptop")).makeAsyncIterator()
        let repaint = await settled(&cached)
        report.expect(repaint.count == 1, "a sentence already checked repaints at once", detail: "\(repaint.count) snapshots")

        var nothing = backend.list(ListRequest(sentence: "zzzz qqqq")).makeAsyncIterator()
        let empty = await settled(&nothing)
        report.expectEqual(empty.last?.emptyMessage ?? "", "Nothing found in 150 items checked", "nothing found is said about what was checked")
        var noted = backend.list(ListRequest(sentence: "laptops under 1000 dollars")).makeAsyncIterator()
        report.expectEqual(await settled(&noted).last?.foot.text ?? "", "Exclusions, amounts and dates aren't judged.", "amounts are not judged, and the foot says so")
    }

    // MARK: Reader

    private static func checkReader(_ report: inout CheckReport) async throws {
        report.section("Fake backend: reader")
        let backend = try FakeBackend()
        var list = backend.list(ListRequest(sentence: "running models locally on a laptop")).makeAsyncIterator()
        guard let article = await settled(&list).last?.rows.first(where: { $0.item.title.hasPrefix("Things we learned") }) else {
            return report.expect(false, "the captured article is a found row of its own search")
        }
        report.expectEqual(backend.preview(itemID: article.id)?.foot.text ?? "", "Return to read", "a preview says \"Return to read\"")
        let unreadBefore = await currentSidebar(of: backend).unreadInAll
        report.expect(article.item.read == false, "previewing never marks an item read")

        let started = Date()
        var opened = backend.open(itemID: article.id, carrying: "running models locally on a laptop").makeAsyncIterator()
        backend.setViewport(firstVisible: 100, lastVisible: 112)
        let run = await settled(&opened) { $0.phase == .ready && !$0.isRunning }
        let seconds = Date().timeIntervalSince(started)
        report.expect(run.first?.phase == .loading, "the title and byline are there before the text")
        report.expect((1.5...3.2).contains(seconds), "judgments arrive over about 2 s", detail: "\(seconds) s")
        if let firstMarks = run.first(where: { $0.checks.values.contains { $0.isChecked } }) {
            let checked = firstMarks.checks.filter { $0.value.isChecked }.keys
            report.expect(checked.count >= Bands.saturationMinimumChecked, "no marks before 24 paragraphs are checked", detail: "\(checked.count)")
            report.expect(checked.contains(105) && !checked.contains(170), "what is on screen is judged first")
        }
        if let last = run.last {
            report.expectEqual(last.foot.text, "12 found, 7 unsure. Code not checked.", "the settled foot counts found and unsure")
            report.expectEqual(last.hits.count, 19, "hits are the found and unsure paragraphs")
            report.expect(last.hits == last.hits.sorted(), "in reading order")
            report.expect(last.checks.keys.allSatisfy { last.passages[$0].isJudgeable }, "headings and code carry no checks")
        }
        report.expectEqual(await currentSidebar(of: backend).unreadInAll, unreadBefore - 1, "opening marks the item read")

        backend.find("large language models")
        let asked = await settled(&opened) { $0.isFindActive && !$0.isRunning }
        report.expect(asked.last?.isSaturated == true && asked.last?.hits.isEmpty == true, "a broad sentence saturates: no hits to walk")
        report.expectEqual(asked.last?.foot.text ?? "", "Most of this article is about this", "the ask field gets the short sentence")
        backend.find(nil)
        let restored = await settled(&opened) { !$0.isFindActive && !$0.isRunning }
        report.expect(restored.count == 1 && restored.last?.hits.count == 19, "closing the ask field restores the carried marks at once")

        var broad = backend.open(itemID: article.id, carrying: "large language models").makeAsyncIterator()
        let saturated = await settled(&broad) { $0.phase == .ready && !$0.isRunning }
        report.expectEqual(saturated.last?.foot.text ?? "", "Most of this article is about this.", "the saturation sentence is calm")
        report.expectEqual(saturated.last?.foot.actionTitle ?? "", "Find something narrower.", "its tail is the text button")
        report.expectEqual(saturated.last?.foot.help ?? "", "149 of 158 paragraphs", "the count lives in the help tag")
    }

    // MARK: Sidebar

    private static func checkSidebar(_ report: inout CheckReport) async throws {
        report.section("Fake backend: sidebar, pins, undo")
        let backend = try FakeBackend()
        let first = await currentSidebar(of: backend)
        report.expectEqual(first.pins.count, 3, "three pins to start with")
        report.expect(first.pins[0].newFound > 0, "the first pin has found items new since it was viewed")
        report.expectEqual(first.sources.filter(\.showsWarning).map(\.source.title), ["r/macapps"], "only a source failing for over 24 hours warns")

        await backend.markPinViewed(id: first.pins[0].id)
        report.expectEqual(await currentSidebar(of: backend).pins.first?.newFound ?? -1, 0, "leaving a pin clears its badge")

        for number in 1...6 { _ = await backend.pin(sentence: "sentence number \(number)") }
        guard case .limitReached = await backend.pin(sentence: "one too many") else { return report.expect(false, "a tenth pin is refused") }
        report.expect(true, "a tenth pin is refused")

        await backend.removePin(id: first.pins[1].id)
        report.expectEqual(backend.undoTitle ?? "", "Undo Remove Pin", "removal is undoable, with its menu title")
        _ = await backend.undo()
        let afterUndo = await currentSidebar(of: backend)
        report.expectEqual(Array(afterUndo.pins.map(\.pin.sentence).prefix(3)), first.pins.map(\.pin.sentence), "Undo puts the pin back where it was")

        let hackerNews = first.sources[0]
        await backend.markAllRead(in: .source(hackerNews.id))
        await backend.removeSource(id: hackerNews.id)
        _ = await backend.undo()
        _ = await backend.undo()
        let restored = await currentSidebar(of: backend).sources.first { $0.id == hackerNews.id }
        report.expectEqual(restored?.unread ?? -1, hackerNews.unread, "Undo restores the source with its items, then their unread state")
        report.expect(backend.undoTitle == nil, "and the undo stack is empty again")
    }

    // MARK: Scenarios

    private static func checkScenarios(_ report: inout CheckReport) async throws {
        report.section("Fake backend: every foot sentence")
        // Each staged run takes its 1.5 s; they wait together.
        async let noKeyRun = settledFoot(FakeOptions(keyStatus: .missing))
        async let rejectedRun = settledFoot(FakeOptions(keyStatus: .rejected))
        async let failuresRun = settledFoot(FakeOptions(scenario: .failures))
        async let stoppedRun = settledFoot(FakeOptions(scenario: .stopped))
        async let offlineRun = settledFoot(FakeOptions(scenario: .offline))
        async let limitRun = settledFoot(FakeOptions(scenario: .limit))
        async let failingSourceRun = settledFoot(FakeOptions(), scope: .source(4), sentence: nil)
        let (noKey, rejected, failures, stopped) = try await (noKeyRun, rejectedRun, failuresRun, stoppedRun)
        let (offline, limit, failingSource) = try await (offlineRun, limitRun, failingSourceRun)

        report.expectEqual(noKey.text, "Add a key to search.", "no key")
        report.expectEqual(rejected.text, "TypeSafe rejected this key.", "key rejected")
        report.expectEqual(rejected.actionTitle ?? "", "Open Settings", "with the way to Settings")
        report.expect(failures.text.hasSuffix(" not checked.") && failures.action == .retry, "failures are counted as not checked, with Retry",
                      detail: failures.text)
        report.expectEqual(stopped.text, "Stopped after repeated errors.", "ten failures in a row stop the run")
        report.expectEqual(offline.text, "Offline. Showing what was already checked.", "offline")
        report.expectEqual(limit.text, "Daily limit reached. Resets at midnight.", "daily limit")
        report.expectEqual(failingSource.text, "Couldn't refresh: HTTP 429.", "a selected failing source names its reason")

        // One order, and it is the list foot's: a pin is a ranked list, so what blocks it is said there too.
        report.expectEqual(try await pinFoot(FakeOptions(keyStatus: .rejected)).text, "TypeSafe rejected this key.",
                           "a pin's foot says the key was rejected, as a search's does")
        report.expectEqual(try await pinFoot(FakeOptions(keyStatus: .missing)).text, "Add a key to search.",
                           "a pin's foot asks for a key")
        report.expectEqual(try await pinFoot(FakeOptions(scenario: .offline)).text, "Offline. Showing what was already checked.",
                           "a pin's foot says Beam is offline")
    }

    /// The same foot under a pin scope, which brings its own sentence.
    private static func pinFoot(_ options: FakeOptions) async throws -> Foot {
        let backend = try FakeBackend(options: options)
        defer { withExtendedLifetime(backend) {} }
        guard let pin = await currentSidebar(of: backend).pins.first else { return .blank }
        var list = backend.list(ListRequest(scope: .pin(pin.id))).makeAsyncIterator()
        return await settled(&list).last?.foot ?? .blank
    }

    private static func settledFoot(_ options: FakeOptions, scope: ListScope = .all,
                                    sentence: String? = "something nobody has searched for yet") async throws -> Foot {
        let backend = try FakeBackend(options: options)
        defer { withExtendedLifetime(backend) {} }               // the stream does not keep its backend alive
        var list = backend.list(ListRequest(scope: scope, sentence: sentence)).makeAsyncIterator()
        return await settled(&list).last?.foot ?? .blank
    }

    // MARK: Stream helpers

    /// Collects snapshots until the run settles. The watchdog in `runAndExit` bounds the wait.
    private static func settled(_ iterator: inout AsyncStream<ListSnapshot>.Iterator) async -> [ListSnapshot] {
        var seen: [ListSnapshot] = []
        while let snapshot = await iterator.next() {
            seen.append(snapshot)
            if !snapshot.isRunning { break }
        }
        return seen
    }

    private static func settled(_ iterator: inout AsyncStream<ReaderSnapshot>.Iterator, when isDone: (ReaderSnapshot) -> Bool) async -> [ReaderSnapshot] {
        var seen: [ReaderSnapshot] = []
        while let snapshot = await iterator.next() {
            seen.append(snapshot)
            if isDone(snapshot) { break }
        }
        return seen
    }

    /// A fresh sidebar stream opens with the current state.
    private static func currentSidebar(of backend: FakeBackend) async -> SidebarSnapshot {
        var snapshots = backend.sidebar().makeAsyncIterator()
        return await snapshots.next() ?? SidebarSnapshot()
    }
}
