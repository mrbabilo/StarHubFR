import SwiftUI

/// Les deux confirmations de la timeline passent par **un seul** modificateur
/// `.alert`, porté par cette valeur.
///
/// Mesuré dans les deux sens : avec deux `.alert` sur la même vue, exactement
/// une des deux se présente. En API héritée c'était celle de l'extérieur (la
/// suppression confirmait, la restauration non) ; en API moderne l'autre (la
/// restauration confirmait, la suppression non). Changer d'API ne fait que
/// déplacer le perdant — seul un modificateur unique ferme la question.
private enum SaveTimelineConfirmation: Identifiable {
    case restore(SaveBackup)
    case delete(SaveBackup)

    var id: String {
        switch self {
        case .restore(let backup): return "restore-\(backup.id)"
        case .delete(let backup): return "delete-\(backup.id)"
        }
    }
}

struct SaveTimelineView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let save: SaveGameInfo
    
    @State private var backups: [SaveBackup] = []
    @State private var confirmation: SaveTimelineConfirmation?
    @State private var isHoveredReturn = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { vm.viewingSaveTimeline = nil }) {
                    HStack(spacing: AppDesign.Spacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(AppDesign.Font.rowTitle(.bold))
                        Text(vm.L(L10n.Saves.saves))
                    }
                    .foregroundColor(isHoveredReturn ? AppDesign.Color.accent : .secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(isHoveredReturn ? Color.accentColor.opacity(AppDesign.Opacity.light) : Color.clear)
                    .cornerRadius(AppDesign.Radius.md)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { isHoveredReturn = $0 }

                Spacer()

                Text(save.playerName)
                    .font(AppDesign.Font.headline)
                    .foregroundColor(.primary)

                Spacer()
                // Backup Button
                Button(action: {
                    Task {
                        if await vm.createBackup(info: save) {
                            loadBackups()
                        }
                    }
                }) {
                    HStack(spacing: AppDesign.Spacing.xs) {
                        if vm.isSaveOperationRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text(vm.L(L10n.Saves.backupLabel))
                    }
                    .font(AppDesign.Font.caption(.medium))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .foregroundColor(AppDesign.Color.accent)
                .padding(.trailing, 8)
                .disabled(vm.isSaveOperationRunning)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            if backups.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(vm.L(L10n.Saves.noBackups))
                        .multilineTextAlignment(.center)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(backups) { backup in
                            // Pas d'index comme id : la liste est triée par
                            // timestamp décroissant, un nouveau backup décale les
                            // index et le @State (note en cours) fuyait vers la
                            // rangée héritant de l'index → note sur le mauvais
                            // backup. SaveBackup est Identifiable. Audit 2026-08-05.
                            let isLast = backup.id == backups.last?.id
                            
                            BackupRow(
                                vm: vm,
                                backup: backup,
                                isLast: isLast,
                                onRestore: { confirmation = .restore(backup) },
                                onDelete: { confirmation = .delete(backup) }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            loadBackups()
        }
        // Un seul `.alert` : voir `SaveTimelineConfirmation`. `presenting:`
        // plutôt qu'une relecture du `@State` dans l'action — celle-ci
        // s'exécute après la fermeture, quand le binding a déjà remis la
        // valeur à `nil`, et l'alerte s'ouvrirait pour ne rien faire.
        .alert(confirmationTitle,
               isPresented: Binding(get: { confirmation != nil },
                                    set: { if !$0 { confirmation = nil } }),
               presenting: confirmation) { pending in
            switch pending {
            case .restore(let backup):
                Button(vm.L(L10n.Saves.restore), role: .destructive) {
                    Task { await vm.restoreBackup(backup: backup, info: save) }
                }
            case .delete(let backup):
                // La restauration est destructive et confirmait déjà ; la
                // suppression va à la corbeille, donc récupérable, mais le
                // clic « trash » mérite la même garde (audit 2026-08-05).
                Button(vm.L(L10n.Saves.deleteBackup), role: .destructive) {
                    Task {
                        if await vm.deleteBackup(backup) {
                            loadBackups()
                        }
                    }
                }
            }
            Button(vm.L(L10n.Saves.cancel), role: .cancel) {}
        } message: { pending in
            switch pending {
            case .restore:
                Text(vm.L(vm.isGameRunning() ? L10n.Saves.confirmRestoreMsgGameRunning
                                             : L10n.Saves.confirmRestoreMsg))
            case .delete:
                Text(vm.L(L10n.Saves.confirmDeleteBackupMsg))
            }
        }
        .sheet(item: $vm.backupToBranch) { backup in
            BranchBackupSheet(vm: vm, backup: backup)
        }
    }
    
    /// Le titre est hors des closures de `.alert` : il s'évalue au moment du
    /// rendu de la vue, pas de la présentation.
    private var confirmationTitle: String {
        switch confirmation {
        case .restore: return vm.L(L10n.Saves.confirmRestore)
        case .delete: return vm.L(L10n.Saves.confirmDeleteBackup)
        case nil: return ""
        }
    }

    private func loadBackups() {
        vm.listBackups(for: save) { fetched in
            backups = fetched
        }
    }
}

struct BackupRow: View {
    @ObservedObject var vm: StarHubTHViewModel
    let backup: SaveBackup
    let isLast: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void
    
    @State private var noteTag: String
    @State private var noteText: String
    @State private var isEditingNote = false
    
    let availableTags = ["", "⭐", "🏆", "🧪", "❤️", "💎", "📅"]
    
    init(vm: StarHubTHViewModel, backup: SaveBackup, isLast: Bool, onRestore: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.vm = vm
        self.backup = backup
        self.isLast = isLast
        self.onRestore = onRestore
        self.onDelete = onDelete
        
        let note = vm.getNote(for: backup.folderPath.lastPathComponent)
        _noteTag = State(initialValue: note.tag)
        _noteText = State(initialValue: note.note)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: AppDesign.Spacing.lg) {
            // Timeline line & dot
            VStack(spacing: 0) {
                Circle()
                    .fill(AppDesign.Color.accent)
                    .frame(width: 12, height: 12)
                    .shadow(color: Color.accentColor.opacity(AppDesign.Opacity.strong), radius: AppDesign.Shadow.badge.radius)
                    .padding(.top, 4)

                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(AppDesign.Opacity.medium))
                        .frame(width: 2)
                }
            }
            .frame(width: 20)

            // Content Card
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                HStack {
                    if !noteTag.isEmpty && !isEditingNote {
                        Text(noteTag)
                            .font(AppDesign.Font.rowTitle)
                    }
                    Text(relativeLabel)
                        .font(AppDesign.Font.rowTitle(.bold))
                    Spacer()
                    Text(formattedDate)
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                }

                if isEditingNote {
                    HStack {
                        Picker("", selection: $noteTag) {
                            ForEach(availableTags, id: \.self) { tag in
                                Text(tag.isEmpty ? "-" : tag).tag(tag)
                            }
                        }
                        .frame(width: 60)

                        TextField(vm.L(L10n.Saves.saveNote), text: $noteText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(vm.L(L10n.Profiles.save)) {
                            vm.setNote(for: backup.folderPath.lastPathComponent, tag: noteTag, note: noteText)
                            isEditingNote = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else if !noteText.isEmpty {
                    Text(noteText)
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 2)
                }

                HStack {
                    Text(vm.L(L10n.Saves.backupLabel))
                        .font(AppDesign.Font.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(AppDesign.Opacity.light))
                        .cornerRadius(AppDesign.Radius.sm)

                    Spacer()

                    // Actions. Crayon et corbeille : cible 18×18 — un glyph
                    // nu de 12 pt rend `.help` muet (a11y §7).
                    Button(action: { isEditingNote.toggle() }) {
                        Image(systemName: "pencil")
                            .font(AppDesign.Font.caption)
                            .frame(width: 18, height: 18)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.trailing, AppDesign.Spacing.xs)
                    .help(vm.L(L10n.Saves.editNoteHint))

                    Button(action: {
                        vm.backupToBranch = backup
                    }) {
                        HStack(spacing: AppDesign.Spacing.xs) {
                            Image(systemName: "arrow.triangle.branch")
                            Text(vm.L(L10n.Saves.branch))
                        }
                        .font(AppDesign.Font.caption(.medium))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    // La teinte « installé/actif » du dépôt, pas le vert
                    // système : la branche crée quelque chose de vivant,
                    // la même sémantique que l'installé (éprouvée deux
                    // thèmes).
                    .foregroundColor(AppDesign.Color.installed)
                    .padding(.trailing, AppDesign.Spacing.xs)

                    Button(action: onRestore) {
                        HStack(spacing: AppDesign.Spacing.xs) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                            Text(vm.L(L10n.Saves.restore))
                        }
                        .font(AppDesign.Font.caption(.medium))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .foregroundColor(AppDesign.Color.accent)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(AppDesign.Font.caption)
                            .frame(width: 18, height: 18)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppDesign.Color.error.opacity(AppDesign.Opacity.secondary))
                    .padding(.leading, AppDesign.Spacing.sm)
                    .help(vm.L(L10n.Saves.deleteBackupHint))
                }
            }
            .padding(AppDesign.Spacing.md)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(AppDesign.Radius.section)
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.Radius.section)
                    .stroke(Color.secondary.opacity(AppDesign.Opacity.light), lineWidth: 1)
            )
            .padding(.bottom, isLast ? 20 : AppDesign.Spacing.lg)
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: vm.currentLanguage)
        return formatter.string(from: backup.timestamp)
    }
    
    private var relativeLabel: String {
        let seconds = Date().timeIntervalSince(backup.timestamp)
        if seconds < 60 {
            return vm.L(L10n.Saves.relativeJustNow)
        }
        if seconds < 3600 {
            return String(format: vm.L(L10n.Saves.relativeMinutesAgo), Int64(seconds / 60))
        }
        if seconds < 86400 {
            return String(format: vm.L(L10n.Saves.relativeHoursAgo), Int64(seconds / 3600))
        }
        return String(format: vm.L(L10n.Saves.relativeDaysAgo), Int64(seconds / 86400))
    }
}
