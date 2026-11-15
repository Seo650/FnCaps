import Foundation
import Testing
@testable import FnCapsCore

/// 앱 언어(D-42, 04-RESEARCH-ADDENDUM §1). 저장은 앱 도메인 AppleLanguages 하나.
@Suite struct AppLanguageTests {
    @Test func nilIsSystem() { #expect(AppLanguage.from(stored: nil) == .system) }

    @Test func emptyIsSystem() { #expect(AppLanguage.from(stored: []) == .system) }

    @Test func plainCodes() {
        #expect(AppLanguage.from(stored: ["ko"]) == .ko)
        #expect(AppLanguage.from(stored: ["ja"]) == .ja)
        #expect(AppLanguage.from(stored: ["en"]) == .en)
        #expect(AppLanguage.from(stored: ["uk"]) == .uk)
        #expect(AppLanguage.from(stored: ["ru"]) == .ru)
        #expect(AppLanguage.from(stored: ["fr"]) == .fr)
        #expect(AppLanguage.from(stored: ["es"]) == .es)
        #expect(AppLanguage.from(stored: ["de"]) == .de)
    }

    @Test func regionSuffixIgnored() { #expect(AppLanguage.from(stored: ["ko-KR"]) == .ko) }

    @Test func firstValueWins() { #expect(AppLanguage.from(stored: ["en-US", "ko"]) == .en) }

    @Test func unsupportedIsSystem() {
        #expect(AppLanguage.from(stored: ["pt"]) == .system)
        #expect(AppLanguage.from(stored: ["nb"]) == .system)
        #expect(AppLanguage.from(stored: ["pt-BR"]) == .system)
        #expect(AppLanguage.from(stored: ["yue-Hant"]) == .system)
    }

    @Test func appleLanguagesValues() {
        #expect(AppLanguage.ko.appleLanguages == ["ko"])
        #expect(AppLanguage.en.appleLanguages == ["en"])
        #expect(AppLanguage.ja.appleLanguages == ["ja"])
        #expect(AppLanguage.zhHans.appleLanguages == ["zh-Hans"])
        #expect(AppLanguage.zhHant.appleLanguages == ["zh-Hant"])
        #expect(AppLanguage.uk.appleLanguages == ["uk"])
        #expect(AppLanguage.ru.appleLanguages == ["ru"])
        #expect(AppLanguage.fr.appleLanguages == ["fr"])
        #expect(AppLanguage.es.appleLanguages == ["es"])
        #expect(AppLanguage.de.appleLanguages == ["de"])
        #expect(AppLanguage.system.appleLanguages == nil)
    }

    @Test func defaultsKeyIsAppleLanguages() { #expect(AppLanguage.defaultsKey == "AppleLanguages") }

    @Test func roundTrip() {
        for lang in AppLanguage.allCases { #expect(AppLanguage.from(stored: lang.appleLanguages) == lang) }
    }

    /// `zh-Hans`와 `zh-Hant`는 `-` 앞 부분이 같다. 문자·지역 꼬리로 갈라야 한다.
    @Test func chineseScriptAndRegion() {
        for tag in ["zh-Hant", "zh-TW", "zh-HK", "zh-Hant-HK", "zh_TW",
                    "zh-Hant-CN", "ZH-tw", "zh-MO"] {
            #expect(AppLanguage.from(stored: [tag]) == .zhHant, "\(tag)")
        }
        // 문자 꼬리가 지역 꼬리보다 앞선다: zh-Hans-TW는 간체(Foundation과 같음).
        for tag in ["zh", "zh-Hans", "zh-CN", "zh-Hans-KR", "zh-SG", "zh_Hans",
                    "zh-Hans-TW", "zh-Hans-HK", "zh-Hans-MO", "zh-hans-tw"] {
            #expect(AppLanguage.from(stored: [tag]) == .zhHans, "\(tag)")
        }
    }

    /// 지역 꼬리가 붙은 값도(예: 시스템 설정의 `ja-KR`) 같은 언어로 읽힌다.
    @Test func regionTailsOfNewLanguages() {
        #expect(AppLanguage.from(stored: ["uk-UA"]) == .uk)
        #expect(AppLanguage.from(stored: ["es-419"]) == .es)
        #expect(AppLanguage.from(stored: ["fr-CA"]) == .fr)
        #expect(AppLanguage.from(stored: ["de-AT"]) == .de)
        #expect(AppLanguage.from(stored: ["ru-RU"]) == .ru)
        #expect(AppLanguage.from(stored: ["ja-KR"]) == .ja)
    }

    /// 판별 결과가 Foundation의 번들 해석과 같아야 고른 언어의 번역이 실제로 쓰인다.
    @Test func matchesBundleResolution() {
        let available = AppLanguage.menuOrder.map(\.rawValue)
        let tags = ["zh", "zh-CN", "zh-TW", "zh-HK", "zh-Hant-HK", "zh-Hans-KR",
                    "zh-Hans-TW", "zh-Hans-HK", "zh-Hans-MO", "zh-Hant-CN", "zh-hans-tw",
                    "ZH-tw", "zh-MO",
                    "es-419", "uk-UA", "pt-BR", "ja-KR", "fr-CA"]
        for tag in tags {
            let bundle = Bundle.preferredLocalizations(from: available, forPreferences: [tag, "en"]).first
            let mine = AppLanguage.from(stored: [tag])
            #expect((mine == .system ? "en" : mine.rawValue) == bundle, "\(tag)")
        }
    }

    /// D-10 팝업 순서. `allCases` 순서에 기대지 않는다.
    @Test func menuOrderIsD10() {
        #expect(AppLanguage.menuOrder.map(\.rawValue)
            == ["en", "ko", "ja", "zh-Hans", "zh-Hant", "uk", "ru", "fr", "es", "de"])
        #expect(!AppLanguage.menuOrder.contains(.system))
    }

    @Test func nativeNames() {
        #expect(AppLanguage.menuOrder.map(\.nativeName)
            == ["English", "한국어", "日本語", "简体中文", "繁體中文",
                "Українська", "Русский", "Français", "Español", "Deutsch"])
    }

    /// `CFBundleLocalizations`와 lproj 폴더 이름이 `menuOrder` 원시값과 어긋나지 않게 묶는다.
    /// lproj 이름 집합 = CFBundleLocalizations = 지원 언어(10개) 완전 일치를 본다(04.1-12).
    @Test func identifiersMatchInfoPlist() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plistURL = root.appendingPathComponent("Resources/FnCaps-Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let declared = (plist as? [String: Any])?["CFBundleLocalizations"] as? [String]
        let supported = Set(AppLanguage.menuOrder.map(\.rawValue))
        #expect(declared != nil, "CFBundleLocalizations를 읽지 못했습니다: \(plistURL.path)")
        #expect(Set(declared ?? []) == supported, "CFBundleLocalizations: \(declared ?? [])")

        let resources = root.appendingPathComponent("Resources")
        let folders = try FileManager.default.contentsOfDirectory(atPath: resources.path)
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(".lproj".count)) }
        // 04.1-12에서 완전 일치로 조임: lproj = CFBundleLocalizations = 지원 집합(10개)
        #expect(Set(folders) == supported, "lproj: \(folders.sorted())")
        #expect(folders.count == supported.count, "lproj 개수: \(folders.count)")
    }
}
