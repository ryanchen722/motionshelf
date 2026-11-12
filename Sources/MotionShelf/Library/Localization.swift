import Foundation

/// 介面語言：繁體中文或英文。存在 UserDefaults，沒選過時跟著系統語言。
/// Interface language: Traditional Chinese or English. Stored in UserDefaults; follows the system language until chosen.
enum Lang {
    static let key = "englishUI"

    static var isEnglish: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? !(Locale.preferredLanguages.first ?? "").hasPrefix("zh")
    }
}

/// 依目前語言回傳中文或英文 / Returns the Chinese or English text for the current language
func L(_ zh: String, _ en: String) -> String { Lang.isEnglish ? en : zh }
