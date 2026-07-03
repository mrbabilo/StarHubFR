import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    
    @AppStorage("launchProfile") private var launchProfile: String = "SMAPI"
    @AppStorage("closeAfterLaunch") private var closeAfterLaunch: Bool = false
    @AppStorage("appColorScheme") private var appColorScheme: String = "System"
    @AppStorage("showDeveloperLogs") private var showDeveloperLogs: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                
                // ── Language ──
                StandardSection(
                    title: "ภาษาของแอป (Language)"
                ) {
                    HStack {
                        Text("เลือกภาษา")
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: $vm.currentLanguage) {
                            Text("ภาษาไทย").tag("th")
                            Text("English").tag("en")
                            Text("日本語").tag("ja")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 150)
                        
                        Image(systemName: "info.circle")
                            .foregroundColor(.clear)
                            .font(.system(size: 14))
                    }
                }
                
                // ── Launch Options ──
                StandardSection(
                    title: "การเปิดเกม (Launch Options)",
                    footer: "หากเปิดเกมไม่สำเร็จ ลองเลือกเป็นตัวเกมดั้งเดิม (Vanilla) ดูนะ สำหรับข้อมูลเพิ่มเติม โปรดดูที่: [wiki.stardewvalley.net/Modding](https://stardewvalleywiki.com/Modding)"
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("โหมดเข้าเกมเริ่มต้น")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $launchProfile) {
                                Text("เล่นผ่าน SMAPI (ใช้ม็อด)").tag("SMAPI")
                                Text("ตัวเกมดั้งเดิม (Vanilla)").tag("Vanilla")
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 240)
                            
                            InfoPopoverButton(text: "โหมดการเปิดเกมครั้งถัดไป")
                        }
                        
                        Divider().padding(.leading, 0)
                        
                        HStack {
                            Text("ปิด Launcher อัตโนมัติหลังจากเกมเปิดขึ้นมา")
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $closeAfterLaunch)
                                .toggleStyle(StardewToggleStyle())
                                .labelsHidden()
                            
                            InfoPopoverButton(text: "ประหยัดทรัพยากรเครื่อง")
                        }
                    }
                }
                
                // ── Directory Config ──
                StandardSection(
                    title: "สำรองข้อมูล (Backup)",
                    footer: "สร้างไฟล์ Zip สำหรับข้อมูลสำคัญไปไว้ที่ Desktop ของคุณ การสำรองข้อมูลจะช่วยป้องกันไฟล์เสียหายระหว่างการอัปเดต"
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("สำรองไฟล์เซฟเกม")
                                .font(.system(size: 13))
                            Spacer()
                            Button(action: {
                                vm.backupAllSaves()
                            }) {
                                Text("Backup เซฟเกม").frame(maxWidth: .infinity)
                            }
                            .frame(width: 140)
                            
                            InfoPopoverButton(text: "บีบอัดโฟลเดอร์ Saves เป็นไฟล์ Zip")
                        }
                        
                        Divider().padding(.leading, 0)
                        
                        HStack {
                            Text("สำรองโฟลเดอร์ม็อด")
                                .font(.system(size: 13))
                            Spacer()
                            Button(action: {
                                vm.backupAllMods()
                            }) {
                                Text("Backup ม็อด").frame(maxWidth: .infinity)
                            }
                            .frame(width: 140)
                            
                            InfoPopoverButton(text: "บีบอัดโฟลเดอร์ Mods เป็นไฟล์ Zip")
                        }
                    }
                }
                
                // ── Appearance ──
                StandardSection(
                    title: "การแสดงผล (Appearance)",
                    footer: "หน้าต่างนักพัฒนา (Developer Logs) มีไว้สำหรับตรวจสอบการทำงานของ SMAPI เวลามีม็อดเกิดปัญหาสามารถคัดลอกข้อความไปสอบถามผู้พัฒนาได้"
                ) {
                    VStack(alignment: .leading, spacing: 16) {

                        HStack {
                            Text("ธีมของแอป")
                                .font(.system(size: 13))
                            Spacer()
                            Picker("", selection: $appColorScheme) {
                                Text("ตามระบบ (System)").tag("System")
                                Text("สว่าง (Light)").tag("Light")
                                Text("มืด (Dark)").tag("Dark")
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .fixedSize(horizontal: true, vertical: false)
                            
                            Image(systemName: "info.circle")
                                .foregroundColor(.clear)
                                .font(.system(size: 14))
                        }
                        
                        Divider().padding(.leading, 0)
                        
                        HStack {
                            Text("แสดงหน้าต่างนักพัฒนา (Developer Logs)")
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: $showDeveloperLogs)
                                .toggleStyle(StardewToggleStyle())
                                .labelsHidden()
                            
                            InfoPopoverButton(text: "เครื่องมือแก้ไขปัญหา สำหรับดู Error Log")
                        }
                    }
                }
                
                // ── Management ──
                StandardSection(
                    title: "การจัดการ (Management)",
                    footer: "ลบโฟลเดอร์ Mods_disabled เพื่อคืนพื้นที่จัดเก็บ หากคุณไม่ต้องการไฟล์ม็อดที่ปิดการใช้งานแล้ว"
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("โฟลเดอร์เซฟเกม")
                                .font(.system(size: 13))
                            Spacer()
                            Button(action: {
                                vm.openSavesFolder()
                            }) {
                                Text("เปิดโฟลเดอร์").frame(maxWidth: .infinity)
                            }
                            .frame(width: 140)
                            
                            InfoPopoverButton(text: "เปิดโฟลเดอร์ใน Finder")
                        }
                        
                        Divider().padding(.leading, 0)
                        
                        HStack {
                            Text("ล้างไฟล์ม็อดที่ถูกปิดใช้งาน")
                                .font(.system(size: 13))
                            Spacer()
                            Button(action: {
                                vm.cleanDisabledMods()
                            }) {
                                Text("ลบไฟล์ขยะม็อด").frame(maxWidth: .infinity)
                            }
                            .foregroundColor(.red)
                            .frame(width: 140)
                            
                            InfoPopoverButton(text: "ลบโฟลเดอร์ Mods_disabled ถาวร", color: .red.opacity(0.8))
                        }
                    }
                }
            }
            .padding(40)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
