// 구조 참고: gksdud KeyboardManagement.swift (MIT). 전역 hidutil --set 대신 서비스별로 읽고 쓴다.
import Foundation
import FnCapsCore
import IOKit
import IOKit.hidsystem

/// 키보드 서비스 하나의 `UserKeyMapping`. 서비스는 자신을 만든 클라이언트보다 오래 살면 안 되므로 클라이언트를 함께 쥔다.
public final class IOHIDKeyboard: KeyboardDevice {
    private static let property = "UserKeyMapping" as CFString
    private static let srcKey = "HIDKeyboardModifierMappingSrc"
    private static let dstKey = "HIDKeyboardModifierMappingDst"

    private let client: IOHIDEventSystemClient
    private let service: IOHIDServiceClient
    public let registryID: UInt64

    init(client: IOHIDEventSystemClient, service: IOHIDServiceClient, registryID: UInt64) {
        self.client = client
        self.service = service
        self.registryID = registryID
    }

    struct Failure: Error {}

    public func readMappings() throws -> [KeyMapping] {
        guard let raw = IOHIDServiceClientCopyProperty(service, Self.property) else { return [] }
        guard let array = raw as? [[String: Any]] else { throw Failure() }
        return try array.map { item in
            guard let s = (item[Self.srcKey] as? NSNumber)?.uint64Value,
                let d = (item[Self.dstKey] as? NSNumber)?.uint64Value
            else { throw Failure() }
            return KeyMapping(src: s, dst: d)
        }
    }

    public func writeMappings(_ m: [KeyMapping]) throws {
        let array: [[String: Any]] = m.map { [Self.srcKey: NSNumber(value: $0.src), Self.dstKey: NSNumber(value: $0.dst)] }
        guard IOHIDServiceClientSetProperty(service, Self.property, array as CFArray) else { throw Failure() }
    }
}

public enum KeyboardMapper {
    /// 키보드 서비스 목록. 열거에 실패하면 nil, 키보드가 없으면 빈 배열.
    /// Universal Control의 다른 Mac 키보드는 커널 목록에 없으므로 커널 목록과의 교집합만 쓴다.
    public static func keyboards() -> [KeyboardDevice]? {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let list = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient],
            let kernel = kernelKeyboardIDs()
        else { return nil }
        var out: [KeyboardDevice] = []
        for service in list where IOHIDServiceClientConformsTo(service, 1, 6) != 0 {
            guard let id = registryID(of: service), kernel.contains(id) else { continue }
            out.append(IOHIDKeyboard(client: client, service: service, registryID: id))
        }
        return out
    }

    /// 커널이 아는 키보드 레지스트리 ID 집합. 1초 조정이 집합이 달라졌는지만 보려고 쓴다. 열거 실패는 nil.
    public static func kernelKeyboardSet() -> Set<UInt64>? { kernelKeyboardIDs() }

    private static func registryID(of service: IOHIDServiceClient) -> UInt64? {
        (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value
    }

    private static func kernelKeyboardIDs() -> Set<UInt64>? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDEventService"), &iterator)
            == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var ids = Set<UInt64>()
        // defer는 반복 본문 끝에 돌므로, 본문 안에서 entry를 다음 값으로 바꾸면 안 된다.
        // 그러면 방금 받은 다음 항목을 해제해 그 뒤 항목을 읽지 못한다.
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            if let pairs = IORegistryEntryCreateCFProperty(entry, "DeviceUsagePairs" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [[String: Any]],
                pairs.contains(where: {
                    ($0["DeviceUsagePage"] as? Int) == 1 && ($0["DeviceUsage"] as? Int) == 6
                })
            {
                var rid: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(entry, &rid) == KERN_SUCCESS { ids.insert(rid) }
            }
        }
        return ids
    }

    /// 재부팅을 가르는 값. 읽지 못하면 빈 문자열(기록을 지우지 않는다).
    public static func bootSession() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}
