import Foundation

/// La mécanique de la passe de couverture française : **qui** mesurer, et
/// **comment** faire entrer un lot de mesures dans l'état publié.
///
/// Ce ne sont pas les lectures de fichiers — celles-là vivent dans
/// `TranslationCoverage`, déjà en Core et testé. Ce sont les deux décisions qui
/// les encadrent, et qui n'avaient aucun test alors qu'elles commandent ce que
/// la pastille de la liste montre : la passe complète coûte ~13 s de lecture
/// disque sur le parc de référence (424 mods, 159 503 clés), et `mods` est
/// republié à chaque mise en pause, chaque rafraîchissement, chaque activation
/// de profil. Se tromper de lot, c'est refaire ces 13 s pour rien — ou ne
/// jamais mesurer un mod.
///
/// Extrait le 2026-09-10 (point 3 du §5 de `docs/REFACTORING.md`). Le
/// `Task.detached` et les lectures restent au ViewModel : ce qui est ici est
/// **pur**, et se teste sans toucher au disque.
enum FrenchCoveragePass {

    /// Un mod à mesurer.
    ///
    /// Les deux noms sont là et doivent y rester. Le dossier à ouvrir est le
    /// **physique** — un mod en pause vit dans `.X` — tandis que la clé de
    /// l'état publié est le nom **logique**, celui qu'emploient tous les
    /// magasins persistés. Les confondre ferait soit chercher dans le vide,
    /// soit reperdre la mesure à chaque bascule.
    struct Target: Equatable {
        /// La clé de l'état publié (`ModItem.folderName`).
        let key: String
        /// Le nom du dossier sur le disque (`ModItem.physicalFolderName`).
        let physicalFolder: String
    }

    /// Les mods qu'il reste à mesurer, dans l'ordre de la liste.
    ///
    /// Deux règles, et elles ne se recouvrent pas :
    ///
    /// - **Incrémental** : un mod dont la couverture est déjà connue n'est pas
    ///   remesuré. Mettre un mod en pause déplace son dossier sans toucher à
    ///   ses fichiers de traduction — le résultat reste valable.
    ///   `invalidateFrenchCoverage(for:)` sert aux cas où le contenu change.
    /// - **Français seulement** : seuls les mods que le scan dit traduits en
    ///   français sont mesurés. C'est ce qui rend la passe abordable, et c'est
    ///   pourquoi cette détection devait être juste d'abord.
    ///
    /// ⚠️ Cette seconde règle **diffère volontairement** de celle des profils
    /// (`ProfileCoveragePass`, qui prend aussi les mods à `default.json` sans
    /// français). Les unifier ferait surgir une pastille « 0 % » sur les mods
    /// non traduits de la liste — voir la documentation de
    /// `profileTranslationSummaries`.
    ///
    /// - Parameter known: les dossiers déjà mesurés, par nom **logique**.
    static func targets(in mods: [ModItem], known: Set<String>) -> [Target] {
        mods.filter { !known.contains($0.folderName) && $0.languages.contains("fr") }
            .map { Target(key: $0.folderName, physicalFolder: $0.physicalFolderName) }
    }

    /// Le nombre de mesures accumulées avant publication.
    ///
    /// Publier par paquets : un envoi par mod ferait redessiner la liste des
    /// centaines de fois pour rien.
    static let batchSize = 25

    /// L'état que la passe alimente : la couverture connue, et les mods dont
    /// l'anglais est plus récent que le français.
    struct State: Equatable {
        var coverage: [String: TranslationCoverage.Coverage]
        var stale: Set<String>

        init(coverage: [String: TranslationCoverage.Coverage] = [:],
             stale: Set<String> = []) {
            self.coverage = coverage
            self.stale = stale
        }
    }

    /// Fait entrer un lot de mesures dans l'état.
    ///
    /// - Parameter batch: les couvertures mesurées, par nom logique.
    /// - Parameter stale: ceux du lot dont l'anglais est plus récent.
    /// - Parameter generation: la génération de la passe qui a produit ce lot.
    /// - Parameter current: la génération en cours.
    /// - Returns: le nouvel état, ou `nil` quand rien ne s'applique — lot vide,
    ///   ou lot périmé.
    ///
    /// **La garde de génération est la réponse à F6-T1.** Le `cancel()` d'un
    /// recalcul n'interrompt pas une fusion déjà engagée : un lot de ≤ 25
    /// mesures de la génération précédente peut atterrir après le recalcul
    /// suivant. C'est bénin tant que le contenu des fichiers ne change pas
    /// entre les deux — les mesures sont alors identiques, ce qui est le cas
    /// aujourd'hui — et cela devient réel le jour de la re-mesure ciblée d'un
    /// seul mod.
    ///
    /// ⚠️ **L'appelant n'a aujourd'hui qu'une génération**, et la ROADMAP dit de
    /// ne pas corriger F6-T1 isolément faute d'observable. Ce paramètre *est*
    /// l'observable : la course s'exprime ici dans un test — deux générations,
    /// arrivée dans le désordre, lot périmé écarté — sans que le comportement
    /// livré change d'un iota. Câbler un compteur dans le chemin vivant reste
    /// à faire, avec la re-mesure ciblée qui lui donnera un sens.
    static func merging(_ batch: [String: TranslationCoverage.Coverage],
                        stale: Set<String>,
                        into current: State,
                        generation: Int = 0,
                        currentGeneration: Int = 0) -> State? {
        guard generation >= currentGeneration else { return nil }
        guard !batch.isEmpty || !stale.isEmpty else { return nil }
        var next = current
        next.coverage.merge(batch) { _, new in new }
        // Un mod du lot qui n'y est plus signalé a cessé d'être suspect — le
        // retirer d'abord laisse `formUnion` ne faire grandir l'ensemble que de
        // ce que ce lot confirme. Latent aujourd'hui, le balayage étant
        // incrémental (chaque mod n'est mesuré qu'une fois) ; nécessaire dès
        // qu'une re-mesure ciblée existera.
        next.stale.subtract(batch.keys)
        next.stale.formUnion(stale)
        return next
    }
}
