// L10n+Onboarding.swift
// Clés du guide de premier lancement. Les titres d'étapes
// (`onboarding_step_*`) vivent dans `OnboardingStep` (Core), pas ici :
// une seule source par chaîne.

extension L10n {
    enum Onboarding {
        static let start          = "onboarding_start"
        static let skipAll        = "onboarding_skip_all"
        static let skipStep       = "onboarding_skip_step"
        static let next           = "onboarding_next"
        static let finish         = "onboarding_finish"
        static let runScan        = "onboarding_run_scan"
        static let stepOf         = "onboarding_step_of"
        static let welcomeBody    = "onboarding_welcome_body"
        static let gameDirBody    = "onboarding_game_dir_body"
        static let modsBody       = "onboarding_mods_body"
        static let modsNeedGameDir = "onboarding_mods_need_game_dir"
        static let modsCreate     = "onboarding_mods_create"
        static let modsScan       = "onboarding_mods_scan"
        static let modsCount      = "onboarding_mods_count"
        static let modsCreateFailed = "onboarding_mods_create_failed"
        static let smapiBody      = "onboarding_smapi_body"
        static let apiKeyBody     = "onboarding_api_key_body"
        static let aiBody         = "onboarding_ai_body"
        static let extensionsBody = "onboarding_extensions_body"
        static let doneBody       = "onboarding_done_body"
        static let doneGameDir    = "onboarding_done_game_dir"
        static let doneSmapi      = "onboarding_done_smapi"
        static let doneApiKey     = "onboarding_done_api_key"
        static let doneMods       = "onboarding_done_mods"
        static let settingsCard   = "onboarding_settings_card"
    }
}
