import Foundation
import PDFKit

struct Line { let text: String; let box: CGRect; let page: Int }
struct Passage: Codable { let page: Int; let text: String; let x: Double; let y: Double; let w: Double; let h: Double; let lines: Int }

let path = CommandLine.arguments[1]
guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { fatalError("cannot open") }
let clock = ContinuousClock(); let started = clock.now

func median(_ v: [CGFloat]) -> CGFloat { v.isEmpty ? 0 : v.sorted()[v.count / 2] }

var passages: [Passage] = []
for index in 0..<doc.pageCount {
    guard let page = doc.page(at: index) else { continue }
    let media = page.bounds(for: .mediaBox)
    guard let all = page.selection(for: media) else { continue }
    var lines: [Line] = []
    for sel in all.selectionsByLine() {
        let text = (sel.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let box = sel.bounds(for: page)
        guard !text.isEmpty, box.height > 1 else { continue }
        // running heads, footers and page numbers
        let nearEdge = box.minY < media.minY + media.height * 0.055 || box.maxY > media.maxY - media.height * 0.045
        if nearEdge && text.split(separator: " ").count < 9 { continue }
        lines.append(Line(text: text, box: box, page: index))
    }
    guard !lines.isEmpty else { continue }
    let lineHeight = median(lines.map(\.box.height))

    var current: [Line] = []
    func flush() {
        guard !current.isEmpty else { return }
        var text = ""
        for line in current {
            if text.hasSuffix("-"), let last = text.dropLast().last, last.isLetter, line.text.first?.isLowercase == true {
                text.removeLast(); text += line.text           // de-hyphenate a wrapped word
            } else { text += (text.isEmpty ? "" : " ") + line.text }
        }
        let box = current.map(\.box).reduce(current[0].box) { $0.union($1) }
        if text.count >= 50 {
            passages.append(Passage(page: index + 1, text: text, x: box.minX, y: box.minY, w: box.width, h: box.height, lines: current.count))
        }
        current = []
    }
    for line in lines {
        guard let prev = current.last else { current = [line]; continue }
        let gap = prev.box.minY - line.box.maxY                      // PDF space: y grows upward
        let jumpedUp = line.box.minY > prev.box.minY + lineHeight    // new column or out-of-flow block
        let sizeChange = abs(line.box.height - prev.box.height) > lineHeight * 0.22
        let bigGap = gap > lineHeight * 0.75
        let prevShort = prev.box.maxX < (current.map(\.box.maxX).max() ?? prev.box.maxX) - lineHeight * 2.5
        let indented = line.box.minX > prev.box.minX + lineHeight * 0.8 && current.count > 1
        let endsSentence = prev.text.last.map { ".:;!?”\"".contains($0) } ?? false
        let farSideways = abs(line.box.minX - prev.box.minX) > media.width * 0.25
        if jumpedUp || farSideways || bigGap || sizeChange || (endsSentence && (prevShort || indented)) { flush() }
        current.append(line)
    }
    flush()
}
let elapsed = clock.now - started
let words = passages.reduce(0) { $0 + $1.text.split(separator: " ").count }
FileHandle.standardError.write("\(doc.pageCount) pages -> \(passages.count) passages, \(words) words, in \(elapsed)\n".data(using: .utf8)!)
let lens = passages.map { $0.text.split(separator: " ").count }.sorted()
FileHandle.standardError.write("words/passage: min \(lens.first ?? 0)  median \(lens[lens.count/2])  p90 \(lens[Int(Double(lens.count)*0.9)])  max \(lens.last ?? 0)\n".data(using: .utf8)!)
let enc = JSONEncoder()
for p in passages { print(String(data: try! enc.encode(p), encoding: .utf8)!) }
