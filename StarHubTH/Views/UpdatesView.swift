import SwiftUI

// MARK: - Updates View (macOS System Settings style)
struct UpdatesView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination
    
    var body: some View {
        // Même confrontation au disque que le badge (X113) : une entrée du
        // relevé SMAPI que le dossier installé couvre déjà ne se liste pas.
        let pendingSmapi = UpdateCount.pendingEntries(outOfDate: vm.outOfDateMods) {
            vm.resolveModFolder(forLoggedName: $0)?.version
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Nexus Mods updates ─────────────────────────────────
                VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.accentColor)
                            .font(AppDesign.Font.headline)
                        Text(localization.L(L10n.Updates.nexusSection))
                            .font(AppDesign.Font.rowTitle(.bold))
                            .foregroundColor(.primary)
                        Spacer()
                        if vm.isCheckingNexusUpdates {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                vm.checkNexusUpdates()
                            } label: {
                                Text(localization.L(L10n.Updates.nexusCheckButton))
                                    .font(AppDesign.Font.caption(.medium))
                            }
                        }
                    }

                    // Note, plus barrage : la vérification passe par smapi.io,
                    // sans clé ni quota. La clé ne manque qu'au téléchargement
                    // intégré. Tant que ce bloc était la première branche de la
                    // chaîne, il **remplaçait** la liste : sans compte Nexus,
                    // aucune mise à jour n'était visible, quand bien même
                    // l'app en avait trouvé.
                    if !vm.hasNexusApiKey {
                        HStack(alignment: .top, spacing: AppDesign.Spacing.sm) {
                            Image(systemName: "key.fill")
                                .foregroundColor(.secondary)
                                .font(AppDesign.Font.caption)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                                Text(localization.L(L10n.Updates.nexusApiKeyMissing))
                                    .font(AppDesign.Font.caption)
                                    .foregroundColor(.secondary)
                                Button {
                                    if let url = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Text(localization.L(L10n.Updates.nexusGetKey))
                                        .font(AppDesign.Font.caption(.medium))
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                        }
                    }

                    if vm.isCheckingNexusUpdates {
                        VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                            HStack(spacing: AppDesign.Spacing.sm) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(localization.L(L10n.Updates.nexusChecking))
                                    .font(AppDesign.Font.caption)
                                    .foregroundColor(.secondary)
                                if let prog = vm.nexusCheckProgress, prog.total > 0 {
                                    Spacer()
                                    Text("\(prog.done)/\(prog.total)")
                                        .font(AppDesign.Font.monoFootnote)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            // Determinate progress bar when we know the total.
                            if let prog = vm.nexusCheckProgress, prog.total > 0 {
                                let fraction = Double(prog.done) / Double(prog.total)
                                ProgressView(value: fraction)
                                    .progressViewStyle(.linear)
                                    .tint(.accentColor)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: vm.nexusCheckProgress?.done)
                    } else if let err = vm.nexusCheckError, vm.nexusUpdates.isEmpty {
                        // A partial run that still found updates falls
                        // through to the list below instead of here — an
                        // error banner must never hide real data that was
                        // actually gathered.
                        Text(err == "rate_limited"
                             ? localization.L(L10n.Updates.nexusRateLimited)
                             : localization.L(L10n.Updates.nexusError))
                            .font(AppDesign.Font.caption)
                            .foregroundColor(AppDesign.Color.error.opacity(0.8))
                    } else if vm.nexusUpdates.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppDesign.Color.success)
                        // C'était `logs_system_alerts_section` — « Aucune
                        // alerte système » — sur la page des **mises à jour** :
                        // le libellé d'une autre page, qui répondait à côté de
                        // la question posée. Jumeau du défaut corrigé en
                        // v1.21.0 dans l'autre sens.
                        //
                        // Avec des invérifiables en suspens, « tous à jour »
                        // serait un quitus pour des mods sans verdict : le
                        // texte ne le dit plus, et le bloc sous la liste
                        // nomme les concernés.
                        Text(localization.L(vm.unverifiableMods.isEmpty
                                  ? L10n.Updates.allUpToDate
                                  : L10n.Updates.allVerifiedUpToDate))
                        }
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                    } else {
                        // Summary line + list of available updates.
                        // Plus de note d'ordre : la liste est alphabétique,
                        // ce qui se voit. La note existait pour un tri par
                        // date de mise en ligne, qui lui ne se voyait pas —
                        // et que le passage à smapi.io avait de toute façon
                        // fait disparaître sans que la phrase suive.
                        Text(String(format: localization.L(L10n.Updates.nexusUpdatesCount),
                                    Int64(vm.nexusUpdates.count)))
                            .font(AppDesign.Font.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, AppDesign.Spacing.xs)

                        ForEach(vm.nexusUpdates) { update in
                            let isEnabled = vm.modForNexusUpdate(update)?.isEnabled ?? false
                            HStack(alignment: .top, spacing: AppDesign.Spacing.lg) {
                                InitialsAvatar(
                                    text: update.name,
                                    initialsCount: 2,
                                    size: 44,
                                    fillColor: Color.accentColor.opacity(0.12),
                                    textColor: .accentColor,
                                    fontSize: 16
                                )

                                VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                                    HStack(spacing: 6) {
                                        Text(update.name)
                                            .font(AppDesign.Font.rowTitle(.semibold))
                                            .foregroundColor(.primary)
                                        Text(isEnabled ? localization.L(L10n.Updates.enabled) : localization.L(L10n.Updates.disabled))
                                            .font(AppDesign.Font.iconXXS(.medium))
                                            .foregroundColor(isEnabled ? AppDesign.Color.installed : AppDesign.Color.warning)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background((isEnabled ? AppDesign.Color.installed : AppDesign.Color.warning).opacity(0.12))
                                            .cornerRadius(4)
                                    }
                                    WrapHStack(spacing: AppDesign.Spacing.md) {
                                        Label("\(localization.L(L10n.Updates.installedVersion)) \(update.installedVersion)",
                                              systemImage: "tag.fill")
                                            .font(AppDesign.Font.footnote)
                                            .foregroundColor(.secondary)
                                        Label("\(localization.L(L10n.Updates.latestVersion)) \(update.latestVersion)",
                                              systemImage: "sparkles")
                                            .font(AppDesign.Font.footnote)
                                            .foregroundColor(.green)
                                        if let uploaded = update.uploadedTime {
                                            Label(vm.formatUploadedDate(uploaded),
                                                  systemImage: "clock.fill")
                                                .font(AppDesign.Font.footnote)
                                                .foregroundColor(.secondary.opacity(0.8))
                                        }
                                    }
                                }

                                Spacer()

                                NexusUpdateActions(update: update, vm: vm, localization: localization)
                            }
                            .padding(.vertical, AppDesign.Spacing.sm)
                            .padding(.horizontal, AppDesign.Spacing.md)
                            .background(isEnabled ? Color.primary.opacity(0.04) : AppDesign.Color.warning.opacity(0.06))
                            .cornerRadius(10)
                        }
                    }

                    // Le silence sur ces mods est ce qui a rendu la fenêtre
                    // mensongère : « tous à jour » alors que certains n'avaient
                    // de verdict d'aucune source. Jusqu'à 115 mods du parc réel
                    // sont dans ce cas — d'où le repli : à plat, la liste
                    // noierait les mises à jour réelles au-dessus d'elle.
                    if !vm.unverifiableMods.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 3) {
                                // Indexé par `UniqueID` : deux mods peuvent
                                // porter le même nom, mais la réponse de
                                // smapi.io n'a qu'une entrée par identifiant.
                                // Indexer par rang ferait glisser les lignes
                                // quand la reprise Nexus en retire une.
                                ForEach(vm.unverifiableMods, id: \.uniqueId) { row in
                                    HStack(spacing: 6) {
                                        Text(row.name)
                                            .font(AppDesign.Font.footnote(.medium))
                                        Text(localization.L(row.blocker.labelKey))
                                            .font(AppDesign.Font.footnote)
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 8)
                                    }
                                }
                            }
                            .padding(.vertical, AppDesign.Spacing.xs)
                        } label: {
                            Label(String(format: localization.L(L10n.Updates.unverifiableTitle),
                                         Int64(vm.unverifiableMods.count)),
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(AppDesign.Font.caption)
                                .foregroundColor(AppDesign.Color.warning)
                        }
                    }

                    // X12 — ce que « Je l'ai déjà » a fait taire.
                    //
                    // **Hors de la chaîne `if/else` ci-dessus**, comme le bloc
                    // des invérifiables : c'est justement quand la page annonce
                    // « tous à jour » que ces mods doivent se voir. Sur
                    // l'installation de référence, 34 mods étaient éteints sans
                    // que rien ne le dise, et plusieurs par mégarde.
                    if !vm.affirmedUpdates.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                // L'explication d'abord : la liste seule ne dit
                                // ni ce que le geste a fait, ni ce qu'il coûte.
                                Text(localization.L(L10n.Updates.affirmedExplanation))
                                    .font(AppDesign.Font.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 2)

                                ForEach(vm.affirmedUpdates) { row in
                                    HStack(spacing: AppDesign.Spacing.sm) {
                                        Text(row.name)
                                            .font(AppDesign.Font.footnote(.medium))
                                            .lineLimit(1)
                                        // Les deux versions côte à côte : le
                                        // numéro affirmé seul ne dit rien,
                                        // c'est l'écart avec le disque qui
                                        // trahit le clic malheureux.
                                        Text(String(format: localization.L(L10n.Updates.affirmedVersion),
                                                    row.affirmedVersion))
                                            .font(AppDesign.Font.monoFootnote)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: localization.L(L10n.Updates.affirmedOnDisk),
                                                    row.manifestVersion))
                                            .font(AppDesign.Font.monoFootnote)
                                            .foregroundColor(row.disagreesWithDisk
                                                             ? AppDesign.Color.warning : .secondary)
                                        Spacer(minLength: 8)
                                        // Voir la fiche avant de décider :
                                        // c'est là que se lisent la version,
                                        // la compatibilité et l'historique du
                                        // mod. On pose la cible PUIS on
                                        // bascule — `MainView` remet à `nil`
                                        // les états de détail dans son
                                        // `onChange(of: currentTab)`, et
                                        // `pendingModDetailFocus` est ce qui
                                        // traverse (patron B3-T4).
                                        //
                                        // Le **dossier**, pas le nom : le
                                        // résolveur le cherche en premier, et
                                        // deux mods homonymes ouvriraient la
                                        // fiche du premier venu.
                                        Button {
                                            vm.navigationStore.pendingModDetailFocus = row.folderName
                                            vm.navigationStore.pendingDetailTab = .state
                                            currentTab = .mods
                                        } label: {
                                            Text(localization.L(L10n.Updates.affirmedOpenMod))
                                                .font(AppDesign.Font.footnote)
                                        }
                                        .buttonStyle(.plain)
                                        .pointingHandCursor()
                                        .help(localization.L(L10n.Updates.affirmedOpenModHelp))
                                        Button {
                                            vm.revealAffirmedUpdate(uniqueId: row.uniqueId)
                                        } label: {
                                            Text(localization.L(L10n.Updates.affirmedReveal))
                                                .font(AppDesign.Font.footnote)
                                        }
                                        .buttonStyle(.plain)
                                        .pointingHandCursor()
                                        .help(localization.L(L10n.Updates.affirmedRevealHelp))
                                    }
                                }
                            }
                            .padding(.vertical, AppDesign.Spacing.xs)
                        } label: {
                            Label(String(format: localization.L(L10n.Updates.affirmedTitle),
                                         Int64(vm.affirmedUpdates.count)),
                                  systemImage: "eye.slash")
                                .font(AppDesign.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // R3 — ce que « Mettre en veille » a endormi. Même
                    // patron que les deux replis ci-dessus, et pour la même
                    // raison : la liste doit rester trouvable et réversible —
                    // snoozer ne doit jamais ressembler à perdre une
                    // information. Contrairement à « je l'ai déjà », rien
                    // n'est affirmé ici : tout revient tout seul.
                    if !vm.snoozedUpdates.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(localization.L(L10n.Updates.snoozedExplanation))
                                    .font(AppDesign.Font.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 2)
                                ForEach(vm.snoozedUpdates) { row in
                                    HStack(spacing: AppDesign.Spacing.sm) {
                                        Text(row.name)
                                            .font(AppDesign.Font.footnote(.medium))
                                            .lineLimit(1)
                                        Text(vm.snoozeExpiryLabel(for: row))
                                            .font(AppDesign.Font.footnote)
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 8)
                                        Button {
                                            vm.unsnoozeUpdate(uniqueId: row.uniqueId)
                                        } label: {
                                            Text(localization.L(L10n.Updates.snoozedWake))
                                                .font(AppDesign.Font.footnote)
                                        }
                                        .buttonStyle(.plain)
                                        .pointingHandCursor()
                                    }
                                }
                            }
                            .padding(.vertical, AppDesign.Spacing.xs)
                        } label: {
                            Label(String(format: localization.L(L10n.Updates.snoozedTitle),
                                         Int64(vm.snoozedUpdates.count)),
                                  systemImage: "moon.zzz.fill")
                                .font(AppDesign.Font.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)

                // I-T16 — après la liste qui porte les gestes : ce relevé constate.
                if !pendingSmapi.isEmpty {
                    // Ces cartes n'avaient aucun en-tête, quand celles de Nexus
                    // en ont un : rien ne disait d'où venait l'information, ni
                    // pourquoi ces mods-là étaient là et pas d'autres.
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                        HStack(spacing: AppDesign.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(AppDesign.Color.warning)
                                .font(AppDesign.Font.headline)
                            Text(localization.L(L10n.Updates.smapiSection))
                                .font(AppDesign.Font.rowTitle(.bold))
                                .foregroundColor(.primary)
                        }
                        Text(localization.L(L10n.Updates.smapiNote))
                            .font(AppDesign.Font.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(pendingSmapi) { mod in
                        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                            HStack(alignment: .top, spacing: AppDesign.Spacing.lg) {
                                // App Icon Fake
                                InitialsAvatar(
                                    text: mod.name,
                                    initialsCount: 2,
                                    size: 56,
                                    fillColor: Color.blue.opacity(0.1),
                                    textColor: .blue.opacity(0.8),
                                    fontSize: 20
                                )
                                
                                VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                                    Text(mod.name)
                                        .font(AppDesign.Font.headline(.bold))
                                        .foregroundColor(.primary)
                                    // `ModUpdateInfo.version` est la version
                                    // **disponible** — celle que SMAPI annonce
                                    // dans « You can update N mods ». Nue sous
                                    // le nom du mod, elle se lisait comme la
                                    // version installée, c'est-à-dire l'inverse.
                                    Text(String(format: localization.L(L10n.Updates.availableVersion),
                                                mod.version))
                                        .font(AppDesign.Font.caption)
                                        .foregroundColor(.secondary)
                                    
                                    // Pas « disponible sur Nexus Mods » :
                                    // ces lignes viennent du journal SMAPI, et
                                    // leur lien pointe vers smapi.io. Le mod
                                    // peut n'avoir aucune page Nexus. Le
                                    // pourquoi est dit une fois, plus bas.
                                    Text(localization.L(L10n.Updates.updateAvailable))
                                        .font(AppDesign.Font.caption)
                                        .foregroundColor(.orange)
                                        .padding(.top, 2)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: AppDesign.Spacing.sm) {
                                    Button(action: {
                                        if let url = URL(string: mod.url) { NSWorkspace.shared.open(url) }
                                    }) {
                                        // Il ouvre `smapi.io/mods#…`, où rien
                                        // ne se télécharge : promettre un
                                        // téléchargement était un faux départ.
                                        Text(localization.L(L10n.Updates.openSmapiPage))
                                            .font(AppDesign.Font.caption(.medium))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, AppDesign.Spacing.lg)
                                            .padding(.vertical, 6)
                                            .background(Color.primary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    .pointingHandCursor()
                                }
                            }

                            VStack(alignment: .leading, spacing: AppDesign.Spacing.lg) {
                                // Le texte d'avant — « apporte de nouvelles
                                // fonctionnalités et des corrections de bugs »
                                // — était inventé : l'app ne sait rien du
                                // contenu de la mise à jour. La phrase le dit
                                // maintenant, au lieu de le supposer.
                                Text(localization.L(L10n.Updates.smapiDescription))
                                    .font(AppDesign.Font.body)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: AppDesign.Spacing.xs) {
                                    Text(localization.L(L10n.Updates.visitWebsite))
                                        .font(AppDesign.Font.body)
                                        .foregroundColor(.secondary)
                                    // Vrai lien cliquable plutôt qu'un Markdown
                                    // `[url](url)` interpolé que Text rendait en brut.
                                    if let url = URL(string: mod.url) {
                                        Link(url.absoluteString, destination: url)
                                            .font(AppDesign.Font.body)
                                    }
                                }
                                .tint(.blue)
                            }
                            .padding(.top, AppDesign.Spacing.sm)
                        }
                        .padding(20)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(12)
                    }
                }

            }
            .padding(30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        // Le scan de lancement remplit déjà la liste ; ce rappel couvre
        // l'ouverture de l'onglet avant qu'il n'ait rendu la main, et le
        // retour sur l'onglet après une affirmation faite ailleurs.
        .onAppear { vm.refreshAffirmedUpdates() }
    }
}
