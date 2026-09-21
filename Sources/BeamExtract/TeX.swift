import Foundation

/// Turns the TeX source that KaTeX and MathJax leave in the page into readable Unicode maths.
///
/// Beam's reader is text, not a web view, so there is no renderer to hand the maths to. The page offers two
/// things and both are bad on their own: the visual markup reads as `x2x^2` once the tags are gone, and the TeX
/// source reads as `\frac{\partial f}{\partial v}`. This turns the source into `∂f/∂v`, which is what a person
/// reading a blog post about backpropagation actually wants to see.
///
/// It is deliberately not a TeX engine. It covers what appears in prose — symbols, sub- and superscripts, simple
/// fractions, sums and roots — and it throws away the commands that only exist to control layout (`\Big`,
/// `\begin{aligned}`, alignment `&`). Anything it does not know survives with its backslash removed rather than
/// being dropped, so an unusual command degrades to a word instead of to nothing.
public enum TeX {
    /// The maximum source length worth converting. Past this it is a displayed derivation, not a phrase, and the
    /// cost of a pathological regex walk outweighs the benefit.
    static let maximumLength = 4_000

    public static func readable(_ source: String) -> String {
        guard !source.isEmpty, source.count <= maximumLength else { return collapse(source) }
        var text = source

        // Environments and layout carry no meaning; the contents do.
        text = environments.replace(in: text, with: " ")
        text = sizing.replace(in: text, with: "")

        // Innermost groups resolve first, so `\frac{QK^T}{\sqrt{d_k}}` can only be read once `\sqrt{d_k}` has
        // become `√dₖ` and left no braces behind. Each pass is strictly simplifying, so this settles quickly.
        for _ in 0..<6 {
            let before = text
            text = symbols(text)                          // `\mathbb{R}` is a symbol, not a font command
            text = braceCommand(text, names: fontCommands)
            text = colourCommand(text)
            text = braceCommand(text, names: decorations)
            text = roots(text)                            // before fractions: a root is often a denominator
            text = fractions(text)
            text = scripts(text)
            if text == before { break }
        }
        text = symbols(text)
        // A `\sqrt` with no group left to read (a stray one) still deserves its character.
        text = text.replacingOccurrences(of: "\\sqrt", with: "√")

        // Alignment and line breaks inside a display block become ordinary spaces: a passage is one run of text.
        // The ampersand arrives as an entity when the annotation came from HTML, so both spellings go.
        text = text.replacingOccurrences(of: "\\\\", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: " ")
        text = text.replacingOccurrences(of: "&", with: " ")
        text = text.replacingOccurrences(of: "$", with: "")
        // Whatever is left: keep the word, drop the marker, so an unknown command degrades to a word rather than
        // to nothing — and so that no backslash or brace can reach the reader, which is the one hard promise.
        text = unknownCommand.replace(in: text, with: "$1")
        text = text.replacingOccurrences(of: "\\", with: "")
        text = text.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        return collapse(text)
    }

    /// True when the source is worth showing at all: a lone `\,` or an empty group is noise.
    public static func isMeaningful(_ source: String) -> Bool {
        !readable(source).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }


    // MARK: Balanced groups
    //
    // `[^{}]*` cannot read `\frac{QK^T}{\sqrt{d_{k}}}`, and real papers nest braces three deep. These read a
    // command's arguments by counting braces, which is the only way to get the denominator right.

    /// The text of the balanced `{…}` starting at `index`, and the index just past its closing brace.
    private static func group(in text: [Character], at index: Int) -> (body: String, end: Int)? {
        guard index < text.count, text[index] == "{" else { return nil }
        var depth = 0
        var cursor = index
        while cursor < text.count {
            if text[cursor] == "{" { depth += 1 }
            else if text[cursor] == "}" {
                depth -= 1
                if depth == 0 { return (String(text[(index + 1)..<cursor]), cursor + 1) }
            }
            cursor += 1
        }
        return nil
    }

    /// Rewrites every `\name{…}…` in `text`, giving `body` the command's arguments.
    /// `arity` is how many groups the command takes; a command with too few arguments is left alone.
    private static func command(_ text: String, _ names: [String], arity: Int,
                                body: (_ name: String, _ arguments: [String]) -> String) -> String {
        guard names.contains(where: { text.contains("\\" + $0) }) else { return text }
        let characters = Array(text)
        var out = ""
        var index = 0
        while index < characters.count {
            guard characters[index] == "\\" else { out.append(characters[index]); index += 1; continue }
            // The longest name first, so `\textbf` is not read as `\text` followed by `bf`.
            let name = names.sorted { $0.count > $1.count }.first { candidate in
                let start = index + 1
                let end = start + candidate.count
                guard end <= characters.count, String(characters[start..<end]) == candidate else { return false }
                // The next character must not continue the name, or `\pi` would match inside `\pistol`.
                return end == characters.count || !characters[end].isLetter
            }
            guard let name else { out.append(characters[index]); index += 1; continue }

            var cursor = index + 1 + name.count
            var arguments: [String] = []
            for _ in 0..<arity {
                while cursor < characters.count, characters[cursor] == " " { cursor += 1 }
                guard let found = group(in: characters, at: cursor) else { break }
                arguments.append(found.body)
                cursor = found.end
            }
            guard arguments.count == arity else { out.append(characters[index]); index += 1; continue }
            out += body(name, arguments)
            index = cursor
        }
        return out
    }

