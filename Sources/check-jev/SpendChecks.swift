import BeamJev
import BeamModels
import Foundation

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
    return calendar
}()

private func parisTime(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    paris.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)) ?? Date()
}

func checkBreaker(_ report: inout CheckReport) async {
    report.section("Spend meter and breaker")
    let price = SpendMeter(calendar: paris)
    await price.add(tokens: 1_000_000)
    let million = await price.dollarsToday
    report.expect(abs(million - 0.042) < 1e-12, "a million input tokens cost $0.042")
    report.expect(SpendMeter.dailyCeiling == 0.50 && SpendMeter.readerReserve == 0.05, "ships at $0.50 a day with $0.05 held for the reader")

    // A one-cent day with a fifth of a cent held for the reader; every answer bills 50,000 tokens ($0.0021).
    let service = FakeService(fallback: .http(200, body: FakeService.answers(["0.5"], tokens: 50_000)))
    let meter = SpendMeter(ceiling: 0.01, readerReserve: 0.002, calendar: paris)
    let judge = Judge(keyProvider: { "k" }, spend: meter, client: JevClient(transport: service.transport))

    var ranked = 0
    var rankingStop: Result<Judgments, JevError>?
    for _ in 0..<10 {
        let result = await outcome { try await judge.judge(state: ["title": "t"], frames: ["f"]) }
        if case .success = result { ranked += 1 } else { rankingStop = result; break }
    }
    report.expect(ranked == 4 && rankingStop == .failure(.dailyLimitReached), "ranking stops with dailyLimitReached once $0.008 of the $0.01 is spent",
                  detail: "\(ranked) answered, then \(String(describing: rankingStop))")
    report.expectEqual(service.requests.count, 4, "the refused request was never sent")
    let rankingClosed = await meter.isExhausted(for: .ranking)
    let readingClosed = await meter.isExhausted(for: .reading)
    report.expect(rankingClosed && !readingClosed, "the reserve is still there for the reader")

    let reading = await outcome { try await judge.judge(state: ["passage": "p"], frames: ["f"], for: .reading) }
    let readingStop = await outcome { try await judge.judge(state: ["passage": "p"], frames: ["f"], for: .reading) }
    report.expect((try? reading.get()) != nil && readingStop == .failure(.dailyLimitReached), "the reader spends the reserve, then stops at the ceiling")
    report.expectEqual(service.requests.count, 5, "five requests were sent in all")
    let spent = await meter.dollarsToday
    let status = await judge.validateKey()
    report.expect(abs(spent - 0.0105) < 1e-9, "spend is the sum of what was billed")
    report.expect(status == .valid, "a key can still be checked on a day the limit was reached")
}

func checkMidnight(_ report: inout CheckReport) async {
    report.section("Midnight and persistence")
    let clock = TestClock(parisTime(21, 23, 58))
    let store = MemorySpendStore()
    let meter = SpendMeter(ceiling: 0.01, readerReserve: 0.002, persistence: store, calendar: paris, now: { clock.now })

    await meter.add(tokens: 250_000)
    await meter.flush()
    let lateExhausted = await meter.isExhausted(for: .reading)
    report.expect(lateExhausted, "exhausted at 23:58")
    report.expectEqual(await store.rows, ["2026-09-21": 250_000], "the day's tokens are stored under the local date")

    // 23:58 and 00:01 Paris time fall on the same UTC day: only a local calendar resets here.
    clock.set(parisTime(22, 0, 1))
    let afterMidnight = await meter.dollarsToday
    let stillClosed = await meter.isExhausted(for: .ranking)
    report.expect(afterMidnight == 0 && !stillClosed, "resets at local midnight")
    await meter.add(tokens: 1_000)
    await meter.flush()
    report.expectEqual(await store.rows, ["2026-09-21": 250_000, "2026-09-22": 1_000], "the new day gets its own row; yesterday's stays")

    clock.set(parisTime(21, 12, 0))
    let setBack = await meter.dollarsToday
    report.expect(abs(setBack - 0.000042) < 1e-12, "a clock set back does not hand the day's spend back")
    clock.set(parisTime(22, 9, 0))

    let relaunched = SpendMeter(ceiling: 0.01, readerReserve: 0.002, persistence: store, calendar: paris, now: { clock.now })
    await relaunched.add(tokens: 500)
    await relaunched.flush()
    report.expectEqual(await store.rows["2026-09-22"], 1_500, "a relaunch carries on from the stored total")

    let burst = SpendMeter(persistence: store, calendar: paris, now: { clock.now })
    let writesBefore = await store.writes
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<300 { group.addTask { await burst.add(tokens: 10) } }
    }
    await burst.flush()
    let writes = await store.writes - writesBefore
    report.expectEqual(await store.rows["2026-09-22"], 4_500, "300 concurrent additions are all counted")
    report.expect(writes < 300, "and are stored in far fewer writes", detail: "\(writes) writes")

    await store.setBroken(true)
    let blind = SpendMeter(persistence: store, calendar: paris, now: { clock.now })
    await blind.add(tokens: 100)
    await blind.flush()
    let failure = await blind.persistenceFailure
    report.expect(failure != nil, "a store that cannot be read is reported, not swallowed")
    await store.setBroken(false)
    report.expectEqual(await store.rows["2026-09-22"], 4_500, "and the stored total is never overwritten by a meter that could not read it")
    await blind.add(tokens: 100)
    await blind.flush()
    let cleared = await blind.persistenceFailure
    report.expect(cleared == nil, "the failure clears once the store answers")
    report.expectEqual(await store.rows["2026-09-22"], 4_700, "and nothing counted in the meantime is lost")
}
