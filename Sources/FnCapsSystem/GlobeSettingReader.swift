import Foundation

/// Read-only access to the system Globe key setting (AppleFnUsageType).
/// See GlobeSettingAdvisor for the meaning of values. No write API on purpose.
public enum GlobeSettingReader {
    public static func readUsage() -> Int? {
        let domain = "com.apple.HIToolbox" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, domain) as? Int
    }
}
