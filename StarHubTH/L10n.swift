// L10n.swift
// Typed localization keys for StarHubTH.
// All raw values must exactly match keys in assets/*/Localizable.strings.
// Usage: vm.L(L10n.Mods.enabled)
// Never pass a raw Thai/English string to vm.localizedString — use this enum instead.

enum L10n {

    // MARK: - MainView / Sidebar
    enum Main {
        static let account          = "บัญชีผู้ใช้"
        static let gameManagement   = "จัดการเกม"
        static let system           = "ระบบ"
        static let online           = "ออนไลน์"
        static let readyToPlay      = "พร้อมลุย!"
        static let launchingGame    = "กำลังเปิดเกม..."
        static let launchGame       = "เข้าสู่เกม"
        static let alert            = "แจ้งเตือน"
        static let ok               = "ตกลง"
        static let home             = "หน้าแรก"
        static let search           = "ค้นหา"
        static let systemAlerts     = "แจ้งเตือนระบบ"
        static let softwareUpdate   = "อัปเดตซอฟต์แวร์"
    }

    // MARK: - HomeView
    enum Home {
        static let appInfo              = "ข้อมูลแอป"
        static let developer            = "ผู้พัฒนา"
        static let modManager           = "ตัวจัดการม็อด"
        static let notInstalled         = "ไม่ได้ติดตั้ง"
        static let installedMods        = "ม็อดที่ติดตั้ง"
        static let gameFolder           = "โฟลเดอร์เกม"
        static let gamePath             = "ที่ตั้งไฟล์เกม"
        static let notSet               = "ยังไม่ได้กำหนด"
        static let selectFolder         = "เลือกโฟลเดอร์..."
        static let smapiManager         = "ระบบจัดการม็อด"
        static let smapiStatus          = "สถานะ SMAPI"
        static let smapiInstalled       = "ติดตั้งแล้ว (v%@)"
        static let installSmapi         = "ติดตั้ง SMAPI"
        static let uninstall            = "ถอนการติดตั้ง"
        static let coreExtensions       = "ส่วนเสริมหลัก"
        static let installedAndEnabled  = "ติดตั้งและเปิดใช้งานแล้ว"
        static let notInstalledOrDisabled = "ไม่ได้ติดตั้ง หรือปิดใช้งานอยู่"
        static let installedButDisabled = "ติดตั้งแล้ว แต่ปิดใช้งานอยู่"
        static let itemCount            = "%lld รายการ"
        static let versionString        = "Stardew Valley v1.6 • StarHubTH v%@"
        static let smapiNotInstalled    = "ยังไม่ได้ติดตั้ง"
    }

    // MARK: - SavesView
    enum Saves {
        static let noSaves              = "ไม่พบไฟล์เซฟในเครื่อง\nลองเริ่มเล่นเกมสักครั้งก่อนนะ"
        static let allSaves             = "เซฟเกมทั้งหมด (%lld)"
        static let autoFetch            = "ระบบจะดึงข้อมูลเซฟเกมจากโฟลเดอร์เกมของคุณโดยอัตโนมัติ"
        static let farmFormat           = "%@ Farm • ปีที่ %lld %@ วันที่ %lld • %@ G"
        static let backupNote           = "ระบบจะทำการสร้างโฟลเดอร์แบ็คอัพไว้ข้างๆ ไฟล์เดิมอัตโนมัติ"
        static let lastPlayed           = "เล่นล่าสุดเมื่อ %@"
        static let spring               = "ฤดูใบไม้ผลิ"
        static let summer               = "ฤดูร้อน"
        static let fall                 = "ฤดูใบไม้ร่วง"
        static let winter               = "ฤดูหนาว"
        static let characterInfo        = "ข้อมูลตัวละคร"
        static let characterName        = "ชื่อตัวละคร"
        static let farmName             = "ชื่อฟาร์ม"
        static let favoriteThing        = "สิ่งที่ชอบ"
        static let resources            = "ทรัพยากร"
        static let money                = "จำนวนเงิน (G)"
        static let casinoCoins          = "เหรียญกาสิโน"
        static let goldenWalnuts        = "วอลนัททองคำ"
        static let qiGems               = "เพชรฉี (Qi Gems)"
        static let characterStats       = "สถานะตัวละคร"
        static let maxHealth            = "พลังชีวิตสูงสุด"
        static let maxStamina           = "พลังงานสูงสุด"
        static let saveManagement       = "การจัดการไฟล์เซฟ"
        static let duplicate            = "ทำสำเนา"
        static let deleteSave           = "ลบเซฟ"
        static let saveChanges          = "บันทึกการเปลี่ยนแปลง"
        static let saves                = "เซฟเกม"
        static let openFolder           = "เปิดโฟลเดอร์"
        static let timeline             = "ประวัติ Backup"
        static let restore              = "กู้คืน"
        static let backupLabel          = "แบ็คอัพ"
        static let noBackups            = "ยังไม่มีการแบ็คอัพเซฟนี้"
        static let notes                = "บันทึกช่วยจำ"
        static let tag                  = "ป้ายกำกับ"
        static let saveNote             = "พิมพ์บันทึกย่อสำหรับเซฟนี้..."
        static let confirmRestore       = "ยืนยันการกู้คืนเซฟ"
        static let confirmRestoreMsg    = "คุณต้องการกู้คืนเซฟนี้หรือไม่?\nข้อมูลเซฟปัจจุบันจะถูกเก็บแบ็คอัพไว้ก่อนการกู้คืน"
    }

