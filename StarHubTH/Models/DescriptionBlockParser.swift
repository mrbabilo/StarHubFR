import AppKit
import Foundation

/// A parsed segment of a Nexus mod description. `.text` holds Markdown (BBCode
/// converted), rendered downstream via SwiftUI `Text(.init(...))`.
enum DescriptionBlock: Hashable {
    case text(String)
    case heading(String, level: Int)      // 1 = le plus grand, 3 = le plus petit
    case list(items: [String], ordered: Bool)
    case code(String)
    case quote(String)
    case image(URL)
    case spoiler(title: String, content: String)
    case divider
    case centered([DescriptionBlock])      // conteneur récursif ([center])
}

/// Pure BBCode/HTML → blocks parser. Best-effort: never crashes on malformed
/// input (falls back to a single `.text`). Ported from upstream
/// NexusAPIService.parseBlocks (+ its list/HTML-linebreak fixes).
enum DescriptionBlockParser {
    /// BBCode tags we understand well enough to drop once their meaning has been
    /// carried over to Markdown (or deliberately discarded). Anything *not* on
    /// this list is left alone: real descriptions contain bracketed text that is
    /// not markup at all — SVE ships folders literally named `[CP] Stardew
    /// Valley Expanded`, and the previous catch-all strip silently turned its
    /// install instructions into wrong ones.
    /// `img` / `spoiler` / `hr` / `line` are absent on purpose: the block
    /// tokenizer still needs them.
    private static let knownInlineTags = [
        "b", "i", "u", "s", "size", "color", "left", "right", "justify",
        "font", "youtube", "media", "table", "tr",
        "td", "th", "indent", "acronym", "abbr", "highlight", "sub",
        "sup", "url", "email", "attachment", "nomedia", "smilie", "spoilertitle",
    ]

    /// `[size]` values at or above this render as a heading; anything below is
    /// body copy. Nexus authors size their *paragraphs* too — SVE uses `size=3`
    /// 187 times for body text against 16 `size=4` headings — so bolding every
    /// sized run turned whole pages bold and made real headings invisible.
    private static let headingSizeThreshold = 4

    static func parse(_ str: String) -> [DescriptionBlock] {
        let (withoutCode, codeBlocks) = extractCode(from: str)
        return tokenize(normalize(withoutCode), codeBlocks: codeBlocks)
    }

