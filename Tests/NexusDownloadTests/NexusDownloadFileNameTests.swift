import Testing
import Foundation
@testable import StarHubTHCore

/// **Le nom que Nexus a donné à l'archive.** Le téléchargement intégré
/// déplaçait le fichier fini vers `<UUID>.zip`, ce qui jetait la seule chose
/// que le nom savait dire : l'identifiant de la page et la version. Relevé sur
/// le registre réel, 4 dépôts sur 13 portaient un UUID comme nom — affiché tel
/// quel dans la fiche du mod, sans identifiant ni suivi de version, et
/// impossible à rattacher plus tard puisque le titre ne concorde avec rien.
struct NexusDownloadFileNameTests {

    /// La forme à tirets de Nexus, la plus courante sur un lien direct.
    @Test func keepsTheNexusHyphenForm() {
        #expect(NexusDownloadAPI.archiveBaseName(
            suggested: "MakeGuntherRealFR-34339-1-0-1748539543.zip", url: nil)
            == "MakeGuntherRealFR-34339-1-0-1748539543")
    }

    /// La forme à espaces, dont la version porte des points. ⚠️ Décaper
    /// l'extension au sens de Foundation mangerait `.0 2026-08-05T17-33Z …`
    /// sur un nom sans extension : seule une extension **d'archive connue**
    /// est retirée.
    @Test func keepsADottedVersionWhenThereIsNoArchiveExtension() {
        #expect(NexusDownloadAPI.archiveBaseName(
            suggested: "Cloths and Colors 1.2.8-43258-1-0-1772792211", url: nil)
            == "Cloths and Colors 1.2.8-43258-1-0-1772792211")
        #expect(NexusDownloadAPI.archiveBaseName(
            suggested: "FishingLogbook - FR 50233 1.1.0 2026-08-05T17-33Z 2hI4jbUR4.zip", url: nil)
            == "FishingLogbook - FR 50233 1.1.0 2026-08-05T17-33Z 2hI4jbUR4")
    }

    /// Sans `Content-Disposition`, le nom est dans le chemin de l'URL du CDN —
    /// la requête, elle, est toujours là. La query n'en fait pas partie, et les
    /// espaces y arrivent encodés.
    @Test func fallsBackToTheCDNPath() {
        let url = URL(string: "https://cdn.nexusmods.com/stardewvalley/34339/"
                      + "Make%20Gunther%20Real-34339-1-0.zip?md5=abc&expires=123")!
        #expect(NexusDownloadAPI.archiveBaseName(suggested: nil, url: url)
            == "Make Gunther Real-34339-1-0")
    }

    /// Une URL qui ne finit pas sur une archive ne nomme rien : mieux vaut le
    /// nom de repli de l'appelant qu'un fichier appelé « stardewvalley ».
    @Test func refusesAURLPathThatIsNotAnArchive() {
        #expect(NexusDownloadAPI.archiveBaseName(
            suggested: nil, url: URL(string: "https://cdn.nexusmods.com/stardewvalley/")) == nil)
        #expect(NexusDownloadAPI.archiveBaseName(
            suggested: nil, url: URL(string: "https://api.nexusmods.com/v1/download_link.json")) == nil)
    }

    /// Le nom que Foundation invente quand la réponse n'en porte aucun ne dit
    /// rien de plus qu'un UUID.
    @Test func refusesFoundationsPlaceholder() {
        #expect(NexusDownloadAPI.archiveBaseName(
            suggested: "CFNetworkDownload_a1B2c3.tmp", url: nil) == nil)
    }

    /// Le nom vient d'un service distant : aucun séparateur de chemin ne doit
    /// survivre, sous peine d'écrire ailleurs que dans le dossier voulu.
    @Test func stripsAnyPathSeparator() {
        let name = NexusDownloadAPI.archiveBaseName(
            suggested: "../../../etc/passwd.zip", url: nil)
        #expect(name == "passwd")
        #expect(NexusDownloadAPI.archiveBaseName(suggested: "a/b\\c:d.zip", url: nil)?
            .contains(where: { "/\\:".contains($0) }) == false)
    }

    /// Un nom vide, blanc, ou réduit à un point ne nomme rien.
    @Test func refusesEmptyOrRelativeNames() {
        #expect(NexusDownloadAPI.archiveBaseName(suggested: "", url: nil) == nil)
        #expect(NexusDownloadAPI.archiveBaseName(suggested: "   ", url: nil) == nil)
        #expect(NexusDownloadAPI.archiveBaseName(suggested: ".", url: nil) == nil)
        #expect(NexusDownloadAPI.archiveBaseName(suggested: "..", url: nil) == nil)
        #expect(NexusDownloadAPI.archiveBaseName(suggested: ".zip", url: nil) == nil)
    }

    /// Un nom de fichier a une limite : 255 octets sur APFS, et le nom part
    /// dans un chemin. On plafonne bien en dessous.
    @Test func capsARidiculouslyLongName() {
        let long = String(repeating: "Mod", count: 200) + ".zip"
        let name = NexusDownloadAPI.archiveBaseName(suggested: long, url: nil)
        #expect(name != nil)
        #expect((name?.count ?? 0) <= 100)
    }

    /// `suggested` a la priorité : c'est ce que le service déclare, l'URL n'est
    /// qu'un repli.
    @Test func suggestedWinsOverTheURL() {
        let url = URL(string: "https://cdn.nexusmods.com/x/Other-1-0.zip")!
        #expect(NexusDownloadAPI.archiveBaseName(
            suggested: "Real Name-99999-2-0.zip", url: url) == "Real Name-99999-2-0")
    }
}
