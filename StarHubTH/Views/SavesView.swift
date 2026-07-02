import SwiftUI

struct SavesView: View {
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            HStack {
                Text("เซฟเกมทั้งหมด (\(vm.saves.count))")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(action: { vm.reloadSaves() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("รีเฟรช")
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            
            VStack(spacing: 0) {
                if vm.saves.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "cloud.bolt")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("ไม่พบไฟล์เซฟในเครื่อง\nลองเริ่มเล่นเกมสักครั้งก่อนนะ")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(vm.saves, id: \.id) { save in
                        Button(action: { vm.editingSave = save }) {
                            SaveRow(vm: vm, save: save)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

// MARK: - Save Row
struct SaveRow: View {
    @ObservedObject var vm: StarHubTHViewModel
    let save: SaveGameInfo
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Player info
            VStack(alignment: .leading, spacing: 4) {
                Text(save.playerName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                Text("\(save.farmName) Farm")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(width: 140, alignment: .leading)
            
            // In-game Date
            VStack(alignment: .leading, spacing: 4) {
                Text("ปีที่ \(save.year) - \(save.seasonName)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text("วันที่ \(save.day)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(width: 130, alignment: .leading)
            
            // Farm Type
            VStack(alignment: .leading, spacing: 4) {
                Text(save.farmTypeName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Money
            Text("\(save.money) G")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color.secondary.opacity(0.3))
                .padding(.leading, 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Editor View
struct SaveEditorView: View {
    @ObservedObject var vm: StarHubTHViewModel
    let save: SaveGameInfo
    
    @State private var name: String
    @State private var farm: String
    @State private var fav: String
    @State private var moneyStr: String
    @State private var maxHealthStr: String
    @State private var maxStaminaStr: String
    @State private var goldenWalnutsStr: String
    @State private var qiGemsStr: String
    @State private var clubCoinsStr: String
    
    init(vm: StarHubTHViewModel, save: SaveGameInfo) {
        self.vm = vm
        self.save = save
        _name = State(initialValue: save.playerName)
        _farm = State(initialValue: save.farmName)
        _fav = State(initialValue: save.favoriteThing)
        _moneyStr = State(initialValue: "\(save.money)")
        _maxHealthStr = State(initialValue: "\(save.maxHealth)")
        _maxStaminaStr = State(initialValue: "\(save.maxStamina)")
        _goldenWalnutsStr = State(initialValue: "\(save.goldenWalnuts)")
        _qiGemsStr = State(initialValue: "\(save.qiGems)")
        _clubCoinsStr = State(initialValue: "\(save.clubCoins)")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(save.playerName)
                    .font(.headline)
                Spacer()
                Button(action: { vm.editingSave = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            Divider()

            // Form
            ScrollView {
                VStack(spacing: 24) {
                    StandardSection(title: "ข้อมูลตัวละคร") {
                        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow { Text("ชื่อตัวละคร:"); TextField("", text: $name).textFieldStyle(.roundedBorder) }
                            GridRow { Text("ชื่อฟาร์ม:"); TextField("", text: $farm).textFieldStyle(.roundedBorder) }
                            GridRow { Text("สิ่งที่ชอบ:"); TextField("", text: $fav).textFieldStyle(.roundedBorder) }
                        }
                    }
                    
                    StandardSection(title: "ทรัพยากร") {
                        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow { Text("จำนวนเงิน (G):"); TextField("", text: $moneyStr).textFieldStyle(.roundedBorder) }
                            GridRow { Text("เหรียญกาสิโน:"); TextField("", text: $clubCoinsStr).textFieldStyle(.roundedBorder) }
                            GridRow { Text("วอลนัททองคำ:"); TextField("", text: $goldenWalnutsStr).textFieldStyle(.roundedBorder) }
                            GridRow { Text("เพชรฉี (Qi Gems):"); TextField("", text: $qiGemsStr).textFieldStyle(.roundedBorder) }
                        }
                    }
                    
                    StandardSection(title: "สถานะตัวละคร") {
                        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow { Text("พลังชีวิตสูงสุด:"); TextField("", text: $maxHealthStr).textFieldStyle(.roundedBorder) }
                            GridRow { Text("พลังงานสูงสุด:"); TextField("", text: $maxStaminaStr).textFieldStyle(.roundedBorder) }
                        }
                    }
                    StandardSection(title: "การจัดการไฟล์เซฟ") {
                        HStack(spacing: 16) {
                            Button(action: { vm.openSaveInFinder(info: save) }) {
                                Label("เปิดโฟลเดอร์", systemImage: "folder")
                                    .frame(maxWidth: .infinity)
                            }
                            
                            Button(action: {
                                vm.duplicateSave(info: save)
                                vm.editingSave = nil
                            }) {
                                Label("ทำสำเนา", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            
                            Button(action: {
                                vm.deleteSave(info: save)
                                vm.editingSave = nil
                            }) {
                                Label("ลบเซฟ", systemImage: "trash")
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("ระบบจะทำการสร้างโฟลเดอร์แบ็คอัพไว้ข้างๆ ไฟล์เดิมอัตโนมัติ")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                
                Button("บันทึกการเปลี่ยนแปลง") {
                    let newMoney = Int(moneyStr) ?? save.money
                    let newHealth = Int(maxHealthStr) ?? save.maxHealth
                    let newStam = Int(maxStaminaStr) ?? save.maxStamina
                    let newWalnuts = Int(goldenWalnutsStr) ?? save.goldenWalnuts
                    let newQi = Int(qiGemsStr) ?? save.qiGems
                    let newClub = Int(clubCoinsStr) ?? save.clubCoins
                    
                    vm.editSave(info: save, newName: name, newFarm: farm, newFav: fav, newMoney: newMoney, newMaxHealth: newHealth, newMaxStamina: newStam, newGoldenWalnuts: newWalnuts, newQiGems: newQi, newClubCoins: newClub)
                    vm.editingSave = nil
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(BorderedProminentButtonStyle())
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
