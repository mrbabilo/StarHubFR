import SwiftUI

struct SavesView: View {
    @ObservedObject var vm: StarHubTHViewModel

    var body: some View {
        Form {
            Section {
                if vm.saves.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "cloud.bolt")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("ไม่พบไฟล์เซฟในเครื่อง\nลองเริ่มเล่นเกมสักครั้งก่อนนะ")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(vm.saves, id: \.id) { save in
                        Button(action: { vm.editingSave = save }) {
                            SaveRow(vm: vm, save: save)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                HStack {
                    Text("เซฟเกมทั้งหมด (\(vm.saves.count))")
                    Spacer()
                    Button(action: { vm.reloadSaves() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("รีเฟรชข้อมูล")
                }
            } footer: {
                Text("ระบบจะดึงข้อมูลเซฟเกมจากโฟลเดอร์เกมของคุณโดยอัตโนมัติ")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Save Row
struct SaveRow: View {
    @ObservedObject var vm: StarHubTHViewModel
    let save: SaveGameInfo
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Circular Avatar/Icon
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(Color.accentColor.opacity(0.8))
                    .frame(width: 32, height: 32)
            }
            .frame(width: 32, height: 32)
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(save.playerName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                let format = vm.localizedString(for: "%@ Farm • ปีที่ %lld %@ วันที่ %lld • %@ G")
                let moneyStr = NumberFormatter.localizedString(from: NSNumber(value: save.money), number: .decimal)
                let formattedStr = String(format: format, save.farmName, save.year, vm.localizedString(for: save.seasonName), save.day, moneyStr)
                Text(formattedStr)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Info Icon
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
                .font(.system(size: 16))
                .padding(.trailing, 4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
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
            Form {
                Section("ข้อมูลตัวละคร") {
                    TextField("ชื่อตัวละคร", text: $name)
                    TextField("ชื่อฟาร์ม", text: $farm)
                    TextField("สิ่งที่ชอบ", text: $fav)
                }
                
                Section("ทรัพยากร") {
                    TextField("จำนวนเงิน (G)", text: $moneyStr)
                    TextField("เหรียญกาสิโน", text: $clubCoinsStr)
                    TextField("วอลนัททองคำ", text: $goldenWalnutsStr)
                    TextField("เพชรฉี (Qi Gems)", text: $qiGemsStr)
                }
                
                Section("สถานะตัวละคร") {
                    TextField("พลังชีวิตสูงสุด", text: $maxHealthStr)
                    TextField("พลังงานสูงสุด", text: $maxStaminaStr)
                }
                
                Section("การจัดการไฟล์เซฟ") {
                    HStack {
                        Button("เปิดโฟลเดอร์") { vm.openSaveInFinder(info: save) }
                        Button("ทำสำเนา") { vm.duplicateSave(info: save); vm.editingSave = nil }
                        Spacer()
                        Button("ลบเซฟ") { vm.deleteSave(info: save); vm.editingSave = nil }
                            .foregroundColor(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
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