    // MARK: - ModListView
    enum Mods {
        static let apiOffline           = "API ออฟไลน์"
        static let apiNormal            = "API ทำงานปกติ"
        static let noModsInstalled      = "ไม่พบส่วนเสริมที่ติดตั้ง\nโปรดตรวจสอบโฟลเดอร์เกม"
        static let noModFound           = "ไม่พบส่วนเสริม \"%@\""
        static let searchMods           = "ค้นหาส่วนเสริม..."
        static let enabled              = "เปิดใช้งานแล้ว"
        static let disabled             = "ปิดการใช้งาน"
        static let openFolder           = "เปิดโฟลเดอร์"
        static let openInFinder         = "เปิดใน Finder"
        static let viewOnNexus          = "ดูบน Nexus Mods"
        static let viewDetailsOnNexus   = "ดูรายละเอียดบน Nexus Mods"
        static let mods                 = "ส่วนเสริม"
    }

    // MARK: - LogsView
    enum Logs {
        static let systemLogs           = "บันทึกการทำงานของระบบ"
        static let noLogs               = "ไม่มีประวัติการบันทึกในเซสชันนี้"
        static let macOSTips            = "คำแนะนำสำหรับระบบ macOS"
        static let macOSTipsContent     = "คำแนะนำสำหรับผู้ใช้ macOS"
        static let history              = "ประวัติการทำงาน"
        static let historySubtitle      = "ประวัติสถานะและคำแนะนำสิทธิ์การเปิดใช้แอปในเซสชันปัจจุบัน"
        static let clearLogs            = "ล้างประวัติ"
        static let logs                 = "บันทึกระบบ"
        static let developer            = "นักพัฒนา"
        static let filterAll            = "ทั้งหมด"
        static let autoScrollHint       = "เลื่อนอัตโนมัติไปล่างสุด"
        static let copyAll              = "คัดลอก log ทั้งหมดที่แสดงอยู่"
        static let searchPlaceholder    = "ค้นหาใน log..."
        static let entryCount           = "%d / %d รายการ"
        static let refreshHint          = "โหลด SMAPI-latest.txt ใหม่"
    }

    // MARK: - SettingsView
    enum Settings {
        static let launchOptions        = "การเปิดเกม"
        static let backup               = "สำรองข้อมูล"
        static let appearance           = "การแสดงผล"
        static let management           = "การจัดการ"
        static let defaultLaunchMode    = "โหมดเข้าเกมเริ่มต้น"
        static let playSMAPI            = "เล่นผ่าน SMAPI (ใช้ม็อด)"
        static let vanillaGame          = "ตัวเกมดั้งเดิม"
        static let closeLauncher        = "ปิด Launcher อัตโนมัติหลังจากเกมเปิดขึ้นมา"
        static let backupSaves          = "สำรองไฟล์เซฟเกม"
        static let backupSavesButton    = "Backup เซฟเกม"
        static let backupMods           = "สำรองโฟลเดอร์ม็อด"
        static let backupModsButton     = "Backup ม็อด"
        static let appLanguage          = "ภาษาของแอป"
        static let selectLanguage       = "เลือกภาษา"
        static let appTheme             = "ธีมของแอป"
        static let themeSystem          = "ตามระบบ"
        static let themeLight           = "สว่าง"
        static let themeDark            = "มืด"
        static let showDevLogs          = "แสดงหน้าต่างนักพัฒนา"
        static let savesFolder          = "โฟลเดอร์เซฟเกม"
        static let openFolder           = "เปิดโฟลเดอร์"
        static let clearDisabledMods    = "ล้างไฟล์ม็อดที่ถูกปิดใช้งาน"
        static let deleteJunkMods       = "ลบไฟล์ขยะม็อด"
        static let settings             = "ตั้งค่าระบบ"
        static let gameDirNotSet        = "กรุณาระบุโฟลเดอร์เกมก่อน"

