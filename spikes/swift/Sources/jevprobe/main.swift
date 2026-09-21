import Foundation
import JevKit

let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"] ?? ""
let client = JevClient(key: key)
let questions: [String: Question] = [
    "price": .noul(instructions: "The writer complains that the product costs too much"),
    "stance": .choice(instructions: "The writer's overall stance toward the product", options: [
        .init("happy", "Satisfied or delighted"),
        .init("mixed", "Satisfied with caveats"),
        .init("leaving", "Has left or intends to leave"),
    ]),
    "actionable": .score(instructions: "How actionable the feedback is", levels: [
        "A vague feeling", "Names an area", "Names a feature", "A concrete, reproducible request",
    ]),
]
let texts = [
    "Je résilie, 15 euros par mois c'est du vol.",
    "Export to PDF drops the last page on A4. Happens every time on 4.2.",
    "Love it.",
]
let clock = ContinuousClock()
let started = clock.now
await withTaskGroup(of: (String, Result<JevResponse, Error>).self) { group in
    for text in texts {
        group.addTask {
            do { return (text, .success(try await client.ask(state: ["feedback": text], questions: questions))) }
            catch { return (text, .failure(error)) }
        }
    }
    for await (text, result) in group {
        switch result {
        case let .success(r):
            print("\(Int(r.milliseconds)) ms  \(r.inputTokens) tok  \(text.prefix(44))")
            for (k, a) in r.answers.sorted(by: { $0.key < $1.key }) { print("    \(k): \(a)") }
        case let .failure(e):
            print("FAILED \(text.prefix(30)): \(e.localizedDescription)")
        }
    }
}
print("wall: \(clock.now - started)")