    /// Extrait les blocs `[code]…[/code]` **avant** toute conversion et les
    /// remplace par un marqueur `\u{0}C<i>\u{0}`. Le contenu est rendu à
    /// l'identique (inviolable) : un `[b]` ou un `**` dans un exemple de config
    /// reste tel quel, espaces et sauts de ligne compris. `tokenize` traduira le
    /// marqueur en `.code`.
    private static func extractCode(from str: String) -> (String, [String]) {
        guard let regex = try? NSRegularExpression(
            pattern: "(?is)\\[code\\](.*?)\\[/code\\]",
            options: .caseInsensitive) else { return (str, []) }
        let ns = str as NSString
        var blocks: [String] = []
        var out = ""
        var last = 0
        for m in regex.matches(in: str, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += "\u{0}C\(blocks.count)\u{0}"
            blocks.append(ns.substring(with: m.range(at: 1)))
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return (out, blocks)
    }

    /// HTML + BBCode → Markdown, without touching block-level tags.
    private static func normalize(_ str: String) -> String {
        var formatted = str

        // 1. HTML entities
        formatted = formatted.replacingOccurrences(of: "&nbsp;", with: " ")
                             .replacingOccurrences(of: "&amp;", with: "&")
                             .replacingOccurrences(of: "&lt;", with: "<")
                             .replacingOccurrences(of: "&gt;", with: ">")
                             .replacingOccurrences(of: "&quot;", with: "\"")
        // 1b. Zero-width junk. Nexus' editor sprinkles BOMs (U+FEFF) through
        // pasted text; they are invisible but not whitespace, so `\s*` never
        // matched them and a "blank" label like `[url=X]\u{FEFF}[/url]` survived
        // every empty-pair guard, reaching the screen as a bare `](https://…)`.
        // U+200D (ZWJ) is deliberately kept: it joins emoji sequences.
        formatted = formatted.replacingOccurrences(of: "\u{FEFF}", with: "")
                             .replacingOccurrences(of: "\u{200B}", with: "")
                             .replacingOccurrences(of: "\u{200C}", with: "")
        // 2. <br> and block tags → newlines
        formatted = formatted.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "(?i)</?(?:p|div|h[1-6]|li|tr|blockquote)\\b[^>]*>", with: "\n", options: .regularExpression)
        // 3. strip other HTML
        formatted = formatted.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // 3b. Drop tag pairs whose content is empty *before* converting, so they
        // never become delimiters with nothing between them. `[b][/b]` used to
        // reach Markdown as `****`, and `[url=X][/url]` as `[](X)` — which the
        // renderer shows as a literal `](https://…)`. SVE has both.
        for tag in knownInlineTags {
            formatted = formatted.replacingOccurrences(
                of: "(?is)\\[\(tag)(?:=[^\\]]*)?\\]\\s*\\[/\(tag)\\]",
                with: "", options: .regularExpression)
        }

        // 4. BBCode → Markdown
        formatted = formatted.replacingOccurrences(of: "(?s)\\[b\\](\\s*)(.*?)(\\s*)\\[/b\\]", with: "$1**$2**$3", options: [.regularExpression, .caseInsensitive])
        formatted = formatted.replacingOccurrences(of: "(?s)\\[i\\](\\s*)(.*?)(\\s*)\\[/i\\]", with: "$1*$2*$3", options: [.regularExpression, .caseInsensitive])
        formatted = formatted.replacingOccurrences(of: "(?s)\\[s\\](\\s*)(.*?)(\\s*)\\[/s\\]", with: "$1~~$2~~$3", options: [.regularExpression, .caseInsensitive])
        // [u]X[/u] → vrai souligné via attribut Markdown personnalisé (était
        // converti en *italique*, ce n'est pas un souligné).
        formatted = formatted.replacingOccurrences(of: "(?s)\\[u\\]\\s*(.*?)\\s*\\[/u\\]", with: "^[$1](shunderline: 'true')", options: [.regularExpression, .caseInsensitive])
        formatted = convertColors(in: formatted)
        formatted = convertSizes(in: formatted)
        formatted = convertHeadings(in: formatted)
        // `[list]`, `[*]` et `[li]` sont gérés au niveau bloc par `tokenize`
        // (vraie liste, pas un .text à tirets) : on ne les convertit plus ici.
        // A link whose whole label is an image (`[url=X][img]Y[/img][/url]`, how
        // Nexus authors make a banner clickable) can't survive as Markdown: the
        // tokenizer lifts the image into its own block and the link's brackets
        // are left behind as a bare `](https://…)`. Unwrap to the image — a
        // `.image` block carries no destination, and showing the picture beats
        // showing the syntax.
        formatted = formatted.replacingOccurrences(
            of: "(?is)\\[url(?:=[^\\]]*)?\\]\\s*(\\[img[^\\]]*\\].*?\\[/img\\])\\s*\\[/url\\]",
            with: "$1", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "(?s)\\[url=(.*?)\\]\\s*(.*?)\\s*\\[/url\\]", with: "[$2]($1)", options: [.regularExpression, .caseInsensitive])
        formatted = formatted.replacingOccurrences(of: "(?s)\\[url\\]\\s*(.*?)\\s*\\[/url\\]", with: "[$1]($1)", options: [.regularExpression, .caseInsensitive])
        // NB: `[hr]` / `[line]` are intentionally NOT converted here — they are
        // tokenized into a `.divider` block below (a real rule renders, whereas
        // a Markdown `---` would show literally in inline-only rendering).
        formatted = formatted.replacingOccurrences(of: "(?i)\\[/\\*\\]", with: "", options: .regularExpression)
        // 5. Strip EVERY remaining BBCode-style tag (a whitelist — upstream's
        // approach — leaves any unlisted or malformed tag, e.g. `[/]`, `[/*]`,
        // `[quote=x]`, or a stray unbalanced `[b]`, rendered raw on screen).
        // Excludes `[img …]` / `[spoiler …]` (the tokenizer below needs them),
        // and won't touch a Markdown link `[text](url)` produced just above
        // (the `(?!\()` guard), so only genuine leftover tags are removed.
        // The negative lookahead sits *before* the optional slash so it rejects
        // both `[img …]` and `[/img]` (and spoiler) — otherwise `/?` backtracks
        // and the body swallows `/img`, stripping the closing tag and breaking
        // image tokenization below.
        let tagAlternation = knownInlineTags.joined(separator: "|")
        formatted = formatted.replacingOccurrences(
            of: "(?i)\\[/?(?:\(tagAlternation))(?:=[^\\]]*)?\\](?!\\()",
            with: "", options: .regularExpression)
        // Bare generic close tag (`[/]`), which no whitelist entry covers.
        formatted = formatted.replacingOccurrences(of: "\\[/\\]", with: "", options: .regularExpression)

        // Nesting two emphasising tags (`[size=4][b]Title[/b][/size]`) yields
        // `****Title****`. Collapse the doubled delimiters instead of deleting
        // them: the old "remove every ****" rule stripped the emphasis whole,
        // so headings came out as plain text — and, when only one side got
        // eaten, left a stray `**` on screen.
        formatted = formatted.replacingOccurrences(of: "\\*\\*\\*\\*(?=\\S)", with: "**", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "(?<=\\S)\\*\\*\\*\\*", with: "**", options: .regularExpression)

        // Unwrap emphasis whose content is only punctuation/whitespace (e.g.
        // `[b]:[/b]` → `**:**`). Markdown can't render `**` flanked by a word on
        // one side and punctuation on the other (CommonMark flanking rules), so
        // it would show the literal `**`; the bold adds nothing here anyway.
        formatted = unwrapPunctuationOnlyEmphasis(formatted, delimiter: "**")
        formatted = unwrapPunctuationOnlyEmphasis(formatted, delimiter: "~~")
        // Drop empty emphasis (`****`, `~~~~`) left by an empty tag pair such as
        // `[b][/b]`, which would otherwise render as literal delimiters.
        formatted = formatted.replacingOccurrences(of: "\\*\\*\\*\\*", with: "", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "~~~~", with: "", options: .regularExpression)
        // Collapse runs of blank lines (HTML block tags each became a newline,
        // stacking up into large vertical gaps) down to a single blank line.
        formatted = formatted.replacingOccurrences(of: "(?:[ \\t]*\\r?\\n[ \\t]*){2,}", with: "\n\n", options: .regularExpression)

        // Normalize the self-closing `[img=URL]` form to `[img]URL[/img]` so the
        // tokenizer picks it up too. Requires `=` right after `img` (optional
        // spaces), so it never mangles the attributed `[img width=550]…` form.
        formatted = formatted.replacingOccurrences(of: "(?i)\\[img\\s*=\\s*([^\\]]+)\\]", with: "[img]$1[/img]", options: .regularExpression)

        return formatted
    }