        // Mod behavior
        static let modBehavior          = "การจัดการม็อด"
        static let chainToggle          = "ปิด/เปิดม็อดที่เกี่ยวข้องอัตโนมัติ"
        static let chainToggleHint      = "เมื่อเปิดม็อด จะเปิด Dependencies พร้อมกันอัตโนมัติ และเมื่อปิดม็อด จะปิดม็อดที่อาศัยม็อดนี้ด้วย"

        // Info popover hints
        static let hintNextLaunchMode   = "โหมดการเปิดเกมครั้งถัดไป"
        static let hintSaveResources    = "ประหยัดทรัพยากรเครื่อง"
        static let hintCompressSaves    = "บีบอัดโฟลเดอร์ Saves เป็นไฟล์ Zip"
        static let hintCompressMods     = "บีบอัดโฟลเดอร์ Mods เป็นไฟล์ Zip"
        static let hintDevLogs          = "เครื่องมือแก้ไขปัญหา สำหรับดู Error Log"

        // Footer strings
        static let footerLaunch         = "หากเปิดเกมไม่สำเร็จ ลองเลือกเป็นตัวเกมดั้งเดิม (Vanilla) ดูนะ สำหรับข้อมูลเพิ่มเติม โปรดดูที่: [wiki.stardewvalley.net/Modding](https://stardewvalleywiki.com/Modding)"
        static let footerBackup         = "สร้างไฟล์ Zip สำหรับข้อมูลสำคัญไปไว้ที่ Desktop ของคุณ การสำรองข้อมูลจะช่วยป้องกันไฟล์เสียหายระหว่างการอัปเดต"
        static let footerAppearance     = "หน้าต่างนักพัฒนา (Developer Logs) มีไว้สำหรับตรวจสอบการทำงานของ SMAPI เวลามีม็อดเกิดปัญหาสามารถคัดลอกข้อความไปสอบถามผู้พัฒนาได้"
        static let footerManagement     = "ลบโฟลเดอร์ Mods_disabled เพื่อคืนพื้นที่จัดเก็บ หากคุณไม่ต้องการไฟล์ม็อดที่ปิดการใช้งานแล้ว"
    }

    // MARK: - SmapiInstaller
    enum Smapi {
        static let downloading          = "กำลังเริ่มดาวน์โหลด SMAPI..."
        static let downloadFailed       = "ดาวน์โหลดล้มเหลว: %@"
        static let downloadedFileNotFound = "ไม่พบข้อมูลไฟล์ที่ดาวน์โหลด"
        static let extracting           = "ดาวน์โหลดสำเร็จ กำลังคลายไฟล์..."
        static let preparing            = "เตรียมติดตั้ง SMAPI ลงในตัวเกม..."
        static let payloadNotFound      = "ไม่พบไฟล์ Payload สำหรับติดตั้งภายใน SMAPI Zip"
        static let installSuccess       = "ติดตั้ง SMAPI เรียบร้อยแล้ว!"
        static let installError         = "การติดตั้งเกิดข้อผิดพลาด: %@"
        static let notFound             = "ไม่พบข้อมูลการติดตั้ง SMAPI ในโฟลเดอร์นี้"
        static let uninstallSuccess     = "ถอนการติดตั้ง SMAPI สำเร็จ! คืนค่าตัวเกมหลักเรียบร้อย"
        static let uninstallFailed      = "ถอนการติดตั้งล้มเหลว: %@"
    }

    // MARK: - UpdatesView
    enum Updates {
        static let newUpdate            = "มีการอัปเดตใหม่ในเว็บไซต์ Nexus Mods"
        static let download             = "ดาวน์โหลด"
        static let updateDescription    = "อัปเดตนี้เพิ่มคุณสมบัติใหม่และแก้ไขข้อบกพร่องสำหรับม็อดของคุณ"
        static let visitWebsite         = "สำหรับข้อมูลเกี่ยวกับเนื้อหาของอัปเดตนี้ โปรดไปที่เว็บไซต์:"
        static let errorsFound          = "พบข้อผิดพลาดจากตัวเกม หรือม็อด (%lld รายการ)"
        static let viewLogs             = "ดูบันทึกระบบ"
        static let errorDescription     = "เกมพบข้อผิดพลาดระหว่างการรันครั้งล่าสุด ซึ่งอาจเกิดจากม็อดที่ล้าสมัยหรือไฟล์ที่ขาดหายไป"
    }

