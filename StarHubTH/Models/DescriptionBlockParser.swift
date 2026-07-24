import Foundation

/// A parsed segment of a Nexus mod description. `.text` holds Markdown (BBCode
/// converted), rendered downstream via SwiftUI `Text(.init(...))`.
enum DescriptionBlock: Hashable {
    case text(String)
    case image(URL)
    case spoiler(title: String, content: String)
}

/// Pure BBCode/HTML → blocks parser. Best-effort: never crashes on malformed
/// input (falls back to a single `.text`). Ported from upstream
/// NexusAPIService.parseBlocks (+ its list/HTML-linebreak fixes).
enum DescriptionBlockParser {
    static func parse(_ str: String) -> [DescriptionBlock] {
        var formatted = str

        // 1. HTML entities
        formatted = formatted.replacingOccurrences(of: "&nbsp;", with: " ")
                             .replacingOccurrences(of: "&amp;", with: "&")
                             .replacingOccurrences(of: "&lt;", with: "<")
                             .replacingOccurrences(of: "&gt;", with: ">")
                             .replacingOccurrences(of: "&quot;", with: "\"")
        // 2. <br> and block tags → newlines
        formatted = formatted.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "(?i)</?(?:p|div|h[1-6]|li|tr|blockquote)\\b[^>]*>", with: "\n", options: .regularExpression)
        // 3. strip other HTML
        formatted = formatted.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // 4. BBCode → Markdown
        formatted = formatted.replacingOccurrences(of: "(?s)\\[b\\]\\s*(.*?)\\s*\\[/b\\]", with: "**$1**", options: [.regularExpression, .caseInsensitive])
        formatted = formatted.replacingOccurrences(of: "(?s)\\[i\\]\\s*(.*?)\\s*\\[/i\\]", with: "*$1*", options: [.regularExpression, .caseInsensitive])
        formatted = formatted.replacingOccurrences(of: "(?s)\\[s\\]\\s*(.*?)\\s*\\[/s\\]", with: "~~$1~~", options: [.regularExpression, .caseInsensitive])
        formatted = formatted.replacingOccurrences(of: "(?s)\\[u\\]\\s*(.*?)\\s*\\[/u\\]", with: "*$1*", options: [.regularExpression, .caseInsensitive])
        formatted = formatted.replacingOccurrences(of: "(?s)\\[size=[^\\]]+\\]\\s*(.*?)\\s*\\[/size\\]", with: "**$1**", options: [.regularExpression, .caseInsensitive])
        formatted = formatted.replacingOccurrences(of: "(?s)\\[heading[=\\d]*\\]\\s*(.*?)\\s*\\[/heading\\]", with: "**$1**", options: [.regularExpression, .caseInsensitive])
        formatted = formatted.replacingOccurrences(of: "(?i)\\[/?list(?:=[^\\]]+)?\\]", with: "\n", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "(?i)\\[\\*\\]", with: "\n- ", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "(?i)\\[li\\]", with: "\n- ", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "(?i)\\[/li\\]", with: "", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "(?s)\\[url=(.*?)\\]\\s*(.*?)\\s*\\[/url\\]", with: "[$2]($1)", options: [.regularExpression, .caseInsensitive])
        formatted = formatted.replacingOccurrences(of: "(?s)\\[url\\]\\s*(.*?)\\s*\\[/url\\]", with: "[$1]($1)", options: [.regularExpression, .caseInsensitive])
        formatted = formatted.replacingOccurrences(of: "(?i)\\[/?(?:line|hr)\\]", with: "\n---\n", options: .regularExpression)
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
        formatted = formatted.replacingOccurrences(
            of: "(?i)\\[(?!/?(?:img[^a-zA-Z]|spoiler[^a-zA-Z]))/?[^\\[\\]]*\\](?!\\()",
            with: "", options: .regularExpression)

        // Unwrap emphasis whose content is only punctuation/whitespace (e.g.
        // `[b]:[/b]` → `**:**`). Markdown can't render `**` flanked by a word on
        // one side and punctuation on the other (CommonMark flanking rules), so
        // it would show the literal `**`; the bold adds nothing here anyway.
        formatted = formatted.replacingOccurrences(of: "\\*\\*([\\p{P}\\s]+?)\\*\\*", with: "$1", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: "~~([\\p{P}\\s]+?)~~", with: "$1", options: .regularExpression)
        // Collapse runs of blank lines (HTML block tags each became a newline,
        // stacking up into large vertical gaps) down to a single blank line.
        formatted = formatted.replacingOccurrences(of: "(?:[ \\t]*\\r?\\n[ \\t]*){2,}", with: "\n\n", options: .regularExpression)

        // Normalize the self-closing `[img=URL]` form to `[img]URL[/img]` so the
        // tokenizer picks it up too. Requires `=` right after `img` (optional
        // spaces), so it never mangles the attributed `[img width=550]…` form.
        formatted = formatted.replacingOccurrences(of: "(?i)\\[img\\s*=\\s*([^\\]]+)\\]", with: "[img]$1[/img]", options: .regularExpression)

        // 6. tokenize by [img] / [spoiler]. The [img] open tag may carry
        // attributes (e.g. `[img width=550]url[/img]`), so match `[img …]`, not
        // just a bare `[img]`.
        var blocks: [DescriptionBlock] = []
        let combinedPattern = "(?s)(\\[img[^\\]]*\\](.*?)\\[/img\\]|\\[spoiler(?:=(.*?))?\\](.*?)\\[/spoiler\\])"
        guard let regex = try? NSRegularExpression(pattern: combinedPattern, options: .caseInsensitive) else {
            let t = balancedText(formatted)
            return t.isEmpty ? [] : [.text(t)]
        }
        let nsString = formatted as NSString
        let matches = regex.matches(in: formatted, range: NSRange(location: 0, length: nsString.length))
        var lastEnd = 0
        for match in matches {
            let textStr = balancedText(nsString.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd)))
            if !textStr.isEmpty { blocks.append(.text(textStr)) }
            let fullMatch = nsString.substring(with: match.range)
            if fullMatch.lowercased().hasPrefix("[img") {
                let r = match.range(at: 2)
                if r.location != NSNotFound {
                    let s = nsString.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let url = URL(string: s) { blocks.append(.image(url)) }
                }
            } else if fullMatch.lowercased().hasPrefix("[spoiler") {
                let titleR = match.range(at: 3), contentR = match.range(at: 4)
                var title = "Spoiler"
                if titleR.location != NSNotFound {
                    let e = nsString.substring(with: titleR).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !e.isEmpty { title = e }
                }
                let content = contentR.location != NSNotFound
                    ? nsString.substring(with: contentR).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                blocks.append(.spoiler(title: title, content: content))
            }
            lastEnd = match.range.location + match.range.length
        }
        let finalText = balancedText(nsString.substring(from: lastEnd))
        if !finalText.isEmpty { blocks.append(.text(finalText)) }
        return blocks
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