    /// `[size=N]body[/size]` → soit un marqueur de titre (promotion en bloc,
    /// résolu par `tokenize`), soit du gras inline (N≥4 mais contenu trop long),
    /// soit le corps nu (N<4). Garde-fou : on ne promeut en titre que si le
    /// contenu tient sur une seule ligne et fait ≤ 80 caractères — un `[size=4]`
    /// enveloppant un paragraphe entier ne doit pas devenir un titre géant.
    /// Une valeur non numérique est traitée comme corps (body copy).
    private static func convertSizes(in str: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(?s)\\[size=([^\\]]+)\\]\\s*(.*?)\\s*\\[/size\\]",
            options: .caseInsensitive) else { return str }
        let ns = str as NSString
        var out = ""
        var last = 0
        for m in regex.matches(in: str, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let rawValue = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let body = ns.substring(with: m.range(at: 2))
            let value = Int(rawValue.prefix(while: { $0.isNumber })) ?? 0
            out += emitSize(value: value, body: body)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Mappe une taille à un marqueur de titre `\u{0}H<n>\u{0}body\u{0}/H\u{0}`
    /// (promotion), à du gras inline, ou au corps nu. Le marqueur ne contient
    /// ni `[` ni `*`, donc aucune étape ultérieure de `normalize` ne le corrompt.
    private static func emitSize(value: Int, body: String) -> String {
        guard value >= headingSizeThreshold else { return body }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("\n") && trimmed.count <= 80 {
            return "\u{0}H\(headingLevel(forSize: value))\u{0}\(body)\u{0}/H\u{0}"
        }
        return "**\(body)**"
    }

    /// `[heading]X[/heading]` → marqueur de titre (niveau 2 par défaut ;
    /// `[heading=N]` suit l'échelle `[size]`). Même garde-fou que les tailles.
    private static func convertHeadings(in str: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(?s)\\[heading(?:=([^\\]]+))?\\]\\s*(.*?)\\s*\\[/heading\\]",
            options: .caseInsensitive) else { return str }
        let ns = str as NSString
        var out = ""
        var last = 0
        for m in regex.matches(in: str, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let body = ns.substring(with: m.range(at: 2))
            let value: Int
            if m.range(at: 1).location != NSNotFound {
                let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                value = Int(raw.prefix(while: { $0.isNumber })) ?? 0
            } else {
                value = 0
            }
            let level = value > 0 ? headingLevel(forSize: value) : 2
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.contains("\n") && trimmed.count <= 80 {
                out += "\u{0}H\(level)\u{0}\(body)\u{0}/H\u{0}"
            } else {
                out += "**\(body)**"
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Échelle des titres : 4→3, 5→2, 6-7→1 (1 = le plus grand).
    private static func headingLevel(forSize size: Int) -> Int {
        switch size {
        case 6...:  return 1
        case 5:     return 2
        default:    return 3   // size 4
        }
    }

    /// `[color=V]body[/color]` → `^[body](shcolor: 'hex')` (attribut Markdown
    /// personnalisé). V est un `#hex` (passé tel quel) ou un nom résolu par la
    /// table `ContrastChecker.color(named:)` ; un nom inconnu → corps nu, sans
    /// attribut couleur. Les paires non appariées restent nettoyées par le strip
    /// final (`color` et `u` restent dans `knownInlineTags`).
    private static func convertColors(in str: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(?is)\\[color=([^\\]]+)\\]\\s*(.*?)\\s*\\[/color\\]",
            options: .caseInsensitive) else { return str }
        let ns = str as NSString
        var out = ""
        var last = 0
        for m in regex.matches(in: str, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let value = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let body = ns.substring(with: m.range(at: 2))
            if let hex = resolveColorHex(value) {
                out += "^[\(body)](shcolor: '\(hex)')"
            } else {
                out += body
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Résout une valeur `[color=V]` en hex `#rrggbb` : `#hex` passé tel quel,
    /// ou un nom via `ContrastChecker.color(named:)` ; nil si nom inconnu.
    private static func resolveColorHex(_ value: String) -> String? {
        if value.hasPrefix("#") { return value }
        guard let c = ContrastChecker.color(named: value)?.usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Drops emphasis whose content is only punctuation or whitespace — `[b]:[/b]`
    /// becomes `**:**`, which CommonMark's flanking rules can't render, so the
    /// delimiters would show literally while adding nothing.
    ///
    /// Delimiters are paired in order (1st with 2nd, 3rd with 4th…) rather than
    /// matched by regex. A regex scanning left to right happily reads a *closing*
    /// delimiter as an opening one: in `**Follow me on** [**Twitter**](url)` it
    /// paired the closer of "Follow me on" with the opener of "Twitter", saw only
    /// `" ["` between them, and unwrapped both — stranding a `**` inside the link
    /// label (`[Twitter**](url)`), exactly as seen on SVE's page.
    private static func unwrapPunctuationOnlyEmphasis(_ str: String, delimiter: String) -> String {
        let parts = str.components(separatedBy: delimiter)
        guard parts.count > 2 else { return str }

        var out = parts[0]
        var index = 1
        while index < parts.count {
            // `parts[index]` is the emphasised body; `parts[index + 1]`, when it
            // exists, is the ordinary text that follows the closing delimiter.
            let body = parts[index]
            guard index + 1 < parts.count else {
                out += delimiter + body           // unpaired trailing delimiter
                break
            }
            let isPunctuationOnly = !body.isEmpty && body.allSatisfy {
                $0.isPunctuation || $0.isWhitespace || $0.isSymbol
            }
            out += isPunctuationOnly ? body : delimiter + body + delimiter
            out += parts[index + 1]
            index += 2
        }
        return out
    }

    // MARK: - Block tokenizer

    /// Splits normalized text into blocks, honouring **nesting**.
    ///
    /// The previous single regex paired `[spoiler]` with the *first* `[/spoiler]`
    /// it found. Real descriptions nest them — SVE wraps a per-map gallery in an
    /// outer spoiler — so the outer content was cut short, its closing tag was
    /// left on screen as literal text, and the images sitting in the inner
    /// spoilers never reached `SpoilerView` (which re-parses its content and
    /// would have rendered them).
    private static func tokenize(_ text: String, codeBlocks: [String] = []) -> [DescriptionBlock] {
        // Marqueurs internes transportés depuis `normalize` :
        //  • `\u{0}C<i>\u{0}`                    → bloc `.code` (contenu verbatim)
        //  • `\u{0}H<n>\u{0}body\u{0}/H\u{0}`    → titre `.heading` de niveau n
        // Balises bloc `[...]` : img, spoiler, hr/line, quote, center, list.
        let nul = "\u{0}"
        let pattern = "(?i)\\[(/?)(img|spoiler|hr|line|quote|center|list)([^\\]]*)\\]"
            + "|" + nul + "C(\\d+)" + nul
            + "|" + nul + "H([1-3])" + nul + "([\\s\\S]*?)" + nul + "/H" + nul
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            let t = balancedText(text)
            return t.isEmpty ? [] : [.text(t)]
        }
        let ns = text as NSString
        let tokens = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        var blocks: [DescriptionBlock] = []
        var cursor = 0
        var i = 0

        func flushText(upTo location: Int) {
            guard location > cursor else { return }
            var s = ns.substring(with: NSRange(location: cursor, length: location - cursor))
            // Un marqueur de liste (`[*]`, `[li]`) échappé de son `[list]` est du
            // bruit : on le retire du texte brut plutôt que de l'afficher.
            s = s.replacingOccurrences(of: "(?i)\\[/?\\*\\]|\\[/?li\\]", with: "", options: .regularExpression)
            let t = balancedText(s)
            if !t.isEmpty { blocks.append(.text(t)) }
        }

        while i < tokens.count {
            let tok = tokens[i]
            let tokEnd = tok.range.location + tok.range.length

            // Titre (groupes 5, 6).
            if tok.range(at: 5).location != NSNotFound {
                flushText(upTo: tok.range.location)
                let level = Int(ns.substring(with: tok.range(at: 5))) ?? 2
                let body = balancedText(flattenInline(ns.substring(with: tok.range(at: 6)),
                                                      codeBlocks: codeBlocks))
                if !body.isEmpty { blocks.append(.heading(body, level: level)) }
                cursor = tokEnd
                i += 1
                continue
            }
            // Code (groupe 4).
            if tok.range(at: 4).location != NSNotFound {
                flushText(upTo: tok.range.location)
                let idx = Int(ns.substring(with: tok.range(at: 4))) ?? 0
                if idx < codeBlocks.count {
                    let content = codeBlocks[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty { blocks.append(.code(content)) }
                }
                cursor = tokEnd
                i += 1
                continue
            }
            // Balise `[...]` (groupes 1, 2, 3).
            let isClosing = ns.substring(with: tok.range(at: 1)) == "/"
            let name = ns.substring(with: tok.range(at: 2)).lowercased()
            let attribute = ns.substring(with: tok.range(at: 3))

            if name == "hr" || name == "line" {
                flushText(upTo: tok.range.location)
                blocks.append(.divider)
                cursor = tokEnd
                i += 1
                continue
            }
            // Fermant orphelin : reliquat de balisage, on l'ignore.
            guard !isClosing else {
                flushText(upTo: tok.range.location)
                cursor = tokEnd
                i += 1
                continue
            }
            // Marche avant jusqu'au fermant apparié (imbriquable), en comptant
            // les ouvrants/fermants de même nom. Marqueurs et autres balises
            // n'impactent pas la profondeur de `name`.
            var depth = 1
            var j = i + 1
            var closer: NSTextCheckingResult?
            while j < tokens.count {
                let c = tokens[j]
                if c.range(at: 2).location != NSNotFound,
                   ns.substring(with: c.range(at: 2)).lowercased() == name {
                    depth += ns.substring(with: c.range(at: 1)) == "/" ? -1 : 1
                    if depth == 0 { closer = c; break }
                }
                j += 1
            }
            guard let closingTag = closer else {
                // Ouvrant non refermé : balisage parasite, on passe.
                flushText(upTo: tok.range.location)
                cursor = tokEnd
                i += 1
                continue
            }

            flushText(upTo: tok.range.location)
            let inner = ns.substring(with: NSRange(location: tokEnd,
                                                    length: closingTag.range.location - tokEnd))
            emitBlock(name: name, attribute: attribute, inner: inner,
                      codeBlocks: codeBlocks, into: &blocks)
            cursor = closingTag.range.location + closingTag.range.length
            // Reprend après le fermant apparié — tout l'intérieur a été consommé.
            i = tokens.firstIndex(where: { $0.range.location >= cursor }) ?? tokens.count
        }

        flushText(upTo: ns.length)
        return blocks
    }

    /// Émet le bloc correspondant à une balise appariée, selon son nom.
    private static func emitBlock(name: String, attribute: String, inner: String,
                                  codeBlocks: [String], into blocks: inout [DescriptionBlock]) {
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "img":
            if let url = URL(string: trimmed) { blocks.append(.image(url)) }
        case "spoiler":
            var title = "Spoiler"
            if attribute.hasPrefix("=") {
                let raw = String(attribute.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty { title = raw }
            }
            // Le contenu garde son balisage : `SpoilerView` le reparse, donc les
            // spoilers imbriqués et leurs images rendent à l'ouverture.
            blocks.append(.spoiler(title: title, content: trimmed))
        case "quote":
            let q = balancedText(flattenInline(trimmed, codeBlocks: codeBlocks))
            if !q.isEmpty { blocks.append(.quote(q)) }
        case "center":
            if !trimmed.isEmpty {
                blocks.append(.centered(tokenize(inner, codeBlocks: codeBlocks)))
            }
        case "list":
            let ordered = attribute.hasPrefix("=")
            let items = splitListItems(inner, codeBlocks: codeBlocks)
            if !items.isEmpty { blocks.append(.list(items: items, ordered: ordered)) }
        default:
            break
        }
    }

    /// Découpe le contenu d'une `[list]` sur les marqueurs d'item `[*]` / `[li]`.
    /// Le texte éventuel avant le premier marqueur (préambule) est ignoré.
    private static func splitListItems(_ inner: String, codeBlocks: [String]) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\[\\*\\]|\\[li\\]") else { return [] }
        let ns = inner as NSString
        let markers = regex.matches(in: inner, range: NSRange(location: 0, length: ns.length))
        guard !markers.isEmpty else {
            let t = balancedText(flattenInline(inner, codeBlocks: codeBlocks))
            return t.isEmpty ? [] : [t]
        }
        var items: [String] = []
        for (k, marker) in markers.enumerated() {
            let start = marker.range.location + marker.range.length
            let end = k + 1 < markers.count ? markers[k + 1].range.location : ns.length
            let raw = ns.substring(with: NSRange(location: start, length: end - start))
            let t = balancedText(flattenInline(raw, codeBlocks: codeBlocks))
            if !t.isEmpty { items.append(t) }
        }
        return items
    }

    /// Aplatie tout reliquat de balisage bloc qui se retrouve dans un bloc à
    /// valeur `String` (item de liste, citation, corps de titre) — contextes qui
    /// ne portent que de l'inline. Les marqueurs de titre y sont démutés en gras,
    /// les marqueurs de code remplacés par leur contenu verbatim, et les balises
    /// bloc résiduelles (`[list]`, `[center]`, `[spoiler]`, `[size]`, `[heading]`,
    /// `[*]`) supprimées (le texte reste). Sans cela, un titre ou un bloc imbriqué
    /// dans un item de liste fuierait en balisage littéral à l'écran.
    private static func flattenInline(_ s: String, codeBlocks: [String]) -> String {
        var out = s
        out = out.replacingOccurrences(of: "\u{0}H[1-3]\u{0}", with: "**", options: .regularExpression)
        out = out.replacingOccurrences(of: "\u{0}/H\u{0}", with: "**", options: .regularExpression)
        if let regex = try? NSRegularExpression(pattern: "\u{0}C(\\d+)\u{0}") {
            let ns = out as NSString
            var rebuilt = ""
            var last = 0
            for m in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                rebuilt += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let idx = Int(ns.substring(with: m.range(at: 1))) ?? -1
                rebuilt += (0..<codeBlocks.count).contains(idx) ? codeBlocks[idx] : ""
                last = m.range.location + m.range.length
            }
            rebuilt += ns.substring(from: last)
            out = rebuilt
        }
        out = out.replacingOccurrences(
            of: "(?i)\\[/?(?:list|center|spoiler|size|heading|code)(?:=[^\\]]*)?\\]",
            with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "(?i)\\[\\*\\]", with: "", options: .regularExpression)
        return out
    }

    /// Trims, then drops emphasis delimiters left unbalanced when a block-level
    /// token (an image or spoiler) is extracted from *inside* inline formatting.
    /// `[b][img]…[/img] caption[/b]` becomes `**[img]…[/img] caption**`, and
    /// splitting the image out would otherwise strand a lone `**` on each side.
    /// A block with an odd number of a given delimiter can't render as valid
    /// Markdown anyway, so removing them yields clean text rather than literal
    /// `**` on screen.
    private static func balancedText(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for delim in ["**", "~~"] {
            let count = s.components(separatedBy: delim).count - 1
            if count % 2 != 0 { s = s.replacingOccurrences(of: delim, with: "") }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
