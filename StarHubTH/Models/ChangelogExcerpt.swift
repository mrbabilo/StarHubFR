import Foundation

/// Ce que la vue « Changelog » de l'app affiche : les **deux** dernières
/// sections de version du `CHANGELOG.md` embarqué, sans le préambule.
///
/// Une section `## [Unreleased]` compte si elle a du contenu — un build de
/// développement tiré de `main` porte là ses changements les plus récents ;
/// vide (juste après une release), elle est sautée et les deux versions
/// publiées précédentes s'affichent.
public enum ChangelogExcerpt {
    public static func latest(_ markdown: String, count: Int = 2) -> String {
        var sections: [[Substring]] = []
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                sections.append([line])
            } else if !sections.isEmpty {
                sections[sections.count - 1].append(line)
            }
        }
        let kept = sections
            .filter { section in
                section.dropFirst().contains { $0.contains { !$0.isWhitespace } }
            }
            .prefix(count)
        return kept
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n")
    }

    /// Les mêmes sections, structurées pour une carte par version : titre,
    /// date, puis les groupes Keep a Changelog et leurs entrées. Une entrée
    /// commence à `- ` ; les lignes qui suivent sans tiret la prolongent.
    public static func releases(_ markdown: String, count: Int = 2) -> [Release] {
        latest(markdown, count: count)
            .components(separatedBy: "\n## ")
            .compactMap { chunk -> Release? in
                var lines = chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                guard let first = lines.first else { return nil }
                lines.removeFirst()
                let heading = first.hasPrefix("## ") ? String(first.dropFirst(3)) : first
                return Release(heading: heading, body: lines)
            }
    }

    public struct Release: Equatable {
        /// « 1.53.0 », ou « Unreleased ».
        public let version: String
        public let date: String?
        public let groups: [Group]

        public var isUnreleased: Bool { version.caseInsensitiveCompare("Unreleased") == .orderedSame }

        init(heading: String, body: [String]) {
            // « [1.53.0] - 2026-10-02 » → version et date.
            let parts = heading.components(separatedBy: " - ")
            version = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            date = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
            var groups: [Group] = []
            var kind = Group.Kind.other
            var entries: [String] = []
            func flush() {
                if !entries.isEmpty { groups.append(Group(kind: kind, entries: entries)) }
                entries = []
            }
            for line in body {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("### ") {
                    flush()
                    kind = Group.Kind(heading: String(trimmed.dropFirst(4)))
                } else if trimmed.hasPrefix("- ") {
                    entries.append(String(trimmed.dropFirst(2)))
                } else if !trimmed.isEmpty, !entries.isEmpty {
                    entries[entries.count - 1] += " " + trimmed
                }
            }
            flush()
            self.groups = groups
        }
    }

    public struct Group: Equatable {
        public enum Kind: Equatable {
            case added, changed, fixed, removed, other
            init(heading: String) {
                switch heading.lowercased() {
                case "added": self = .added
                case "changed": self = .changed
                case "fixed": self = .fixed
                case "removed": self = .removed
                default: self = .other
                }
            }
        }
        public let kind: Kind
        public let entries: [String]
    }
}
