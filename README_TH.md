> [!IMPORTANT]
> For non-Thai users, please refer to the [English README](README_EN.md) or [French README](README.md).

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white" alt="Swift"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/SwiftUI-0288D1?logo=swift&logoColor=white" alt="SwiftUI"></a>
  <a href="https://www.python.org"><img src="https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white" alt="Python"></a>
  <a href="#"><img src="https://img.shields.io/badge/Platform-macOS%2014%2B-000000?logo=apple&logoColor=white" alt="macOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow" alt="MIT License"></a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/features_banner.png" alt="ฟีเจอร์หลัก" width="300">
</p>

*   **รันเกมได้ง่ายๆ**: เลือกรันเกมได้ทั้งโหมดปกติ (Vanilla) และโหมดผ่าน SMAPI สำหรับเล่นม็อด
*   **จัดการส่วนเสริม (Mods Manager)**: เปิด/ปิด ม็อดต่างๆ ได้อย่างง่ายดายผ่านหน้าตาแอปพลิเคชันที่สวยงาม ไม่ต้องเข้าไปย้ายไฟล์เอง
*   **ติดตั้งม็อดด้วยการลากวาง (Drag & Drop Installer)**: ลากไฟล์ `.zip` มาวางในแอปเพื่อติดตั้งม็อดได้โดยตรง ตรวจจับโครงสร้างอัตโนมัติ (ม็อดเดียวหรือแพ็คหลายม็อด) ตรวจสอบความปลอดภัย (กัน zip-bomb, < 500 MB) พร้อมแสดงตัวอย่างความขัดแย้งและแนะนำม็อดที่ขาดหายไป
*   **โปรไฟล์ม็อด (Mod Profiles)**: จัดกลุ่มม็อดเป็นหลายโปรไฟล์และสลับใช้งานได้ทันทีในคลิกเดียว
*   **ศูนย์รวมการแปลภาษาไทย (Thai Translation Hub)**: หน้าเฉพาะที่รวมม็อดแปลภาษาไทยทั้งหมด — เรียกดู ตรวจสอบสถานะ ดาวน์โหลด และติดตามอัปเดตในที่เดียว
*   **ตรวจสอบอัปเดต Nexus Mods**: ตรวจสอบอัปเดตม็อดด้วยตนเองผ่าน Nexus Mods API คีย์ API เก็บใน Keychain ของ macOS อย่างปลอดภัย ตรวจจับอัปเดตแม้เวอร์ชันเดียวกัน (เปรียบเทียบวันที่อัปโหลด)
*   **สำรองข้อมูลม็อด (Mod Backups)**:
    *   *สำรองการติดตั้ง*: สำรองข้อมูลอัตโนมัติก่อนเขียนทับม็อดเดิม พร้อมนโยบายเก็บรักษาแบบไฮบริด (5 ล่าสุด + ≤30 วัน + 1 รายเดือนหลังจากนั้น)
    *   *สำรองการตั้งค่า*: สำรองและกู้คืนไฟล์ `config.json`/`fr.json` ของม็อดที่เปิดใช้งาน
*   **ตัวแก้ไขการตั้งค่าม็อด (Mod Config Editor)**: แก้ไขไฟล์ `config.json` ของม็อดได้โดยตรงในแอป ผ่านตัวแก้ไขแบบภาพเป็นลำดับชั้น (โครงสร้างการตั้งค่าที่ค้นหาได้) หรือตัวแก้ไข JSON แบบดิบพร้อมเลขบรรทัดและการตรวจสอบความถูกต้องแบบเรียลไทม์ พร้อมปุ่มรีเซ็ตและกู้คืนจากไฟล์สำรองในเครื่อง
*   **รายการม็อดขั้นสูง (Advanced Mod List)**: กรองตามหมวดหมู่ แบ่งหน้า (15 ม็อด/หน้าพร้อมข้ามหน้าโดยตรง) กรองม็อดที่ไม่มีหมวดหมู่ กรอง "มีการตั้งค่า" (เฉพาะม็อดที่ตั้งค่าได้) เรียงตามชื่อ (A-Z/Z-A) ผู้สร้าง เวอร์ชัน หรือลำดับการเปิดใช้งาน รองรับรูปภาพคำอธิบาย และมีไอคอนรูปเฟืองบนม็อดที่ตั้งค่าได้เพื่อเปิดตัวแก้ไขการตั้งค่าโดยตรง
*   **จัดการเซฟเกม (Save Manager)**: 
    *   ดูรายละเอียดเซฟเกมทั้งหมด (จำนวนเงิน, เวลาในเกม, ฤดูกาล, รูปแบบฟาร์ม)
    *   ทำสำเนา (Duplicate) หรือลบเซฟเกม
    *   แก้ไขเงินและสถานะต่างๆ ของตัวละครเบื้องต้น
