import BeamModels
import BeamStore
import Foundation

func checkPins(_ report: inout CheckReport) async throws {
    let database = try Database.inMemory()
    var pins: [Pin] = []
    for number in 1...9 {
        if case let .pinned(pin) = try await database.addPin(sentence: "sentence \(number)", at: Fixtures.now) { pins.append(pin) }
    }
    report.expectEqual(pins.map(\.position), Array(0..<9), "nine pins, in order, one per ⌘-digit")
    report.expectEqual(pins.first?.created, Fixtures.now, "created round-trips")

    var tenth = false
    if case .limitReached = try await database.addPin(sentence: "sentence 10") { tenth = true }
    report.expect(tenth, "the tenth pin is refused: nine pins maximum")
    report.expectEqual(try await database.pins().count, Pin.maximum, "and nothing was stored for it")

    var duplicate: Pin?
    if case let .alreadyPinned(pin) = try await database.addPin(sentence: "sentence 3") { duplicate = pin }
    report.expectEqual(duplicate?.id, pins[2].id, "pinning a pinned sentence answers with the existing pin, even at the limit")

    try await database.movePin(id: pins[8].id, by: -8)
    try await database.movePin(id: pins[0].id, by: 1)
    let moved = try await database.pins()
    report.expectEqual(moved.prefix(3).map(\.sentence), ["sentence 9", "sentence 2", "sentence 1"], "pins move by offset")
    report.expectEqual(moved.map(\.position), Array(0..<9), "positions stay 0..<9")
    try await database.movePin(id: pins[8].id, by: -5)
    report.expectEqual(try await database.pins().first?.id, pins[8].id, "a move stops at the top")

    let viewed = Fixtures.now.addingTimeInterval(600)
    try await database.markPinViewed(id: pins[4].id, at: viewed)
    report.expectEqual(try await database.pin(id: pins[4].id)?.lastViewed, viewed, "last viewed is recorded")

    // Remove Pin and its Undo.
    let victim = try await database.pin(id: pins[1].id)
    let removed = try await database.removePin(id: pins[1].id)
    report.expectEqual(removed, victim, "removePin returns the pin as it was")
    let remaining = try await database.pins()
    report.expect(remaining.count == 8 && remaining.map(\.position) == Array(0..<8), "eight remain, positions closed up")
    report.expectTrue(try await database.removePin(id: pins[1].id) == nil, "removing it twice is a no-op")

    var restored: Pin?
    if case let .pinned(pin) = try await database.restorePin(id: pins[1].id) { restored = pin }
    report.expectEqual(restored, victim, "Undo Remove Pin brings it back in its former place")
    report.expectEqual(try await database.pins().map(\.position), Array(0..<9), "positions are 0..<9 again")

    _ = try await database.removePin(id: pins[1].id)
    var replacement: Pin?
    if case let .pinned(pin) = try await database.addPin(sentence: "took the free slot") { replacement = pin }
    report.expect(replacement != nil, "a removed pin frees its slot")
    var blocked = false
    if case .limitReached = try await database.restorePin(id: pins[1].id) { blocked = true }
    report.expect(blocked, "Undo cannot exceed nine pins")
    report.expectEqual(try await database.pins().count, 9, "still nine")

    if let replacement { _ = try await database.removePin(id: replacement.id) }
    var revived: Pin?
    if case let .pinned(pin) = try await database.addPin(sentence: "sentence 2") { revived = pin }
    report.expectEqual(revived?.id, pins[1].id, "pinning a sentence unpinned this session revives its pin")
    report.expectEqual(revived?.position, 8, "at the end of the list")

    let unknown = await failure { _ = try await database.restorePin(id: 777) }
    report.expectEqual(unknown, .notFound("pin 777"), "restoring an unknown pin is an error")
}
