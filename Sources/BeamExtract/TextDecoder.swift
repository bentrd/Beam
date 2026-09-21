import Foundation

/// Turns the raw bytes of a web page into a `String` before any HTML parsing happens.
///
/// Why this exists: `XMLDocument`'s tidy guesses the encoding when handed bytes, and it guesses wrong on
/// ordinary UTF-8 pages ("Iâ€™ve", "ActualitÃ©s", measured in EVIDENCE.md). Beam therefore decodes first and
/// hands tidy a `String`, so tidy never gets to guess.
///
/// Order, as browsers do it: a byte-order mark, the HTTP `charset`, a `<meta>` charset in the first bytes,
/// UTF-8, and finally Latin-1 in its web sense (Windows-1252), which accepts any byte sequence.
public enum TextDecoder {
    /// How far into the page a `<meta charset>` is looked for. Browsers stop at 1,024 bytes; real pages put
    /// long preload lists first, so Beam looks a little further.
    static let metaScanLength = 8192

    public static func decode(_ data: Data, httpCharset: String?) -> String {
        if let marked = decodeByteOrderMark(data) { return marked }

        var candidates: [String.Encoding] = []
        for name in [httpCharset, declaredCharset(in: data)] {
            if let encoding = name.flatMap(encoding(named:)), !candidates.contains(encoding) { candidates.append(encoding) }
        }
        if !candidates.contains(.utf8) { candidates.append(.utf8) }

        for encoding in candidates {
            if let text = String(data: data, encoding: encoding) { return text }
            // A UTF-8 page with a few broken bytes is still a UTF-8 page: repairing it beats turning every accent into mojibake.
            if encoding == .utf8, isDamagedUTF8(data) { return String(decoding: data, as: UTF8.self) }
        }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    /// The charset named by `<meta charset="…">` or `<meta http-equiv="Content-Type" content="…; charset=…">`.
    static func declaredCharset(in data: Data) -> String? {
        guard let head = String(data: data.prefix(metaScanLength), encoding: .isoLatin1) else { return nil }
        let pattern = #"<meta\b[^>]*?charset\s*=\s*["']?\s*([A-Za-z0-9_:.\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
              let range = Range(match.range(at: 1), in: head) else { return nil }
        return String(head[range])
    }

    /// Maps an IANA charset label to an encoding. Labels of the Latin-1 family mean Windows-1252 on the web
    /// (the WHATWG Encoding Standard): bytes 0x80-0x9F are curly quotes and dashes there, not control codes.
    static func encoding(named label: String) -> String.Encoding? {
        let name = label.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'")).lowercased()
        guard !name.isEmpty else { return nil }
        if ["utf-8", "utf8"].contains(name) { return .utf8 }
        if ["iso-8859-1", "iso8859-1", "latin1", "latin-1", "us-ascii", "ascii", "windows-1252", "cp1252"].contains(name) { return .windowsCP1252 }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    private static func decodeByteOrderMark(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            let body = data.dropFirst(3)
            return String(data: body, encoding: .utf8) ?? String(decoding: body, as: UTF8.self)
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) }
        return nil
    }

    /// True when the bytes are overwhelmingly well-formed multi-byte UTF-8 with only a few bad sequences.
    /// Genuine Latin-1 text looks the opposite: an accented byte followed by ASCII is never valid UTF-8.
    static func isDamagedUTF8(_ data: Data) -> Bool {
        var valid = 0, invalid = 0, index = 0
        let bytes = [UInt8](data)
        while index < bytes.count {
            let byte = bytes[index]
            if byte < 0x80 { index += 1; continue }
            let length: Int
            switch byte {
            case 0xC2...0xDF: length = 2
            case 0xE0...0xEF: length = 3
            case 0xF0...0xF4: length = 4
            default: length = 0
            }
            let tail = bytes[min(index + 1, bytes.count)..<min(index + max(length, 1), bytes.count)]
            if length > 0, tail.count == length - 1, tail.allSatisfy({ $0 & 0xC0 == 0x80 }) { valid += 1; index += length }
            else { invalid += 1; index += 1 }
        }
        return valid > 0 && valid >= invalid * 8
    }
}
