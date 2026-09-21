import Foundation

/// Gets a feed's bytes into a shape `XMLParser` accepts.
///
/// Real feeds are not well-formed XML: they open with a byte-order mark or a blank line, declare one encoding and
/// use another, carry HTML entities XML has never heard of, bare ampersands and control characters. `XMLParser`
/// stops at the first of these, so they are repaired before it runs. The result is always UTF-8 with no XML
/// declaration, which also means the parser never has to trust the declared encoding.
enum FeedText {
    /// - Parameter charsetHint: the HTTP `charset`, used only when the bytes carry no mark and no declaration.
    static func repairedXML(from data: Data, charsetHint: String? = nil) -> Data {
        var text = decode(data, charsetHint: charsetHint)
        if let firstTag = text.firstIndex(of: "<"), firstTag != text.startIndex {
            text.removeSubrange(text.startIndex..<firstTag)
        }
        text = removingXMLDeclaration(text)
        return Data(repairingReferences(in: text).utf8)
    }

    // MARK: Decoding

    /// Order of trust: byte-order mark, the XML declaration, the HTTP header, then UTF-8, then Windows-1252
    /// (which, unlike UTF-8, can decode any byte, so something always comes out).
    static func decode(_ data: Data, charsetHint: String? = nil) -> String {
        if let marked = decodeByMark(data) { return marked }
        let declared = declaredEncoding(in: data) ?? charsetHint
        if let name = declared, let encoding = encoding(named: name) {
            if encoding == .utf8 {
                // A feed that says UTF-8 and mostly is: replacing the odd bad byte beats turning every accent into mojibake.
                return String(decoding: data, as: UTF8.self)
            }
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    private static func decodeByMark(_ data: Data) -> String? {
        let marks: [([UInt8], String.Encoding)] = [
            ([0xEF, 0xBB, 0xBF], .utf8),
            ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian), ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
            ([0xFF, 0xFE], .utf16LittleEndian), ([0xFE, 0xFF], .utf16BigEndian),
        ]
        for (mark, encoding) in marks where data.starts(with: mark) {
            let body = data.dropFirst(mark.count)
            return encoding == .utf8 ? String(decoding: body, as: UTF8.self) : String(data: body, encoding: encoding)
        }
        return nil
    }

    /// Reads `encoding="…"` from the XML declaration. Every encoding a feed is likely to declare is ASCII-compatible
    /// in its first bytes, so the declaration can be read before the encoding is known.
    private static func declaredEncoding(in data: Data) -> String? {
        let head = String(decoding: data.prefix(256), as: UTF8.self)
        guard let declarationEnd = head.range(of: "?>"), head.contains("<?xml") else { return nil }
        let declaration = head[..<declarationEnd.lowerBound]
        guard let key = declaration.range(of: "encoding", options: .caseInsensitive) else { return nil }
        let afterKey = declaration[key.upperBound...].drop(while: { $0 == " " || $0 == "=" })
        guard let quote = afterKey.first, quote == "\"" || quote == "'" else { return nil }
        let value = afterKey.dropFirst().prefix(while: { $0 != quote })
        return value.isEmpty ? nil : String(value)
    }

    private static func encoding(named name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name.trimmingCharacters(in: .whitespaces) as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    private static func removingXMLDeclaration(_ text: String) -> String {
        guard text.hasPrefix("<?xml"), let end = text.range(of: "?>") else { return text }
        return String(text[end.upperBound...])
    }

    // MARK: References and control characters

    /// Outside CDATA: named HTML entities become numeric references, ampersands that start no reference become
    /// `&amp;`, and characters XML 1.0 forbids are dropped. CDATA is copied untouched, because there `&nbsp;` is
    /// literal text for the HTML layer to decode later.
    static func repairingReferences(in text: String) -> String {
        let source = Array(text.utf8)
        var output = [UInt8]()
        output.reserveCapacity(source.count + source.count / 16)
        let cdataOpen = Array("<![CDATA[".utf8), cdataClose = Array("]]>".utf8)
        var index = 0
        while index < source.count {
            let byte = source[index]
            if byte == UInt8(ascii: "<"), matches(cdataOpen, in: source, at: index) {
                let end = firstIndex(of: cdataClose, in: source, from: index).map { $0 + cdataClose.count } ?? source.count
                output.append(contentsOf: source[index..<end].filter(isAllowedByte))
                index = end
            } else if byte == UInt8(ascii: "&") {
                index = appendReference(from: source, at: index, to: &output)
            } else {
                if isAllowedByte(byte) { output.append(byte) }
                index += 1
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// Appends a reference XML will accept for whatever starts at `ampersand`, and returns the index to continue from.
    private static func appendReference(from source: [UInt8], at ampersand: Int, to output: inout [UInt8]) -> Int {
        var end = ampersand + 1
        while end < source.count, end - ampersand <= 12, isReferenceByte(source[end]) { end += 1 }
        guard end < source.count, source[end] == UInt8(ascii: ";"), end > ampersand + 1 else {
            output.append(contentsOf: "&amp;".utf8)
            return ampersand + 1
        }
        let body = String(decoding: source[(ampersand + 1)..<end], as: UTF8.self)
        if HTMLEntities.xmlPredefined.contains(body) {
            output.append(contentsOf: source[ampersand...end])
        } else if let scalar = HTMLText.scalar(forReference: body) {
            // Numeric references to characters XML forbids (`&#0;`, `&#x1F;`) are fatal too: drop them.
            if isAllowedScalar(scalar) { output.append(contentsOf: "&#\(scalar.value);".utf8) }
        } else {
            output.append(contentsOf: "&amp;".utf8)
            return ampersand + 1
        }
        return end + 1
    }

    private static func isReferenceByte(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || byte == UInt8(ascii: "#")
    }

    /// XML 1.0 allows tab, line feed and carriage return below U+0020, and nothing else.
    private static func isAllowedByte(_ byte: UInt8) -> Bool {
        byte >= 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func isAllowedScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0D, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: return true
        default: return false
        }
    }

    private static func matches(_ pattern: [UInt8], in source: [UInt8], at index: Int) -> Bool {
        index + pattern.count <= source.count && source[index..<(index + pattern.count)].elementsEqual(pattern)
    }

    private static func firstIndex(of pattern: [UInt8], in source: [UInt8], from start: Int) -> Int? {
        guard source.count >= pattern.count else { return nil }
        var index = start
        while index + pattern.count <= source.count {
            if source[index] == pattern[0], matches(pattern, in: source, at: index) { return index }
            index += 1
        }
        return nil
    }
}
