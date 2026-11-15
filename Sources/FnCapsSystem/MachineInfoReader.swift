import Foundation
import Carbon
import IOKit

/// D-32 진단 정보용 기기 읽기. 일련번호·기기 고유 UUID·위치 ID는 읽지 않는다(D-31).
/// 셋 다 메인 스레드에서 짧게 끝나는 동기 함수이며 예외를 던지지 않는다.
public enum MachineInfoReader {
    /// `hw.model`(예: `Mac17,3`). 읽지 못하면 "-".
    public static func macModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "-" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "-" }
        return String(cString: buffer)
    }

    /// 현재 키보드 배열(ANSI·ISO·JIS). 장치별 배열을 주는 공개 API가 없어 현재 입력 장치 기준 한 값이다.
    /// KBGetLayoutType은 네 글자 코드(kKeyboardANSI 등)를 돌려주고, 그 밖의 값은 `unknown(0x…)`로 남긴다.
    public static func layoutType() -> String {
        switch Int(KBGetLayoutType(Int16(LMGetKbdType()))) {
        case Int(kKeyboardANSI): return "ANSI"
        case Int(kKeyboardISO): return "ISO"
        case Int(kKeyboardJIS): return "JIS"
        case let other: return String(format: "unknown(0x%08X)", other)
        }
    }

    /// 연결된 키보드 종류만 `built-in`·`external`로 한 번씩 적는다.
    /// 제품명은 블루투스 키보드에 사용자 이름이 들어갈 수 있어 넣지 않는다(사용자 결정 2026-11-13).
    /// 레지스트리만 열거하고 장치를 열지 않으므로 키 입력에 영향을 주지 않는다(T-04.2-13).
    /// 일련번호·위치 ID는 읽지 않는다(T-04.2-12).
    public static func keyboards() -> [String] {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator)
                == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var seen = Set<String>()
        var out: [String] = []
        // defer는 반복 본문 끝에 돌므로 본문 안에서 entry를 다음 값으로 바꾸면 안 된다.
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard
                let pairs = property(entry, "DeviceUsagePairs") as? [[String: Any]],
                pairs.contains(where: {
                    ($0["DeviceUsagePage"] as? Int) == 1 && ($0["DeviceUsage"] as? Int) == 6
                })
            else { continue }
            let builtIn = (property(entry, kIOHIDBuiltInKey) as? Bool) ?? false
            let line = builtIn ? "built-in" : "external"
            if seen.insert(line).inserted { out.append(line) }
        }
        return out
    }

    private static func property(_ entry: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
