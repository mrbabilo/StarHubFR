import SwiftUI

struct SaveTimelineView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let save: SaveGameInfo
    
    @State private var backups: [SaveBackup] = []
    @State private var backupToRestore: SaveBackup?
    @State private var showRestoreConfirm = false
    @State private var isHoveredReturn = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { vm.viewingSaveTimeline = nil }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text(vm.L(L10n.Saves.saves))
                    }
                    .foregroundColor(isHoveredReturn ? .accentColor : .secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(isHoveredReturn ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { isHoveredReturn = $0 }
                
                Spacer()
                
                Text(save.playerName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                // Backup Button
                Button(action: {
                    if vm.createBackup(info: save) {
                        loadBackups()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(vm.L(L10n.Saves.backupLabel))
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .padding(.trailing, 8)
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
                        ForEach(backups.indices, id: \.self) { index in
                            let backup = backups[index]
                            let isLast = index == backups.count - 1
                            
                            BackupRow(
                                vm: vm,
                                backup: backup,
                                isLast: isLast,
                                onRestore: {
                                    backupToRestore = backup
                                    showRestoreConfirm = true
                                },
                                onDelete: {
                                    if vm.deleteBackup(backup) {
                                        loadBackups()
                                    }
                                }
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
        .alert(isPresented: $showRestoreConfirm) {
            Alert(
                title: Text(vm.L(L10n.Saves.confirmRestore)),
                message: Text(vm.L(L10n.Saves.confirmRestoreMsg)),
                primaryButton: .destructive(Text(vm.L(L10n.Saves.restore))) {
                    if let b = backupToRestore {
                        vm.restoreBackup(backup: b, info: save)
                    }
                },
                secondaryButton: .cancel(Text(vm.L(L10n.Main.ok)))
            )
        }
        .sheet(item: $vm.backupToBranch) { backup in
            BranchBackupSheet(vm: vm, backup: backup)
        }
    }
    
    private func loadBackups() {
        backups = vm.listBackups(for: save)
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
        HStack(alignment: .top, spacing: 16) {
            // Timeline line & dot
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 3)
                    .padding(.top, 4)
                
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 2)
                }
            }
            .frame(width: 20)
            
            // Content Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if !noteTag.isEmpty && !isEditingNote {
                        Text(noteTag)
                            .font(.system(size: 14))
                    }
                    Text(backup.relativeLabel)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text(backup.formattedDate)
                        .font(.system(size: 12))
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
                        
                        Button("Save") {
                            vm.setNote(for: backup.folderPath.lastPathComponent, tag: noteTag, note: noteText)
                            isEditingNote = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else if !noteText.isEmpty {
                    Text(noteText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 2)
                }
                
                HStack {
                    Text(vm.L(L10n.Saves.backupLabel))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    // Actions
                    Button(action: { isEditingNote.toggle() }) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 4)
                    
                    Button(action: {
                        vm.backupToBranch = backup
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                            Text("แตกสาขา")
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.green)
                    .padding(.trailing, 4)
                    
                    Button(action: onRestore) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                            Text(vm.L(L10n.Saves.restore))
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red.opacity(0.7))
                    .padding(.leading, 8)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .padding(.bottom, isLast ? 20 : 16)
        }
    }
}
