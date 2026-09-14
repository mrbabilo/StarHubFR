import SwiftUI

// MARK: - Updates View (macOS System Settings style)
struct UpdatesView: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @Binding var currentTab: SidebarDestination
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // Out of date mods (Software Update style)
                if !vm.outOfDateMods.isEmpty {
                    // Ces cartes n'avaient aucun en-tête, quand celles de Nexus
                    // en ont un : rien ne disait d'où venait l'information, ni
                    // pourquoi ces mods-là étaient là et pas d'autres.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.system(size: 16))
                            Text(localization.L(L10n.Updates.smapiSection))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        Text(localization.L(L10n.Updates.smapiNote))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(vm.outOfDateMods) { mod in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 16) {
                                // App Icon Fake
                                InitialsAvatar(
                                    text: mod.name,
                                    initialsCount: 2,
                                    size: 56,
                                    fillColor: Color.blue.opacity(0.1),
                                    textColor: .blue.opacity(0.8),
                                    fontSize: 20
                                )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mod.name)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.primary)
                                    // `ModUpdateInfo.version` est la version
                                    // **disponible** — celle que SMAPI annonce
                                    // dans « You can update N mods ». Nue sous
                                    // le nom du mod, elle se lisait comme la
                                    // version installée, c'est-à-dire l'inverse.
                                    Text(String(format: localization.L(L10n.Updates.availableVersion),
                                                mod.version))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    
                                    // Pas « disponible sur Nexus Mods » :
                                    // ces lignes viennent du journal SMAPI, et
                                    // leur lien pointe vers smapi.io. Le mod
                                    // peut n'avoir aucune page Nexus. Le
                                    // pourquoi est dit une fois, plus bas.
                                    Text(localization.L(L10n.Updates.updateAvailable))
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)
                                        .padding(.top, 2)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    Button(action: {
                                        if let url = URL(string: mod.url) { NSWorkspace.shared.open(url) }
                                    }) {
                                        // Il ouvre `smapi.io/mods#…`, où rien
                                        // ne se télécharge : promettre un
                                        // téléchargement était un faux départ.
                                        Text(localization.L(L10n.Updates.openSmapiPage))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 6)
                                            .background(Color.primary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .pointingHandCursor()
                                }
                            }

                            VStack(alignment: .leading, spacing: 16) {
                                // Le texte d'avant — « apporte de nouvelles
                                // fonctionnalités et des corrections de bugs »
                                // — était inventé : l'app ne sait rien du
                                // contenu de la mise à jour. La phrase le dit
                                // maintenant, au lieu de le supposer.
                                Text(localization.L(L10n.Updates.smapiDescription))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 4) {
                                    Text(localization.L(L10n.Updates.visitWebsite))
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                    // Vrai lien cliquable plutôt qu'un Markdown
                                    // `[url](url)` interpolé que Text rendait en brut.
                                    if let url = URL(string: mod.url) {
                                        Link(url.absoluteString, destination: url)
                                            .font(.system(size: 13))
                                    }
                                }
                                .tint(.blue)
                            }
                            .padding(.top, 8)
                        }
                        .padding(20)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(12)
                    }
                }
                
                // ── Nexus Mods updates ─────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 16))
                        Text(localization.L(L10n.Updates.nexusSection))
                            .font(.system(size: 14, weight: .bold))
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
                                    .font(.system(size: 12, weight: .medium))
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
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "key.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(localization.L(L10n.Updates.nexusApiKeyMissing))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Button {
                                    if let url = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Text(localization.L(L10n.Updates.nexusGetKey))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                        }
                    }

                    if vm.isCheckingNexusUpdates {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(localization.L(L10n.Updates.nexusChecking))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                if let prog = vm.nexusCheckProgress, prog.total > 0 {
                                    Spacer()
                                    Text("\(prog.done)/\(prog.total)")
                                        .font(.system(size: 11, design: .monospaced))
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
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                    } else if vm.nexusUpdates.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
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
                        .font(.system(size: 12))
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
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        ForEach(vm.nexusUpdates) { update in
                            let isEnabled = vm.modForNexusUpdate(update)?.isEnabled ?? false
                            HStack(alignment: .top, spacing: 16) {
                                InitialsAvatar(
                                    text: update.name,
                                    initialsCount: 2,
                                    size: 44,
                                    fillColor: Color.accentColor.opacity(0.12),
                                    textColor: .accentColor,
                                    fontSize: 16
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(update.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text(isEnabled ? localization.L(L10n.Updates.enabled) : localization.L(L10n.Updates.disabled))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(isEnabled ? AppDesign.Color.installed : .orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background((isEnabled ? AppDesign.Color.installed : Color.orange).opacity(0.12))
                                            .cornerRadius(4)
                                    }
                                    HStack(spacing: 12) {
                                        Label("\(localization.L(L10n.Updates.installedVersion)) \(update.installedVersion)",
                                              systemImage: "tag.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Label("\(localization.L(L10n.Updates.latestVersion)) \(update.latestVersion)",
                                              systemImage: "sparkles")
                                            .font(.system(size: 11))
                                            .foregroundColor(.green)
                                        if let uploaded = update.uploadedTime {
                                            Label(vm.formatUploadedDate(uploaded),
                                                  systemImage: "clock.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary.opacity(0.8))
                                        }
                                    }
                                }

                                Spacer()

                                if let nexusId = Int(update.nexusModId),
                                   vm.downloadingNexusModId == nexusId {
                                    // Le pourcentage à côté du témoin quand
                                    // la taille est connue : la ligne est le
                                    // seul endroit où l'on regarde après avoir
                                    // cliqué, et le pied de barre latérale
                                    // n'est pas toujours dans le champ.
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        if let percent = vm.nexusDownloadProgress?.displayPercent {
                                            Text("\(percent) %")
                                                .font(.system(size: 11).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        Button(action: { vm.cancelNexusDownload() }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 12))
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                        .pointingHandCursor()
                                        .help(localization.L(L10n.Downloads.cancel))
                                    }
                                    .help(localization.L(L10n.VM.nexusDlStarting).replacingOccurrences(of: "%lld", with: String(nexusId)))
                                } else {
                                    if let nexusId = Int(update.nexusModId) {
                                        Button {
                                            vm.downloadModFromNexus(nexusId: nexusId)
                                        } label: {
                                            Label(localization.L(L10n.Mods.premiumUpdate), systemImage: "arrow.down.circle")
                                        }
                                        .buttonStyle(.bordered)
                                        // Désactivé quand on **sait** que le
                                        // compte n'est pas premium : l'API
                                        // refuse alors tout lien direct
                                        // (`403 premium users only`), et
                                        // proposer le bouton revient à promettre
                                        // un échec. Le doute, lui, ne retire
                                        // rien.
                                        .disabled(vm.isDownloadingFromNexus || vm.nexusDirectDownloadUnavailable)
                                        .help(vm.nexusDirectDownloadUnavailable
                                              ? localization.L(L10n.Mods.premiumOnlyHint) : "")
                                    }

                                    Button {
                                        // Open the mod's Files tab directly, where the free
                                        // "Mod Manager Download" (nxm://) button lives.
                                        if var comps = URLComponents(string: update.url) {
                                            comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "tab", value: "files")]
                                            if let url = comps.url { NSWorkspace.shared.open(url) }
                                        }
                                    } label: {
                                        Text(localization.L(L10n.Mods.nexusUpdate))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color.primary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .pointingHandCursor()
                                    .disabled(vm.isDownloadingFromNexus)

                                    // La seule sortie quand l'auteur a oublié
                                    // d'incrémenter son manifest : la
                                    // comparaison de chaînes réclamera cette
                                    // mise à jour à chaque passe, sinon.
                                    Button {
                                        vm.affirmInstalled(uniqueId: update.uniqueId,
                                                           version: update.latestVersion)
                                    } label: {
                                        Text(localization.L(L10n.Updates.nexusAlreadyHave))
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .pointingHandCursor()
                                    .help(localization.L(L10n.Updates.nexusAlreadyHaveHelp))

                                    // R3 — « je sais, pas maintenant ». Troisième
                                    // geste après mettre à jour et « je l'ai
                                    // déjà » : l'update est vraie mais pas
                                    // voulue tout de suite. La ligne disparaît
                                    // d'ici (et du badge), jamais de
                                    // l'inventaire, et revient toute seule
                                    // selon le mode choisi.
                                    Menu {
                                        Button {
                                            vm.snoozeUpdate(update, mode: .oneWeek)
                                        } label: {
                                            Label(localization.L(L10n.Updates.snoozeOneWeek),
                                                  systemImage: "clock")
                                        }
                                        Button {
                                            vm.snoozeUpdate(update, mode: .untilModVersion)
                                        } label: {
                                            Label(localization.L(L10n.Updates.snoozeUntilModVersion),
                                                  systemImage: "sparkles")
                                        }
                                        Button {
                                            vm.snoozeUpdate(update, mode: .untilGameVersion)
                                        } label: {
                                            Label(localization.L(L10n.Updates.snoozeUntilGameVersion),
                                                  systemImage: "gamecontroller")
                                        }
                                    } label: {
                                        Label(localization.L(L10n.Updates.snoozeButton),
                                              systemImage: "moon.zzz.fill")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 6)
                                            .background(Color.primary.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .fixedSize()
                                    .pointingHandCursor()
                                    .disabled(vm.isDownloadingFromNexus)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(isEnabled ? Color.primary.opacity(0.04) : Color.orange.opacity(0.06))
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
                                            .font(.system(size: 11, weight: .medium))
                                        Text(localization.L(row.blocker.labelKey))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 8)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        } label: {
                            Label(String(format: localization.L(L10n.Updates.unverifiableTitle),
                                         Int64(vm.unverifiableMods.count)),
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
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
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 2)

                                ForEach(vm.affirmedUpdates) { row in
                                    HStack(spacing: 8) {
                                        Text(row.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        // Les deux versions côte à côte : le
                                        // numéro affirmé seul ne dit rien,
                                        // c'est l'écart avec le disque qui
                                        // trahit le clic malheureux.
                                        Text(String(format: localization.L(L10n.Updates.affirmedVersion),
                                                    row.affirmedVersion))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Text(String(format: localization.L(L10n.Updates.affirmedOnDisk),
                                                    row.manifestVersion))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(row.disagreesWithDisk
                                                             ? .orange : .secondary)
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
                                                .font(.system(size: 11))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .pointingHandCursor()
                                        .help(localization.L(L10n.Updates.affirmedOpenModHelp))
                                        Button {
                                            vm.revealAffirmedUpdate(uniqueId: row.uniqueId)
                                        } label: {
                                            Text(localization.L(L10n.Updates.affirmedReveal))
                                                .font(.system(size: 11))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .pointingHandCursor()
                                        .help(localization.L(L10n.Updates.affirmedRevealHelp))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        } label: {
                            Label(String(format: localization.L(L10n.Updates.affirmedTitle),
                                         Int64(vm.affirmedUpdates.count)),
                                  systemImage: "eye.slash")
                                .font(.system(size: 12))
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
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 2)
                                ForEach(vm.snoozedUpdates) { row in
                                    HStack(spacing: 8) {
                                        Text(row.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        Text(vm.snoozeExpiryLabel(for: row))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 8)
                                        Button {
                                            vm.unsnoozeUpdate(uniqueId: row.uniqueId)
                                        } label: {
                                            Text(localization.L(L10n.Updates.snoozedWake))
                                                .font(.system(size: 11))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .pointingHandCursor()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        } label: {
                            Label(String(format: localization.L(L10n.Updates.snoozedTitle),
                                         Int64(vm.snoozedUpdates.count)),
                                  systemImage: "moon.zzz.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)

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