    // MARK: - Thai Translation Hub
    enum ThaiHub {
        static let title                = "ม็อดแปลไทย"
        static let hubTitle             = "ศูนย์รวมม็อดแปลไทย"
        static let subtitle             = "ติดตั้งม็อดภาษาไทยที่รองรับได้ด้วยการคลิกเพียงครั้งเดียว สนับสนุนโดย AppleBoiy"
        static let loading              = "กำลังโหลดข้อมูลม็อดแปลไทย..."
        static let status               = "สถานะ"
        static let reinstall            = "ติดตั้งซ้ำ"
        static let install              = "ติดตั้ง"
        static let installation         = "การติดตั้ง"
        static let alreadyInstalled     = "คุณได้ติดตั้งม็อดนี้แล้ว แต่อาจมีเวอร์ชันใหม่ให้ดาวน์โหลด"
        static let clickToInstall       = "คลิกเพื่อดาวน์โหลดและติดตั้งม็อดแปลไทยลงในโฟลเดอร์เกมของคุณ"
        static let information          = "ข้อมูล"
        static let version              = "เวอร์ชันแปล"
        static let viewOnNexus          = "ดูบน Nexus Mods"
        static let note                 = "หมายเหตุ: ระบบนี้เป็นเพียงศูนย์รวมม็อดแปลภาษาเท่านั้น คุณจำเป็นต้องติดตั้งม็อดต้นฉบับก่อนเพื่อให้ม็อดแปลภาษาทำงานได้"
        static let translator           = "ผู้แปล"
        static let originalMod          = "ม็อดต้นฉบับ"
        static let originalModStatus    = "สถานะม็อดต้นฉบับ"
        static let installed            = "ติดตั้งแล้ว"
        static let notInstalled         = "ยังไม่ได้ติดตั้ง"
        static let destinationFolder    = "โฟลเดอร์ปลายทาง"
        static let description          = "รายละเอียด"
        static let descriptionPrefix    = "นี่คือม็อดแปลภาษาไทยสำหรับ "
        static let descriptionSuffix    = " โปรดตรวจสอบรายละเอียดเพิ่มเติมจากหน้าม็อดต้นฉบับบน Nexus Mods"
        static let completed            = "เสร็จสมบูรณ์"
        static let waitingTranslation   = "รอแปล"
        static let availableDownload    = "พร้อมให้ดาวน์โหลด"
        static let missingOriginal      = "ขาดม็อดต้นฉบับ"
        static let downloadAndInstall   = "ดาวน์โหลดและติดตั้ง"
        static let author               = "ผู้สร้าง"
        static let website              = "เว็บไซต์"
        static let thaiTranslationMod   = "ม็อดแปลภาษาไทย"
    }

    // MARK: - Mod Profiles
    enum Profiles {
        static let title                = "โปรไฟล์ม็อด"
        static let titleFull            = "โปรไฟล์ม็อด (Mod Profiles)"
        static let allProfiles          = "โปรไฟล์ม็อดทั้งหมด"
        static let addProfile           = "เพิ่มโปรไฟล์..."
        static let noProfiles           = "ยังไม่มีโปรไฟล์ม็อด"
        static let active               = "เปิดใช้งานอยู่"
        static let inUse                = "กำลังใช้งาน"
        static let inactive             = "ไม่ได้ใช้งาน"
        static let viewDetails          = "ดูรายละเอียดโปรไฟล์นี้"
        static let profileName          = "ชื่อโปรไฟล์"
        static let deleteProfile        = "ลบโปรไฟล์ม็อดนี้"
        static let deleteThisProfile    = "ลบโปรไฟล์นี้"
        static let deleteNote           = "การลบโปรไฟล์จะไม่ลบไฟล์ม็อดในเครื่องของคุณ"
        static let newProfileNote       = "โปรไฟล์ใหม่จะเริ่มต้นโดยไม่มีม็อดใดๆ เปิดใช้งาน คุณสามารถตั้งค่าม็อดได้ในภายหลัง"
        static let addNewProfile        = "เพิ่มโปรไฟล์ใหม่..."
        static let createNewProfile     = "สร้างโปรไฟล์ม็อดใหม่"
        static let profileNamePlaceholder = "ชื่อโปรไฟล์..."
        static let delete               = "ลบ..."
        static let save                 = "บันทึก"
        static let help                 = "ความช่วยเหลือ"
        static let cancel               = "ยกเลิก"
        static let ok                   = "ตกลง"
        static let modsInProfile        = "ม็อดในโปรไฟล์นี้ (%d ม็อด)"
        static let modsInProfileLong    = "ม็อดในโปรไฟล์นี้ (%lld ม็อด)"
        static let selectMods           = "เลือกม็อดที่คุณต้องการให้เปิดใช้งานในโปรไฟล์นี้"
        static let manage               = "จัดการ..."
        static let manageMods           = "จัดการม็อดในโปรไฟล์"
        static let dependencies         = "Dependencies (ม็อดที่ต้องการ)"
        static let required             = "Required"
        static let optional             = "Optional"
        static let selectAll            = "เลือกทั้งหมด"
        static let deselectAll          = "เอาออกทั้งหมด"
    }

