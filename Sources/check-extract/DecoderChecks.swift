import BeamExtract
import BeamModels
import Foundation

/// Bytes to text: the order of trust, and what happens when every declaration is missing or wrong.
enum DecoderChecks {
    static func run(_ report: inout CheckReport) {
        report.section("TextDecoder")
        let french = "<html><head><title>Actualités</title></head><body><p>L’été à Noël, déjà — « voilà ».</p></body></html>"
        let utf8 = Data(french.utf8)
        let latin1 = Data("<html><body><p>Actualit\u{E9}s d\u{E9}j\u{E0} vues</p></body></html>".unicodeScalars.map { UInt8($0.value) })

        report.expectEqual(TextDecoder.decode(utf8, httpCharset: "utf-8"), french, "HTTP charset utf-8 decodes accents and curly quotes")
        report.expectEqual(TextDecoder.decode(utf8, httpCharset: nil), french, "no declaration at all falls back to UTF-8, not Latin-1")
        report.expect(TextDecoder.decode(latin1, httpCharset: "ISO-8859-1").contains("Actualités déjà vues"), "HTTP charset ISO-8859-1 is honoured")
        report.expect(TextDecoder.decode(latin1, httpCharset: nil).contains("Actualités déjà vues"), "undeclared Latin-1 bytes fall through UTF-8 to Latin-1")

        let declared = Data("<html><head><meta charset=\"windows-1252\"></head><body>".utf8) + Data([0x93, 0x63, 0x61, 0x66, 0xE9, 0x94]) + Data("</body></html>".utf8)
        report.expect(TextDecoder.decode(declared, httpCharset: nil).contains("“café”"), "<meta charset> is used when HTTP names none (Windows-1252 quotes)")
        let legacyMeta = Data("<meta http-equiv=\"Content-Type\" content=\"text/html; charset=iso-8859-15\"><p>".utf8) + Data([0x31, 0x30, 0xA4])
        report.expect(TextDecoder.decode(legacyMeta, httpCharset: nil).contains("10€"), "http-equiv meta charset is read (ISO-8859-15 euro sign)")
        report.expect(TextDecoder.decode(legacyMeta, httpCharset: "utf-8").contains("10"), "a wrong HTTP charset never crashes and still yields text")

        let utf8Meta = Data("<meta charset=\"iso-8859-1\"><p>déjà</p>".utf8)
        report.expect(TextDecoder.decode(utf8Meta, httpCharset: "utf-8").contains("déjà"), "HTTP charset wins over a contradicting <meta>")

        let marked = Data([0xEF, 0xBB, 0xBF]) + Data("<p>élan</p>".utf8)
        report.expectEqual(TextDecoder.decode(marked, httpCharset: "iso-8859-1"), "<p>élan</p>", "a UTF-8 byte-order mark wins and is removed")

        var damaged = Data(String(repeating: "<p>Les élèves français étudient à l’école.</p>", count: 40).utf8)
        damaged[damaged.count / 2] = 0xFF
        let repaired = TextDecoder.decode(damaged, httpCharset: "utf-8")
        report.expect(repaired.contains("élèves français") && !repaired.contains("Ã"), "one broken byte in a UTF-8 page is repaired, not turned into mojibake")

        let japanese = "<p>吾輩は猫である。名前はまだ無い。</p>"
        if let shiftJIS = japanese.data(using: .shiftJIS) {
            report.expectEqual(TextDecoder.decode(shiftJIS, httpCharset: "Shift_JIS"), japanese, "any IANA charset the system knows is accepted (Shift_JIS)")
        }
    }
}
