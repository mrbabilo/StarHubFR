> [!IMPORTANT]
> For non-Thai users, please refer to the [English README](README_EN.md).

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/features_banner.png" alt="ฟีเจอร์หลัก" width="300">
</p>

*   **รันเกมได้ง่ายๆ**: เลือกรันเกมได้ทั้งโหมดปกติ (Vanilla) และโหมดผ่าน SMAPI สำหรับเล่นม็อด
*   **จัดการส่วนเสริม (Mods Manager)**: เปิด/ปิด ม็อดต่างๆ ได้อย่างง่ายดายผ่านหน้าตาแอปพลิเคชันที่สวยงาม ไม่ต้องเข้าไปย้ายไฟล์เอง
*   **จัดการเซฟเกม (Save Manager)**: 
    *   ดูรายละเอียดเซฟเกมทั้งหมด (จำนวนเงิน, เวลาในเกม, ฤดูกาล, รูปแบบฟาร์ม)
    *   ทำสำเนา (Duplicate) หรือลบเซฟเกม
    *   แก้ไขเงินและสถานะต่างๆ ของตัวละครเบื้องต้น
*   **บันทึกนักพัฒนา (Developer Logs)**: ติดตามการทำงานของ SMAPI ได้แบบเรียลไทม์ภายในแอป
*   **รองรับ 2 ภาษา (Bilingual Support)**: สลับภาษาในแอปได้ทันทีระหว่างภาษาอังกฤษ (English) และภาษาไทย (Thai)
*   **UI สไตล์ Native macOS**: หน้าตาแอปพลิเคชันที่สวยงาม ใช้งานง่าย ออกแบบมาให้กลมกลืนกับระบบ macOS อย่างสมบูรณ์แบบ

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/screenshots_banner.png" alt="ภาพตัวอย่างการใช้งาน" width="300">
</p>

| หน้าแรก (Home / Profile) | การตั้งค่าแอปพลิเคชัน (Settings) |
| :---: | :---: |
| <img src="screenshots/profile.png" width="400"> | <img src="screenshots/settings.png" width="400"> |

| การจัดการเซฟเกม (Saves) | การแก้ไขข้อมูลเซฟ (Save Editor) |
| :---: | :---: |
| <img src="screenshots/save.png" width="400"> | <img src="screenshots/save_edit.png" width="400"> |

| การจัดการส่วนเสริม (Mods Manager) | โปรไฟล์ม็อด (Mod Profiles) |
| :---: | :---: |
| <img src="screenshots/mods.png" width="400"> | <img src="screenshots/mod_profile.png" width="400"> |

| ศูนย์รวมม็อดแปลไทย (Thai Translation Hub) |
| :---: |
| <img src="screenshots/th_translation_hub.png" width="400"> |


<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/install_banner.png" alt="วิธีติดตั้ง" width="300">
</p>

1. **ดาวน์โหลดแอปพลิเคชัน**: โหลดไฟล์เวอร์ชันล่าสุดจากหน้า [Releases](../../releases)
2. **เปิดใช้งาน**: แตกไฟล์แล้วลาก `StarHubTH.app` ไปไว้ที่โฟลเดอร์ Applications แล้วดับเบิลคลิกเพื่อเปิดใช้งาน
3. **กำหนดโฟลเดอร์เกม**: ในครั้งแรกที่เปิด โปรแกรมจะค้นหาโฟลเดอร์เกมของ Steam อัตโนมัติ หากไม่พบ คุณสามารถเลือกโฟลเดอร์ตัวเกม (เช่น `/Applications/Stardew Valley.app/Contents/MacOS`) ได้ด้วยตัวเอง
4. **พร้อมลุย!**: จัดการม็อดหรือเซฟเกม แล้วกด **"เข้าสู่เกม"** จากแถบเมนูด้านซ้ายได้เลย!

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/developers_banner.png" alt="สำหรับนักพัฒนา" width="300">
</p>

แอปพลิเคชันนี้เขียนขึ้นด้วย **Swift** และ **SwiftUI** ผ่านโครงสร้างของแอปพลิเคชัน macOS แท้ๆ

### ความต้องการของระบบ (Requirements)
*   macOS 14.0 (Sonoma) หรือใหม่กว่า
*   Xcode 15.0 หรือใหม่กว่า (สำหรับการคอมไพล์ซอร์สโค้ด)

### วิธีการรันโปรเจกต์
คุณสามารถเปิดโปรเจกต์ผ่าน Xcode หรือใช้สคริปต์คอมไพล์ผ่าน Terminal:
```bash
python3 build_app.py
open StarHubTH.app
```

### การแพ็คแอปพลิเคชัน (Release)
หากต้องการบีบอัดแอปพลิเคชัน (.app) เป็นไฟล์ `.zip` สำหรับนำไปแจกจ่าย สามารถรันคำสั่ง:
```bash
python3 release.py
```
ไฟล์ Release จะถูกบันทึกไว้ในโฟลเดอร์ `bundles/` ครับ

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/credits_banner.png" alt="เครดิตและลิขสิทธิ์" width="300">
</p>

โปรเจกต์นี้เผยแพร่ภายใต้ [MIT License](LICENSE)สามารถนำไปดัดแปลงและพัฒนาต่อยอดได้ตามอิสระ