*   **บันทึกนักพัฒนา (Developer Logs)**: ติดตามการทำงานของ SMAPI ได้แบบเรียลไทม์ภายในแอป
*   **ดูบันทึกการเปลี่ยนแปลงในแอป (In-App Changelog)**: ดูประวัติเวอร์ชัน (`CHANGELOG.md`) ได้โดยตรงจากแถบเมนูด้านข้างของแอป
*   **รองรับ 3 ภาษา (Multilingual Support)**: สลับภาษาในแอปได้ทันทีระหว่างภาษาฝรั่งเศส (French), ภาษาอังกฤษ (English) และภาษาไทย (Thai)
*   **UI สไตล์ Native macOS**: หน้าตาแอปพลิเคชันที่สวยงาม ใช้งานง่าย ออกแบบมาให้กลมกลืนกับระบบ macOS อย่างสมบูรณ์แบบ

<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/screenshots_banner.png" alt="ภาพตัวอย่างการใช้งาน" width="300">
</p>

|   |   |
| :---: | :---: |
| <img src="screenshots/1.png" width="400"> | <img src="screenshots/2.png" width="400"> |
| <img src="screenshots/3.png" width="400"> | <img src="screenshots/4.png" width="400"> |
| <img src="screenshots/5.png" width="400"> | <img src="screenshots/6.png" width="400"> |
| <img src="screenshots/7.png" width="400"> | <img src="screenshots/8.png" width="400"> |
| <img src="screenshots/9.png" width="400"> | <img src="screenshots/10.png" width="400"> |
| <img src="screenshots/11.png" width="400"> | <img src="screenshots/12.png" width="400"> |


<p align="center">
  <img src="https://raw.githubusercontent.com/AppleBoiy/stardew-thai-translations/main/banners/install_banner.png" alt="วิธีติดตั้ง" width="300">
</p>

### ความต้องการขั้นต่ำของระบบ
*   **ระบบปฏิบัติการ**: macOS 14.0 (Sonoma) หรือใหม่กว่า
*   **Stardew Valley**: เกมที่ติดตั้งบน macOS (เวอร์ชัน Steam หรือ GOG)
*   **ทางเลือก**: [SMAPI](https://smapi.io/) สำหรับเล่นม็อด

### ขั้นตอนการติดตั้ง
1. **ดาวน์โหลดแอปพลิเคชัน**: โหลดไฟล์เวอร์ชันล่าสุดจากหน้า [Releases](../../releases)
2. **เปิดใช้งาน**: แตกไฟล์แล้วลาก `StarHubTH.app` ไปไว้ที่โฟลเดอร์ Applications แล้วดับเบิลคลิกเพื่อเปิดใช้งาน
3. **กำหนดโฟลเดอร์เกม**: ในครั้งแรกที่เปิด โปรแกรมจะค้นหาโฟลเดอร์เกมของ Steam อัตโนมัติ หากไม่พบ คุณสามารถเลือกโฟลเดอร์ตัวเกม (เช่น `/Applications/Stardew Valley.app/Contents/MacOS`) ได้ด้วยตัวเอง
4. **พร้อมลุย!**: จัดการม็อดหรือเซฟเกม แล้วกด **"เข้าสู่เกม"** ที่หน้าหลักได้เลย!

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
