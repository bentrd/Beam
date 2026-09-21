import BeamJev
import BeamModels
import Foundation

private let items: [[String: String]] = [
    ["title": "MLX 0.30: faster quantized matmul on Apple Silicon", "snippet": "This release brings 4-bit kernels for M-series GPUs and lower memory use for on-device language models."],
    ["title": "Show HN: A sans-serif typeface drawn for small sizes", "snippet": "Open-source font with wide apertures, tuned hinting and tabular figures for dense interfaces."],
    ["title": "EU regulators fine ad network over location tracking", "snippet": "The decision says the company collected precise location data without valid consent from millions of people."],
    ["title": "Writing a borrow checker for a toy language in Rust", "snippet": "A walk through lifetimes, regions and the constraint solver, with all the code in one file."],
    ["title": "Why our startup moved off Kubernetes", "snippet": "Three engineers, forty services, and the operational cost that finally made us switch to plain virtual machines."],
    ["title": "Balatro passe la barre des cinq millions de ventes", "snippet": "Le jeu de cartes ind\u{00E9}pendant continue de s\u{00E9}duire sur consoles et mobiles, un an apr\u{00E8}s sa sortie."],
    ["title": "A field guide to sourdough starters", "snippet": "Hydration, feeding schedules and what the smell is telling you."],
    ["title": "Core ML adds stateful models for transformer caches", "snippet": "Key-value caches can now live on the Neural Engine between predictions, which speeds up token generation on iPhone."],
    ["title": "How GitHub's terms handle governing law and venue", "snippet": "Disputes are governed by California law and heard in San Francisco courts, with exceptions for some government users."],
    ["title": "Signal adds post-quantum ratchet to its protocol", "snippet": "The messenger upgrades its end-to-end encryption to resist future quantum attacks on recorded traffic."],
]

private let sentences = [
    "on-device ML on Apple Silicon", "privacy and surveillance", "is the Rust compiler hard to understand?",
    "typography", "trucs sur les jeux vid\u{00E9}o", "running a small engineering team",
].map(Sentence.init)

func checkLive(_ report: inout CheckReport, key: String) async {
    report.section("Live: api.typesafe.ai")
    let meter = SpendMeter()
    let judge = Judge(keyProvider: { key }, spend: meter)

    let good = await judge.validateKey()
    report.expect(good == .valid, "the key validates", detail: "\(good)")
    let bad = await judge.validate(key: "beam-check-jev-not-a-key")
    report.expect(bad == .rejected, "a bad key reports rejected", detail: "\(bad)")

    // 10 items x 4 sentences, one request each, all at once.
    let clock = ContinuousClock()
    let started = clock.now
    var pairs: [(item: Int, sentence: Int)] = []
    for item in items.indices { for sentence in 0..<4 { pairs.append((item, sentence)) } }
    let answers: [Result<Judgments, JevError>] = await withTaskGroup(of: Result<Judgments, JevError>.self) { group in
        for pair in pairs {
            group.addTask { await outcome { try await judge.judge(state: items[pair.item], frames: [sentences[pair.sentence].itemFrame()]) } }
        }
        var collected: [Result<Judgments, JevError>] = []
        for await answer in group { collected.append(answer) }
        return collected
    }
    let elapsed = clock.now - started
    let judged = answers.filter { (try? $0.get().probabilities.first ?? nil) != nil }.count
    let firstFailure = answers.compactMap { result -> JevError? in if case let .failure(error) = result { return error }; return nil }.first
    report.expect(judged == 40, "40 parallel judgments complete with valid answers", detail: "\(judged) of 40; \(String(describing: firstFailure))")
    report.note("40 judgments in \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))")

    // MUST 8: answers in a multi-question request equal the answers to the same questions asked alone.
    let state = items[0]
    let frames = sentences.map { $0.itemFrame() }
    let together = await outcome { try await judge.judge(state: state, frames: frames) }
    var worst = 0.0
    var compared = 0
    var lines: [String] = []
    for (index, frame) in frames.enumerated() {
        let alone = await outcome { try await judge.judge(state: state, frames: [frame]) }
        guard let packed = (try? together.get().probabilities[index]) ?? nil, let solo = (try? alone.get().probabilities.first) ?? nil else { continue }
        compared += 1
        worst = max(worst, abs(packed - solo))
        lines.append(String(format: "%.3f together, %.3f alone  %@", packed, solo, sentences[index].cleaned))
    }
    report.expect(compared == 6 && worst <= 0.02, "a 6-sentence request answers within 0.02 of six solo requests",
                  detail: "compared \(compared), worst difference \(String(format: "%.4f", worst))")
    lines.forEach(report.note)
    if let model = try? together.get().model { report.note("model \(model)") }

    let relevant = (try? together.get().probabilities[0]) ?? nil
    let unrelated = (try? together.get().probabilities[3]) ?? nil
    report.expect((relevant ?? 0) >= Bands.listFound && (unrelated ?? 1) < Bands.listUnsure, "the MLX item is found for on-device ML and nothing for typography")

    let spent = await meter.dollarsToday
    report.expect(spent > 0 && spent < 0.01, "every live answer was metered", detail: String(format: "$%.5f", spent))
    report.note(String(format: "this run cost $%.5f", spent))
}