    // MARK: - ViewModel / Operations
    enum VM {
        static let defaultFarmerName    = "ชาวไร่"
        
        // Launch Game
        static let launchingVanilla      = "กำลังเริ่มเปิดเกม Stardew Valley (Vanilla)..."
        static let launchVanillaSuccess  = "เปิดเกมเซสชัน Vanilla สำเร็จ"
        static let launchVanillaError    = "ไม่สามารถเปิดไฟล์ตัวเกมหลักโดยตรงได้: %@"
        static let cannotStartVanilla    = "ไม่สามารถเริ่มเกมแบบ Vanilla ได้"
        static let launchingSmapi        = "กำลังเริ่มเปิดเกม Stardew Valley (SMAPI)..."
        static let launchSteamSuccess    = "เปิดเกมผ่าน Steam สำเร็จ"
        static let launchDirectSuccess   = "เปิดไฟล์แอปตัวเกมโดยตรงสำเร็จ"
        static let cannotStartDirect     = "ไม่สามารถเปิดเกมได้ โปรดตรวจสอบโฟลเดอร์เกมของคุณ"
        static let cannotStartGame       = "ไม่สามารถเริ่มเกมได้โดยตรง"
        
        // Saves Manager
        static let saveSuccess           = "บันทึกเซฟและสำรองไฟล์เรียบร้อยแล้ว!"
        static let saveError             = "เกิดข้อผิดพลาดในการบันทึกเซฟ"
        static let deleteSaveSuccess     = "ย้ายเซฟลงถังขยะเรียบร้อยแล้ว"
        static let deleteSaveError       = "ไม่สามารถลบเซฟได้"
        static let duplicateSaveSuccess  = "ทำสำเนาเซฟเรียบร้อยแล้ว"
        static let duplicateSaveError    = "ไม่สามารถทำสำเนาเซฟได้ (อาจมีซ้ำอยู่แล้ว)"
        
        // Backups / Utility
        static let backupSavesSuccess    = "สำรองไฟล์เซฟทั้งหมดไปที่ Desktop เรียบร้อยแล้ว\n(%@)"
        static let zipSavesError         = "เกิดข้อผิดพลาดในการ Zip ไฟล์เซฟ"
        static let cannotRunZip          = "ไม่สามารถสั่งรันคำสั่ง Zip ได้"
        static let backupModsSuccess     = "สำรองโฟลเดอร์ม็อดไปที่ Desktop เรียบร้อยแล้ว\n(%@)"
        static let zipModsError          = "เกิดข้อผิดพลาดในการ Zip โฟลเดอร์ม็อด"
        static let cleanModsSuccess      = "ลบโฟลเดอร์ Mods_disabled เรียบร้อยแล้ว"
        static let cleanModsNotFound     = "ไม่พบโฟลเดอร์ Mods_disabled"
        static let cleanModsError        = "ลบโฟลเดอร์ Mods_disabled ไม่สำเร็จ: %@"
        
        // Thai Hub
        static let urlError              = "เกิดข้อผิดพลาดในการสร้าง URL ดาวน์โหลด"
        static let downloadingTranslation = "กำลังดาวน์โหลดไฟล์แปลภาษา: %@..."
        static let downloadFailed        = "ดาวน์โหลดล้มเหลว: %@"
        static let installThaiSuccess    = "ติดตั้งภาษาไทยสำหรับ %@ สำเร็จ!"
        static let unzipError            = "เกิดข้อผิดพลาดในการแตกไฟล์ Zip ลงโฟลเดอร์ Mods"
        static let unzipFailed           = "ไม่สามารถรันคำสั่ง Unzip ได้: %@"
        
        // Profiles
        static let switchProfile         = "สลับโปรไฟล์ม็อดเป็น: %@"
    }
}
