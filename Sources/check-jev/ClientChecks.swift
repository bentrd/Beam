import BeamJev
import BeamModels
import Foundation

func checkValidation(_ report: inout CheckReport) async {
    report.section("Answer validation")
    report.expect(Probability.validated(0.0) == 0.0 && Probability.validated(1.0) == 1.0 && Probability.validated(0.42) == 0.42, "accepts 0, 1 and what lies between")
    report.expect(Probability.validated(Double.nan) == nil, "rejects NaN")
    report.expect(Probability.validated(Double.infinity) == nil && Probability.validated(-Double.infinity) == nil, "rejects infinities")
    report.expect(Probability.validated(-0.0001) == nil && Probability.validated(1.0001) == nil, "rejects out of range")
    report.expect(Probability.validated(nil) == nil && Probability.validated(NSNull()) == nil, "rejects missing and null")
    report.expect(Probability.validated("0.5") == nil && Probability.validated(true) == nil, "rejects strings and booleans")

    // The same gate, reached the way real answers reach it: through a response body.
    let body = FakeService.answers(["0.87", "1.5", "-0.2", "true", "\"0.5\"", "null", "0"], tokens: 412, model: "jev-1.13.0")
        .replacingOccurrences(of: "\"q6\": {\"type\": \"noul\"", with: "\"q6\": {\"type\": \"score\"")
    let service = FakeService(script: [.http(200, body: body)])
    let client = JevClient(transport: service.transport)
    let frames = (0..<8).map { "frame \($0)" }
    do {
        let judgments = try await client.ask(key: "k", state: ["title": "t"], frames: frames)
        report.expectEqual(judgments.probabilities, [0.87, nil, nil, nil, nil, nil, nil, nil], "invalid, mistyped and missing answers become nil; the valid one survives")
        report.expect(judgments.tokens == 412 && judgments.model == "jev-1.13.0", "tokens and model come back with the answers")
    } catch {
        report.expect(false, "a response with some invalid answers still decodes", detail: "\(error)")
    }

    let malformed = [
        ("not JSON", "<html>busy</html>"),
        ("no answers", "{\"model\": \"m\", \"usage\": {\"input_tokens\": 1}}"),
        ("no token count (cannot be priced)", "{\"model\": \"m\", \"answers\": {}}"),
        ("no model (cannot be cached)", "{\"answers\": {}, \"usage\": {\"input_tokens\": 1}}"),
        ("fractional token count", "{\"model\": \"m\", \"answers\": {}, \"usage\": {\"input_tokens\": 1.5}}"),
        ("negative token count", "{\"model\": \"m\", \"answers\": {}, \"usage\": {\"input_tokens\": -1}}"),
        ("boolean token count", "{\"model\": \"m\", \"answers\": {}, \"usage\": {\"input_tokens\": true}}"),
        ("overflowing token count", "{\"model\": \"m\", \"answers\": {}, \"usage\": {\"input_tokens\": 1e100}}"),
    ]
    for (what, body) in malformed {
        let client = JevClient(transport: FakeService(script: [.http(200, body: body)]).transport)
        let result = await outcome { try await client.ask(key: "k", state: [:], frames: ["f"]) }
        report.expect(result == .failure(.malformedResponse), "malformed response: \(what)", detail: "\(result)")
    }
}