    // MARK: Pieces

    private static let fontCommands = ["text", "textrm", "textbf", "textit", "mathrm", "mathbf", "mathit",
                                       "mathsf", "mathcal", "mathbb", "mathop", "operatorname", "boldsymbol", "bm"]
    private static let decorations = ["overbrace", "underbrace", "overline", "underline", "hat", "bar", "vec", "tilde"]

    private static let environments = Rx(#"\\(?:begin|end)\s*\{[^}]*\}"#)
    private static let sizing = Rx(#"\\(?:left|right|big|Big|bigg|Bigg|displaystyle|textstyle|scriptstyle|limits|nolimits|;|:|,|!|quad|qquad)\b|\\[,;:!]"#)
    private static let unknownCommand = Rx(#"\\([a-zA-Z]+)"#)
    private static let fraction = Rx(#"\\(?:d|t)?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}"#)
    private static let root = Rx(#"\\sqrt\s*\{([^{}]*)\}"#)
    private static let scriptBraced = Rx(#"([_^])\s*\{([^{}]*)\}"#)
    private static let scriptBare = Rx(#"([_^])\s*(\\?[A-Za-z0-9+\-=()]{1,2})"#)
    private static let colour = Rx(#"\\(?:color|textcolor)\s*\{[^}]*\}\s*\{([^{}]*)\}"#)

    /// `\frac{a}{b}` becomes `a/b`, with brackets only where they are needed to keep the meaning
    /// (`\frac{a+b}{c}` is `(a+b)/c`, but `\frac{\partial f}{\partial v}` is `∂f/∂v`, not `(∂f)/(∂v)`).
    private static func fractions(_ text: String) -> String {
        command(text, ["frac", "dfrac", "tfrac", "cfrac"], arity: 2) { _, arguments in
            "\(wrapIfCompound(readable(arguments[0])))/\(wrapIfCompound(readable(arguments[1])))"
        }
    }

    private static func wrapIfCompound(_ part: String) -> String {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        let needsBrackets = trimmed.contains(where: { "+-±".contains($0) })
            && !trimmed.hasPrefix("-")                     // a leading minus is a sign, not an operator
        return needsBrackets ? "(\(trimmed))" : trimmed
    }

    private static func roots(_ text: String) -> String {
        command(text, ["sqrt"], arity: 1) { _, arguments in
            let body = readable(arguments[0]).trimmingCharacters(in: .whitespaces)
            // Brackets only where the root covers more than one term: √2 and √dₖ, but √(a+b).
            return body.contains(where: { "+-± ".contains($0) }) ? "√(\(body))" : "√\(body)"
        }
    }

    private static func colourCommand(_ text: String) -> String {
        command(text, ["color", "textcolor"], arity: 2) { _, arguments in readable(arguments[1]) }
    }

    /// `\text{if }x` and friends: the braces carry the content, the command carries nothing.
    private static func braceCommand(_ text: String, names: [String]) -> String {
        command(text, names, arity: 1) { _, arguments in readable(arguments[0]) }
    }

    /// Sub- and superscripts become real Unicode where a character exists, and keep their marker where it does not,
    /// so `\theta_1` reads as `θ₁` while `x_{\max}` stays `x_max` rather than becoming an ambiguous `xmax`.
    private static func scripts(_ text: String) -> String {
        var out = balancedScripts(text)
        out = scriptBare.replaceMatches(in: out) { groups in
            convertScript(marker: groups[0], body: groups[1])
        }
        return out
    }

    /// `x^{2n}` and `\theta_{ij}`: the marker takes a balanced group, which `[^{}]*` cannot read.
    private static func balancedScripts(_ text: String) -> String {
        let characters = Array(text)
        var out = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character == "_" || character == "^", let found = group(in: characters, at: index + 1) else {
                out.append(character); index += 1; continue
            }
            out += convertScript(marker: String(character), body: readable(found.body))
            index = found.end
        }
        return out
    }

    private static func convertScript(marker: String, body: String) -> String {
        let table = marker == "_" ? subscripts : superscripts
        let resolved = symbols(body)                       // `\theta` inside a script becomes θ first
        var mapped = ""
        for character in resolved {
            guard let small = table[character] else { return "\(marker)\(resolved)" }
            mapped.append(small)
        }
        return mapped
    }

    private static func symbols(_ text: String) -> String {
        var out = text
        for (command, replacement) in symbolTable {
            guard out.contains(command) else { continue }
            out = out.replacingOccurrences(of: command, with: replacement)
        }
        return out
    }

    private static func collapse(_ text: String) -> String {
        var out = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // TeX writes `\partial f` with a space that a renderer closes up; left in, `∂ f/∂ v` reads as a list of
        // symbols rather than a derivative. The same goes for the other prefix operators.
        out = tightPrefix.replace(in: out, with: "$1$2")
        out = out.replacingOccurrences(of: " ( ", with: " (").replacingOccurrences(of: " ) ", with: ") ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A prefix operator binds to what follows it: `∂ f` is `∂f`, `√ 2` is `√2`.
    private static let tightPrefix = Rx(#"([∂∇√])\s+([A-Za-z0-9α-ωΑ-Ω(])"#)

    // MARK: Tables

    /// Longest first, so `\thetax` cannot be eaten by `\theta`'s prefix and `\subseteq` beats `\subset`.
    private static let symbolTable: [(String, String)] = {
        let pairs: [String: String] = [
            // Greek
            "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ", "\\epsilon": "ε", "\\varepsilon": "ε",
            "\\zeta": "ζ", "\\eta": "η", "\\theta": "θ", "\\vartheta": "ϑ", "\\iota": "ι", "\\kappa": "κ",
            "\\lambda": "λ", "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ", "\\pi": "π", "\\rho": "ρ", "\\sigma": "σ",
            "\\varsigma": "ς", "\\tau": "τ", "\\upsilon": "υ", "\\phi": "φ", "\\varphi": "φ", "\\chi": "χ",
            "\\psi": "ψ", "\\omega": "ω",
            "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ", "\\Xi": "Ξ", "\\Pi": "Π",
            "\\Sigma": "Σ", "\\Upsilon": "Υ", "\\Phi": "Φ", "\\Psi": "Ψ", "\\Omega": "Ω",
            // Calculus and operators
            "\\partial": "∂", "\\nabla": "∇", "\\infty": "∞", "\\sum": "∑", "\\prod": "∏", "\\int": "∫",
            "\\iint": "∬", "\\oint": "∮", "\\prime": "′", "\\circ": "∘", "\\cdot": "·",
            "\\cdots": "⋯", "\\dots": "…", "\\ldots": "…", "\\vdots": "⋮", "\\ddots": "⋱",
            "\\times": "×", "\\div": "÷", "\\pm": "±", "\\mp": "∓", "\\ast": "∗", "\\star": "⋆",
            // Relations
            "\\leq": "≤", "\\le": "≤", "\\geq": "≥", "\\ge": "≥", "\\neq": "≠", "\\ne": "≠",
            "\\approx": "≈", "\\sim": "∼", "\\simeq": "≃", "\\equiv": "≡", "\\propto": "∝",
            "\\ll": "≪", "\\gg": "≫",
            // Sets and logic
            "\\in": "∈", "\\notin": "∉", "\\subset": "⊂", "\\subseteq": "⊆", "\\supset": "⊃", "\\supseteq": "⊇",
            "\\cup": "∪", "\\cap": "∩", "\\emptyset": "∅", "\\varnothing": "∅", "\\forall": "∀", "\\exists": "∃",
            "\\neg": "¬", "\\land": "∧", "\\lor": "∨", "\\mid": "|",
            // Arrows
            "\\to": "→", "\\rightarrow": "→", "\\leftarrow": "←", "\\leftrightarrow": "↔",
            "\\Rightarrow": "⇒", "\\Leftarrow": "⇐", "\\Leftrightarrow": "⇔", "\\mapsto": "↦",
            // Blackboard letters, which `\mathbb{R}` would otherwise reduce to a bare R
            "\\mathbb{R}": "ℝ", "\\mathbb{N}": "ℕ", "\\mathbb{Z}": "ℤ", "\\mathbb{Q}": "ℚ",
            "\\mathbb{C}": "ℂ", "\\mathbb{E}": "𝔼", "\\mathbb{P}": "ℙ",
        ]
        return pairs.sorted { $0.key.count > $1.key.count }.map { ($0.key, $0.value) }
    }()

    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
        "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
    ]

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ",
        "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ",
        "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ", "′": "′",
    ]
}

/// A compiled regular expression with the two replacement shapes this file needs.
struct Rx {
    private let expression: NSRegularExpression?
    init(_ pattern: String) { expression = try? NSRegularExpression(pattern: pattern) }

    func replace(in text: String, with template: String) -> String {
        guard let expression else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                   withTemplate: template)
    }

    /// Replaces each match with the result of `body`, which receives the capture groups.
    func replaceMatches(in text: String, body: ([String]) -> String) -> String {
        guard let expression else { return text }
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }
        var out = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: out) else { continue }
            var groups: [String] = []
            for index in 1..<match.numberOfRanges {
                groups.append(Range(match.range(at: index), in: out).map { String(out[$0]) } ?? "")
            }
            out.replaceSubrange(range, with: body(groups))
        }
        return out
    }
}
