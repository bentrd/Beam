import SwiftUI

@main
struct ReaderProbe: App {
    var body: some Scene {
        WindowGroup { Root().frame(minWidth: 820, minHeight: 620) }
            .windowStyle(.hiddenTitleBar)
    }
}

struct Root: View {
    @State private var passages: [Passage] = []
    @State private var states: [Int: HitState] = [:]
    @State private var marks: [Mark] = []
    @State private var jump: Int?
    @State private var query = "Apple admitted a feature is late"
    @State private var cursor = -1

    var hits: [Int] { states.filter { $0.value != .nothing }.keys.sorted() }

    var body: some View {
        ZStack(alignment: .top) {
            if passages.isEmpty { ProgressView() } else {
                HStack(spacing: 0) {
                    ReaderView(passages: passages, states: states, jumpTo: $jump) { marks = $0 }
                    Strip(marks: marks) { jump = $0 }.padding(.vertical, 12).padding(.trailing, 6)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(.secondary)
                TextField("What are you looking for?", text: $query).textFieldStyle(.plain).font(.system(size: 14))
                Text("\(states.values.filter { $0 == .found }.count) found · \(states.values.filter { $0 == .unsure }.count) unsure")
                    .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                Button { step(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain).keyboardShortcut("g", modifiers: .command)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .frame(width: 520).padding(.top, 14)
        }
        .task { await load() }
    }

    func step(_ d: Int) {
        guard !hits.isEmpty else { return }
        cursor = (cursor + d + hits.count) % hits.count
        jump = hits[cursor]
    }

    func load() async {
        let url = URL(string: CommandLine.arguments.dropFirst().first ?? "https://daringfireball.net/2025/03/something_is_rotten_in_the_state_of_cupertino")!
        var req = URLRequest(url: url); req.setValue("Mozilla/5.0 (Macintosh) Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), let result = try? extract(data, response: resp) else { return }
        passages = result.passages
        var s: [Int: HitState] = [:]
        for (i, p) in result.passages.enumerated() where p.kind != "heading" {     // stand-in for real judgments
            let t = p.text.lowercased()
            s[i] = t.contains("delay") || t.contains("“in the coming year”") ? .found : (t.contains("demo") ? .unsure : .nothing)
        }
        states = s
    }
}
