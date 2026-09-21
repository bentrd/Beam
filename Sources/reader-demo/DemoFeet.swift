import BeamModels

/// The foot sentences the engine will write, word for word from DESIGN.md section 6.
enum DemoFeet {
    static func checking(_ paragraphs: Int) -> Foot { Foot("Checking \(paragraphs) paragraphs") }

    static func settled(found: Int, unsure: Int, checked: Int, judgeable: Int, saturated: Bool, hasCode: Bool) -> Foot {
        if checked < judgeable {
            return Foot("\(checked) of \(judgeable) checked.", actionTitle: "Retry", action: .retry, isProminent: true)
        }
        if saturated {
            return Foot("Most of this article is about this.", actionTitle: "Find something narrower.", action: .findNarrower,
                        isProminent: true, help: "\(found) of \(checked) paragraphs")
        }
        var parts: [String] = []
        if found > 0 { parts.append("\(found) found") }
        if unsure > 0 { parts.append("\(unsure) unsure") }
        let sentence = parts.isEmpty ? "Nothing found in \(checked) paragraphs checked" : parts.joined(separator: ", ")
        return Foot(hasCode ? sentence + ". Code not checked." : sentence)
    }
}