func checkClient(_ report: inout CheckReport) async {
    report.section("Client: request, retries, errors")
    let frames = [Sentence("rust").itemFrame(), Sentence("privacy").itemFrame(), Sentence("is this about MLX?").itemFrame()]
    let state = ["title": "MLX 0.30 released", "snippet": "Faster \"quantized\" matmul"]
    let service = FakeService(script: [.http(200, body: FakeService.answers(["0.1", "0.2", "0.9"]))])
    _ = await outcome { try await JevClient(transport: service.transport).ask(key: "secret-key", state: state, frames: frames) }

    if let request = service.requests.first, let body = request.httpBody,
       let sent = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let questions = sent["questions"] as? [String: [String: String]] {
        report.expect(request.url == JevClient.endpoint && request.httpMethod == "POST", "POSTs to /v1/systemone")
        report.expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key", "the key travels as a bearer token")
        report.expectEqual(sent["model"] as? String, "jev-latest", "asks for jev-latest")
        report.expectEqual(sent["state"] as? [String: String], state, "state is sent as given")
        report.expectEqual(questions.count, 3, "all frames travel in one request")
        report.expect(frames.indices.allSatisfy { questions["q\($0)"] == ["type": "noul", "instructions": frames[$0]] }, "each frame is one Noul, in order")
        report.expectEqual(service.requests.count, 1, "one request, no more")
    } else {
        report.expect(false, "the request body is readable JSON")
    }

    let busy = FakeService(script: [.http(429, body: ""), .http(529, body: ""), .http(503, body: ""), .failure(.timedOut), .http(200, body: FakeService.answers(["0.7"]))])
    let log = PauseLog()
    let recovered = await outcome { try await JevClient(transport: busy.transport, pause: log.pause).ask(key: "k", state: [:], frames: ["f"]) }
    report.expect((try? recovered.get().probabilities) == [0.7], "429, 529, 503 and a timeout are retried until the answer arrives", detail: "\(recovered)")
    report.expectEqual(busy.requests.count, 5, "five tries")
    let expectedPauses = [0.4, 0.8, 1.6, 3.2]
    report.expect(log.pauses.count == 4 && zip(log.pauses, expectedPauses).allSatisfy { $0 >= $1 && $0 <= $1 * 1.25 },
                  "waits 0.4 s, doubling, with at most a quarter of jitter", detail: "\(log.pauses)")

    let down = FakeService(fallback: .http(529, body: ""))
    let gaveUp = await outcome { try await JevClient(transport: down.transport, pause: PauseLog().pause).ask(key: "k", state: [:], frames: ["f"]) }
    report.expect(gaveUp == .failure(.overloaded(status: 529)) && down.requests.count == 5, "gives up after five tries with the last status", detail: "\(gaveUp)")

    let cases: [(String, FakeService.Reply, JevError, Int)] = [
        ("401 is unauthorized, not retried", .http(401, body: ""), .unauthorized, 1),
        ("403 is unauthorized, not retried", .http(403, body: ""), .unauthorized, 1),
        ("422 is rejected with the key redacted, not retried", .http(422, body: "bad field near secret-key"), .rejected(status: 422, detail: "bad field near <key>"), 1),
        ("no connection fails at once", .failure(.notConnectedToInternet), .unreachable(URLError(.notConnectedToInternet).localizedDescription), 1),
        ("a dropped connection is retried, then unreachable", .failure(.networkConnectionLost), .unreachable(URLError(.networkConnectionLost).localizedDescription), 5),
    ]
    for (what, reply, expected, tries) in cases {
        let service = FakeService(fallback: reply)
        let result = await outcome { try await JevClient(transport: service.transport, pause: PauseLog().pause).ask(key: "secret-key", state: [:], frames: ["f"]) }
        report.expect(result == .failure(expected) && service.requests.count == tries, what, detail: "\(result) after \(service.requests.count) tries")
    }

    let untouched = FakeService()
    let keyless = await outcome { try await JevClient(transport: untouched.transport).ask(key: "", state: [:], frames: ["f"]) }
    report.expect(keyless == .failure(.missingKey) && untouched.requests.isEmpty, "an empty key sends nothing")
    let blank = await outcome { try await JevClient(transport: untouched.transport).ask(key: " \n\t", state: [:], frames: ["f"]) }
    report.expect(blank == .failure(.missingKey) && untouched.requests.isEmpty, "a whitespace-only key sends nothing")
    let injected = await outcome { try await JevClient(transport: untouched.transport).ask(key: "key\r\nAuthorization: injected", state: [:], frames: ["f"]) }
    report.expect(injected == .failure(.unauthorized) && untouched.requests.isEmpty, "line breaks in a key are rejected before building an HTTP header")

    let reflectedKey = String(repeating: "z", count: 100)
    let reflected = FakeService(fallback: .http(422, body: String(repeating: "x", count: 290) + reflectedKey))
    let redacted = await outcome { try await JevClient(transport: reflected.transport).ask(key: reflectedKey, state: [:], frames: ["f"]) }
    if case let .failure(.rejected(_, detail)) = redacted {
        report.expect(!detail.contains("z") && detail.hasSuffix("<key>"), "a reflected key is redacted before truncation, including across the boundary")
    } else {
        report.expect(false, "the reflected-key rejection is reported")
    }

    struct ReflectedTransportError: LocalizedError {
        var errorDescription: String? { "Failed request using secret-key" }
    }
    let transportError = await outcome {
        try await JevClient(transport: { _ in throw ReflectedTransportError() }, pause: { _ in })
            .ask(key: "secret-key", state: [:], frames: ["f"])
    }
    report.expect(transportError == .failure(.unreachable("Failed request using <key>")), "transport error messages cannot expose the credential")

    let cancelled = FakeService(fallback: .failure(.cancelled))
    let task = Task { try await JevClient(transport: cancelled.transport, pause: PauseLog().pause).ask(key: "k", state: [:], frames: ["f"]) }
    let wasCancelled = await task.result.isCancellation
    report.expect(wasCancelled && cancelled.requests.count == 1, "URLSession's own cancellation surfaces as CancellationError, not retried")

    report.section("Failure streak")
    var streak = FailureStreak()
    for _ in 0..<9 { streak.record(JevError.overloaded(status: 529)) }
    report.expect(!streak.shouldStop, "nine consecutive failures keep the run going")
    streak.recordSuccess()
    for _ in 0..<9 { streak.record(JevError.unreachable("x")) }
    streak.record(CancellationError())
    streak.record(JevError.dailyLimitReached)
    report.expect(!streak.shouldStop, "a success resets the count; cancellation and the daily limit do not count")
    streak.record(JevError.malformedResponse)
    report.expect(streak.shouldStop, "the tenth consecutive failure stops the run")
}

/// A `Result` whose failure is a `JevError`, so checks can compare outcomes with `==`. Any other error is reported as unreachable with its description.
func outcome(_ work: () async throws -> Judgments) async -> Result<Judgments, JevError> {
    do { return .success(try await work()) }
    catch let error as JevError { return .failure(error) }
    catch { return .failure(.unreachable("unexpected: \(error)")) }
}
