import SwiftUI

// Sorti de SettingsView.swift le 2026-09-25 (onglets des Réglages) : une
// section autonome de ~480 lignes, sans rien de privé au fichier d'origine.

/// La section « Traduction assistée » des réglages (tâche 15 du plan P2b,
/// spec §6) : serveur IA local + glossaire du jeu.
///
/// Le sondage des briques connues (Ollama 11434, LM Studio 1234) tourne à
/// l'apparition, en parallèle, timeout 2 s : une répond → URL préremplie ;
/// les deux → deux lignes, au choix ; aucune → champ libre et la mention
/// d'installation. La saisie manuelle reste toujours possible — le champ
/// n'est jamais verrouillé sur ce que le sondage a vu.
struct LocalAISettingsSection: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    @AppStorage(UDKey.localAIBaseURL) private var baseURL: String = ""
    @AppStorage(UDKey.localAIModel) private var model: String = ""

    @State private var probes: [LocalLLMClient.ProbeResult] = []
    @State private var isProbing = true
    @State private var models: [String] = []
    @State private var testVerdictOK: Bool?
    @State private var isRebuildingGlossary = false
    @State private var glossaryCount: Int?
    @State private var glossaryDate: Date?
    /// La mémoire de la machine, lue une fois : un `sysctl` à chaque passe de
    /// rendu serait payé pour rien, elle ne change pas.
    @State private var ramGB = LocalModelAdvisor.machineRAMGB()
    @State private var didCopyPullCommand = false
    /// Le modèle réglé délibère avant de répondre — su par la route native
    /// d'Ollama, inconnue de LM Studio (qui laisse alors ce drapeau à `false`).
    @State private var modelThinks = false

    /// Le secours en ligne. La clé n'est **jamais** réaffichée : le champ
    /// sert à en saisir une nouvelle, et « Clé enregistrée » dit qu'il y en a
    /// une. La relire pour la remettre dans un champ n'apporterait rien et
    /// promènerait un secret dans la mémoire de la vue.
    @AppStorage(UDKey.deepLFallbackEnabled) private var fallbackEnabled = false
    @State private var fallbackKeyDraft = ""
    @State private var fallbackUsage: DeepLClient.Usage?
    @State private var fallbackTestError: String?
    @State private var isTestingFallback = false
    /// LaunchServices interrogé **une fois**, à la création de la vue : la
    /// réponse ne change pas pendant qu'on règle un panneau, et la question
    /// n'a pas à être reposée à chaque passe de rendu.
    @State private var isDeepLAppInstalled = DeepLDesktop.isInstalled()

    var body: some View {
        VStack(spacing: 32) {
            StandardSection(
                title: localization.L(L10n.Settings.localAITitle),
                // « Rien n'est envoyé ailleurs que sur votre serveur local »
                // devient faux dès que le secours est actif : la phrase de
                // confidentialité passe alors au bloc qui en est la cause.
                footer: isFallbackActive ? nil : localization.L(L10n.Settings.localAIPrivacy)
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if isProbing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                        }
                    } else if probes.isEmpty {
                        Text(localization.L(L10n.Settings.localAINoneDetected))
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        // Chaque brique détectée est cliquable : elle préremplit
                        // l'URL et ses modèles — deux briques, deux lignes, le
                        // choix appartient à l'utilisateur.
                        ForEach(probes, id: \.baseURL.absoluteString) { probe in
                            Button {
                                baseURL = probe.baseURL.absoluteString
                                models = probe.models
                                if model.isEmpty || !probe.models.contains(model) {
                                    model = probe.models.first ?? ""
                                }
                                testVerdictOK = nil
                            } label: {
                                Label(String(format: localization.L(L10n.Settings.localAIDetected),
                                             probe.baseURL.absoluteString,
                                             Int64(probe.models.count)),
                                      systemImage: "circle.fill")
                                    .font(AppDesign.Font.footnote)
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localization.L(L10n.Settings.localAIURL)).font(AppDesign.Font.body)
                        TextField("http://localhost:11434", text: $baseURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(AppDesign.Font.monoCaption)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(localization.L(L10n.Settings.localAIModel)).font(AppDesign.Font.body)
                            if !models.isEmpty {
                                // Les modèles vus sur ce serveur, en choix
                                // rapide — le champ reste la voie de saisie
                                // libre, jamais remplacé.
                                Menu(localization.L(L10n.Settings.localAIModel)) {
                                    ForEach(models, id: \.self) { name in
                                        Button(name) { model = name }
                                    }
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                        TextField("qwen2.5", text: $model)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(AppDesign.Font.monoCaption)
                        // Un modèle à raisonnement épuise le budget de jetons
                        // en délibérant : la réponse revient tronquée et le
                        // client la rejette. Le dire ici, pas après un lot.
                        if modelThinks {
                            Label(localization.L(L10n.Settings.localAIModelThinks),
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(AppDesign.Font.footnote)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // Ollama fraîchement installé n'a aucun modèle, et le
                        // bon nom n'est pas devinable. L'aide ne s'affiche que
                        // tant que le champ est vide : une fois réglé, elle
                        // n'a plus rien à dire.
                        if model.isEmpty { modelAdvice }
                    }

                    HStack(spacing: 8) {
                        Button {
                            testConnection()
                        } label: {
                            Text(localization.L(L10n.Settings.localAITest))
                        }
                        .disabled(baseURL.isEmpty)
                        if testVerdictOK == true {
                            Text(localization.L(L10n.Settings.localAIOK))
                                .font(AppDesign.Font.footnote)
                                .foregroundColor(.green)
                        } else if testVerdictOK == false {
                            // Pas « aucun serveur détecté » : l'utilisateur
                            // vient de saisir une URL, c'est d'elle qu'on parle.
                            Text(localization.L(L10n.Settings.localAITestFailed))
                                .font(AppDesign.Font.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            fallbackSection

            StandardSection(title: localization.L(L10n.Settings.glossaryTitle)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if let count = glossaryCount, let date = glossaryDate {
                            Text(String(format: localization.L(L10n.Settings.glossaryInfo),
                                        Int64(count),
                                        date.formatted(date: .abbreviated, time: .shortened)))
                                .font(AppDesign.Font.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(localization.L(L10n.Settings.glossaryNone))
                                .font(AppDesign.Font.footnote)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            rebuildGlossary()
                        } label: {
                            if isRebuildingGlossary {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(localization.L(L10n.Settings.glossaryRebuild))
                            }
                        }
                        .disabled(isRebuildingGlossary)
                    }
                }
            }
        }
        .task {
            // Sondage parallèle des deux briques, timeout 2 s (spec §6).
            let session = LocalLLMEndpoint.makeSession(timeout: 2)
            probes = await LocalLLMClient.probeBricks(session: session)
            session.finishTasksAndInvalidate()
            isProbing = false
            if baseURL.isEmpty, let first = probes.first {
                baseURL = first.baseURL.absoluteString
            }
            // Les modèles proposés — et le modèle par défaut — viennent du
            // serveur que **l'URL désigne**, jamais du premier sondé : une URL
            // déjà réglée sur Ollama recevait sinon un modèle de LM Studio, et
            // chaque requête postait un nom que le serveur ne connaît pas.
            if let current = probeMatching(baseURL) {
                models = current.models
                if model.isEmpty { model = current.models.first ?? "" }
            }
            await refreshModelSuitability()
            glossaryCount = vm.currentGlossary(language: "fr")?.entries.count
            glossaryDate = vm.glossaryBuiltDate(language: "fr")
        }
    }

    // MARK: - Secours en ligne

    /// Le secours part-il vraiment ? La même question que
    /// `vm.isFallbackEnabled`, posée sur l'`@AppStorage` local pour que la
    /// vue se redessine à l'instant où la case change.
    private var isFallbackActive: Bool { fallbackEnabled && vm.hasDeepLKey }

    /// La phrase de confidentialité suit l'état, y compris le cas où DeepL
    /// est le **seul** moteur : dire « quand l'IA locale échoue » à qui n'en
    /// a pas serait faux, et c'est justement la configuration la plus
    /// probable sur une machine qui ne fait pas tourner de modèle.
    private var fallbackPrivacy: String {
        guard isFallbackActive else { return localization.L(L10n.Settings.fallbackPrivacyOff) }
        return vm.isLocalAIConfigured
            ? localization.L(L10n.Settings.fallbackPrivacyOn)
            : localization.L(L10n.Settings.fallbackPrivacyOnNoLocal)
    }

    private var fallbackSection: some View {
        StandardSection(title: localization.L(L10n.Settings.fallbackTitle),
                        footer: fallbackPrivacy) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.L(L10n.Settings.fallbackKey)).font(AppDesign.Font.body)
                    // Même forme que la clé Nexus : une fois la clé enregistrée,
                    // le champ cède la place à un masque. Il restait saisissable
                    // ici, avec son bouton « Enregistrer » — on pouvait donc
                    // écraser une clé en place sans l'avoir voulu, et rien ne
                    // montrait qu'il y en avait déjà une, sinon la ligne verte
                    // plus bas.
                    if vm.hasDeepLKey {
                        HStack(spacing: 8) {
                            Text("••••••••••••")
                                .font(AppDesign.Font.monoCaption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(localization.L(L10n.Settings.fallbackGetKey)) {
                                NSWorkspace.shared.open(DeepLDesktop.apiKeyPageURL)
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            SecureField("", text: $fallbackKeyDraft)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(AppDesign.Font.monoCaption)
                            Button(localization.L(L10n.Settings.fallbackSave)) { saveFallbackKey() }
                                .disabled(fallbackKeyDraft
                                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            // La page que la documentation de DeepL nomme
                            // elle-même ; sans session, elle mène à la connexion,
                            // d'où l'offre gratuite est accessible.
                            Button(localization.L(L10n.Settings.fallbackGetKey)) {
                                NSWorkspace.shared.open(DeepLDesktop.apiKeyPageURL)
                            }
                        }
                    }
                    // Dit seulement quand l'application est là. Une résolution
                    // vide ne prouve pas l'absence, donc on n'affirme rien.
                    if isDeepLAppInstalled {
                        Text(localization.L(L10n.Settings.fallbackDesktopApp))
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if vm.hasDeepLKey {
                        HStack(spacing: 8) {
                            Text(localization.L(L10n.Settings.fallbackSaved))
                                .font(AppDesign.Font.footnote)
                                .foregroundColor(.green)
                            Button(localization.L(L10n.Settings.fallbackClear)) {
                                vm.clearDeepLKey()
                                // Le champ réapparaît : le laisser prérempli
                                // de ce qu'on venait de saisir rendrait la
                                // suppression douteuse.
                                fallbackKeyDraft = ""
                                // Une case cochée sans clé n'aurait plus de
                                // sens : la décocher évite qu'elle se
                                // rallume toute seule à la prochaine clé.
                                fallbackEnabled = false
                                fallbackUsage = nil
                                fallbackTestError = nil
                            }
                            .buttonStyle(.link)
                        }
                    } else {
                        Text(localization.L(L10n.Settings.fallbackNeedsKey))
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    Button(localization.L(L10n.Settings.fallbackTest)) { testFallback() }
                        .disabled(!vm.hasDeepLKey || isTestingFallback)
                    if isTestingFallback {
                        ProgressView().controlSize(.small)
                    } else if let usage = fallbackUsage {
                        // Le plafond vient du service : le coder en dur
                        // mentirait au premier changement d'offre.
                        Text(String(format: localization.L(L10n.Settings.fallbackQuota),
                                    Int64(usage.used), Int64(usage.limit)))
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary)
                    } else if let error = fallbackTestError {
                        Text(error)
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Toggle(localization.L(vm.isLocalAIConfigured ? L10n.Settings.fallbackEnable
                                                   : L10n.Settings.fallbackEnableNoLocal),
                       isOn: $fallbackEnabled)
                    .disabled(!vm.hasDeepLKey)
                    .font(AppDesign.Font.body)
            }
        }
    }

    private func saveFallbackKey() {
        let key = fallbackKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        fallbackUsage = nil
        fallbackTestError = vm.setDeepLKey(key) ? nil : localization.L(L10n.Settings.fallbackFailed)
        // Le champ se vide : la clé vit au trousseau, pas dans la vue.
        fallbackKeyDraft = ""
    }

    private func testFallback() {
        guard let credentials = DeepLClient.Credentials.fromKeychain() else {
            fallbackTestError = localization.L(L10n.Settings.fallbackFailed)
            return
        }
        isTestingFallback = true
        fallbackUsage = nil
        fallbackTestError = nil
        Task { @MainActor in
            defer { isTestingFallback = false }
            let session = LocalLLMEndpoint.makeSession(timeout: 20)
            defer { session.finishTasksAndInvalidate() }
            do {
                fallbackUsage = try await DeepLClient.usage(credentials: credentials,
                                                            session: session)
            } catch DeepLClient.UsageError.unauthorized {
                fallbackTestError = localization.L(L10n.Settings.fallbackFailed)
            } catch {
                // Ni la clé ni l'URL : un service muet ou une réponse
                // illisible ne disent rien de la clé, et l'annoncer refusée
                // enverrait l'utilisateur la changer pour rien.
                fallbackTestError = localization.L(L10n.Settings.fallbackUnreachable)
            }
        }
    }

    /// Quel modèle prendre, pour cette machine et ce qui est déjà installé.
    /// Un modèle déjà présent qui convient vaut mieux que six gigaoctets à
    /// télécharger ; sinon, la commande exacte, copiable — on ne demande pas
    /// à l'utilisateur de retaper un tag sans se tromper.
    @ViewBuilder
    private var modelAdvice: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch LocalModelAdvisor.advise(ramGB: ramGB, installed: models) {
            case .useInstalled(let tag):
                Text(String(format: localization.L(L10n.Settings.localAIAdviceInstalled),
                            tag, Int64(ramGB)))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(format: localization.L(L10n.Settings.localAIAdviceUse), tag)) {
                    model = tag
                }
                .controlSize(.small)
            case .pull(let candidate):
                Text(String(format: localization.L(L10n.Settings.localAIAdvicePull),
                            Int64(ramGB), candidate.tag,
                            candidate.downloadGB.formatted(
                                .number.precision(.fractionLength(0...1)))))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text("ollama pull \(candidate.tag)")
                        .font(AppDesign.Font.monoFootnote)
                        .textSelection(.enabled)
                    Button(localization.L(didCopyPullCommand ? L10n.Settings.localAICopied
                                                   : L10n.Settings.localAICopy)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("ollama pull \(candidate.tag)",
                                                       forType: .string)
                        // « Copié » deux secondes, comme le flash de la clé
                        // Nexus — mais sans `DispatchQueue`, que le cliquet
                        // des conventions cherche justement à faire reculer.
                        withMotion { didCopyPullCommand = true }
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            withMotion { didCopyPullCommand = false }
                        }
                    }
                    .controlSize(.small)
                }
                // Le lien n'a de sens que si rien n'a répondu : avec un
                // serveur détecté, Ollama est déjà là.
                if probes.isEmpty, let url = URL(string: "https://ollama.com/download") {
                    Button(localization.L(L10n.Settings.localAIInstallOllama)) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .font(AppDesign.Font.footnote)
                    .pointingHandCursor()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    /// La brique sondée que `text` désigne — appariée sur le **port**, pas
    /// sur l'ordre du sondage. Comparer les hôtes serait un piège : les
    /// briques connues s'annoncent en `127.0.0.1`, l'invite du champ propose
    /// `localhost`, et `validate` accepte aussi `::1` et tout `127.x.x.x`.
    /// Trois écritures de la même machine — seul le port distingue Ollama de
    /// LM Studio, et l'endpoint est loopback par construction.
    private func probeMatching(_ text: String) -> LocalLLMClient.ProbeResult? {
        guard let url = LocalLLMEndpoint.validate(text) else { return nil }
        return probes.first { $0.baseURL.port == url.port }
    }

    /// Demande au serveur ce qu'il sait du modèle réglé. Silencieux quand il
    /// ne sait rien (LM Studio n'a pas cette route) : une information absente
    /// n'est pas un avertissement.
    private func refreshModelSuitability() async {
        guard let url = LocalLLMEndpoint.validate(baseURL), !model.isEmpty else {
            modelThinks = false
            return
        }
        let session = LocalLLMEndpoint.makeSession(timeout: 5)
        defer { session.finishTasksAndInvalidate() }
        let report = await OllamaCapabilities.fetch(model: model, baseURL: url,
                                                    session: session)
        modelThinks = report?.thinks ?? false
    }

    private func testConnection() {
        Task {
            guard let url = LocalLLMEndpoint.validate(baseURL) else {
                testVerdictOK = false
                return
            }
            let session = LocalLLMEndpoint.makeSession(timeout: 5)
            defer { session.finishTasksAndInvalidate() }
            do {
                models = try await LocalLLMClient.listModels(baseURL: url, session: session)
                testVerdictOK = true
                await refreshModelSuitability()
            } catch {
                testVerdictOK = false
            }
        }
    }

    private func rebuildGlossary() {
        Task {
            isRebuildingGlossary = true
            defer { isRebuildingGlossary = false }
            glossaryCount = await vm.rebuildGlossary(language: "fr")
            glossaryDate = vm.glossaryBuiltDate(language: "fr")
        }
    }
}
