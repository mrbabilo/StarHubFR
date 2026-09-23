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
}
