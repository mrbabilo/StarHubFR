import SwiftUI

struct LogsView: View {
    @ObservedObject var vm: StarHubTHViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                
                // ── Logs Section ──
                StandardSection(
                    title: "ประวัติการทำงาน (System Logs)",
                    footer: "ประวัติสถานะและคำแนะนำสิทธิ์การเปิดใช้แอปในเซสชันปัจจุบัน"
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("บันทึกการทำงานของระบบ")
                                .font(.system(size: 13))
                            Spacer()
                            Button("ล้างประวัติ") {
                                vm.logOutput = ""
                            }
                        }
                        
                        Divider()
                        
                        // Log Console
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading) {
                                    if vm.logOutput.isEmpty {
                                        Text("ไม่มีประวัติการบันทึกในเซสชันนี้")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                            .italic()
                                    } else {
                                        Text(vm.logOutput)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    
                                    Spacer().frame(height: 1).id("LogBottom")
                                }
                                .padding(12)
                            }
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(6)
                            .frame(minHeight: 200, maxHeight: 400)
                            .onChange(of: vm.logOutput) { _ in
                                withAnimation {
                                    proxy.scrollTo("LogBottom", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                // ── Troubleshooting tip card ──
                StandardSection(title: "คำแนะนำสำหรับระบบ macOS") {
                    Text("1. หากรันเกมไม่ได้เนื่องจาก 'Developer cannot be verified' ให้ไปที่ System Settings > Privacy & Security แล้วกดปุ่ม 'Allow Anyway' ข้างชื่อ SMAPI หรือ Stardew Valley\n2. ตัวจัดการม็อดจะสร้างโฟลเดอร์ชื่อ 'Mods_disabled' ไว้ในโฟลเดอร์เกม เพื่อเก็บม็อดที่คุณสั่งปิดใช้งานชั่วคราว")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
            }
            .padding(40)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
