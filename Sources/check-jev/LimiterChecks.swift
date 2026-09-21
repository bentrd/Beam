import BeamJev
import BeamModels
import Foundation

func checkLimiter(_ report: inout CheckReport) async {
    report.section("Limiter")
    await checkStorm(&report, capacity: 64, seed: 0xBEA4)
    await checkStorm(&report, capacity: 3, seed: 0x5EED)
    await checkOrder(&report)
    await checkCancelledWaiter(&report)
}

/// 500 tasks at once, four in ten cancelled at a random moment: before they start, while they queue, or while they hold a slot.
private func checkStorm(_ report: inout CheckReport, capacity: Int, seed: UInt64) async {
    let limiter = Limiter(capacity: capacity)
    let gauge = Gauge()
    var random = SplitMix64(seed: seed)

    var tasks: [Task<Void, Error>] = []
    var cancellers: [Task<Void, Never>] = []
    for _ in 0..<500 {
        let work = UInt64.random(in: 1...6, using: &random) * 1_000_000
        let task = Task {
            try await limiter.withSlot {
                await gauge.enter()
                let slept: Void? = try? await Task.sleep(nanoseconds: work)
                await gauge.leave()
                if slept == nil { throw CancellationError() }
            }
        }
        tasks.append(task)
        if Int.random(in: 0..<10, using: &random) < 4 {
            let delay = UInt64.random(in: 0...40, using: &random) * 1_000_000
            cancellers.append(Task {
                try? await Task.sleep(nanoseconds: delay)
                task.cancel()
            })
        }
    }

    var finished = 0
    var cancelled = 0
    for task in tasks {
        if await task.result.isCancellation { cancelled += 1 } else { finished += 1 }
    }
    for canceller in cancellers { await canceller.value }

    let peak = await gauge.peak
    let settled = await eventually { await limiter.load.isIdle }
    let load = await limiter.load
    report.expect(peak <= capacity, "cap \(capacity): never more than \(capacity) at once under 500 tasks", detail: "peak \(peak)")
    report.expect(peak == capacity, "cap \(capacity): the cap was actually reached", detail: "peak \(peak)")
    report.expect(finished > 0 && cancelled > 0 && finished + cancelled == 500, "cap \(capacity): every task ended (\(finished) finished, \(cancelled) cancelled)")
    report.expect(settled, "cap \(capacity): ends with zero slots held and nobody waiting", detail: "\(load)")
}

/// With one slot, waiters must run in the order they arrived, and a cancelled one must drop out without disturbing the rest.
private func checkOrder(_ report: inout CheckReport) async {
    let limiter = Limiter(capacity: 1)
    let order = OrderLog()
    let gate = Task { try await limiter.withSlot { try await Task.sleep(nanoseconds: 60_000_000_000) } }
    var queuedInOrder = await eventually { await limiter.load.held == 1 }

    var waiters: [Task<Void, Error>] = []
    for index in 0..<20 {
        waiters.append(Task { try await limiter.withSlot { await order.append(index) } })
        let queued = await eventually { await limiter.load.waiting == index + 1 }
        queuedInOrder = queuedInOrder && queued
    }
    waiters[7].cancel()
    let left = await eventually { await limiter.load.waiting == 19 }
    gate.cancel()
    for waiter in waiters { _ = await waiter.result }

    report.expect(queuedInOrder && left, "twenty waiters queue behind one slot; a cancelled one leaves the queue at once")
    report.expectEqual(await order.values, Array(0..<20).filter { $0 != 7 }, "slots are granted first come, first served")
    let seventh = await waiters[7].result
    report.expect(seventh.isCancellation, "the cancelled waiter got CancellationError and never ran")
}

private func checkCancelledWaiter(_ report: inout CheckReport) async {
    let limiter = Limiter(capacity: 1)
    let holder = Task { try await limiter.withSlot { try await Task.sleep(nanoseconds: 60_000_000_000) } }
    _ = await eventually { await limiter.load.held == 1 }
    let waiter = Task { try await limiter.withSlot {} }
    _ = await eventually { await limiter.load.waiting == 1 }
    waiter.cancel()
    _ = await waiter.result
    holder.cancel()
    _ = await holder.result
    let free = await eventually { await limiter.load.isIdle }
    report.expect(free, "a waiter cancelled in the queue leaks no slot")

    let already = Task { () -> Bool in
        withUnsafeCurrentTask { $0?.cancel() }
        return (try? await limiter.withSlot { true }) ?? false
    }
    let ran = await already.value
    let held = await limiter.load.held
    let next = try? await limiter.withSlot { 42 }
    report.expect(!ran, "a task cancelled before it asks runs nothing")
    report.expect(held == 0, "and takes no slot")
    report.expect(next == 42, "the slot is free for the next caller")
}

private actor OrderLog {
    private(set) var values: [Int] = []
    func append(_ value: Int) { values.append(value) }
}

func checkJudgeLimit(_ report: inout CheckReport) async {
    report.section("Judge: one limiter for everything")
    let service = FakeService(latency: 1...5)
    let judge = Judge(keyProvider: { "k" }, spend: SpendMeter(), client: JevClient(transport: service.transport))
    var random = SplitMix64(seed: 0x1D6E)

    var tasks: [Task<Judgments, Error>] = []
    for index in 0..<500 {
        let purpose: SpendMeter.Purpose = index % 3 == 0 ? .reading : .ranking
        let task = Task { try await judge.judge(state: ["title": "item \(index)"], frames: ["f"], for: purpose) }
        tasks.append(task)
        if Int.random(in: 0..<10, using: &random) < 3 { task.cancel() }
    }
    async let validation = judge.validateKey()
    var answered = 0
    for task in tasks where (try? await task.value) != nil { answered += 1 }
    let status = await validation

    report.expect(service.peakInFlight <= 64, "500 judgments with random cancellation never put more than 64 requests in flight", detail: "peak \(service.peakInFlight)")
    report.expect(service.peakInFlight > 32, "and the limiter is not needlessly tight", detail: "peak \(service.peakInFlight)")
    report.expect(answered > 0 && answered < 500 && status == .valid, "\(answered) answered, the rest cancelled; key validation shared the same limiter")
    let idle = await eventually { await judge.load.isIdle }
    report.expect(idle, "ends with zero slots held")

    let before = service.requests.count
    let none = try? await judge.judge(state: ["title": "t"], frames: [])
    report.expect(none?.probabilities.isEmpty == true && service.requests.count == before, "no frames, no request")
}
