// 구조 참고: gksdud KeyboardManagement.swift, main.swift(merged / restored / targetConflict) (MIT)
import Foundation

/// `UserKeyMapping` 항목 하나. src와 dst는 `0x7_0000_0000 | 사용값` 형태의 64비트 값이다.
public struct KeyMapping: Equatable, Codable, Sendable {
    public var src: UInt64
    public var dst: UInt64

    public init(src: UInt64, dst: UInt64) {
        self.src = src
        self.dst = dst
    }
}

/// 키보드 서비스 하나. 시스템 구현은 FnCapsSystem에 있고, 시험은 가짜를 쓴다.
public protocol KeyboardDevice: AnyObject {
    var registryID: UInt64 { get }
    func readMappings() throws -> [KeyMapping]
    func writeMappings(_ m: [KeyMapping]) throws
}

/// 되돌림 기록. 쓰기 전에 저장한다.
/// - original: Caps가 원래 내던 값(항목이 없었으면 nil)
/// - target: 우리가 넣은 값
/// - pendingTarget: 쓰기를 시작했으나 다시 읽어 확인하기 전인 값
public struct KeyMappingRecord: Equatable, Codable, Sendable {
    public var original: UInt64?
    public var target: UInt64
    public var pendingTarget: UInt64?
    public var away: Bool

    public init(original: UInt64?, target: UInt64, pendingTarget: UInt64? = nil, away: Bool = false) {
        self.original = original
        self.target = target
        self.pendingTarget = pendingTarget
        self.away = away
    }

    /// 이 값이면 우리가 넣은 것으로 본다.
    public func isOurs(_ dst: UInt64) -> Bool {
        dst == target || dst == pendingTarget
    }

    /// 부재 중에 매핑을 원래 값으로 내려 둔 기록이다. 이 값은 원래 값이지 남의 매핑이 아니다.
    public func isAwayOriginal(_ dst: UInt64) -> Bool {
        away && original == dst
    }
}

/// 매핑 배열에 대한 순수 함수.
public enum KeyMappingOps {
    public static let caps = CapsKey.capsLockUsage

    public static func capsOutput(_ current: [KeyMapping]) -> UInt64? {
        current.first(where: { $0.src == caps })?.dst
    }

    /// Caps 항목만 교체한다. 다른 항목은 그대로 둔다.
    public static func merged(current: [KeyMapping], target: UInt64) -> [KeyMapping] {
        current.filter { $0.src != caps } + [KeyMapping(src: caps, dst: target)]
    }

    /// Caps 항목을 원래대로 돌린다. original이 nil이면 Caps 항목이 사라진다.
    public static func restored(current: [KeyMapping], original: UInt64?) -> [KeyMapping] {
        let rest = current.filter { $0.src != caps }
        guard let original else { return rest }
        return rest + [KeyMapping(src: caps, dst: original)]
    }

    /// Caps 말고 다른 키가 이미 target을 내는가.
    public static func targetConflict(current: [KeyMapping], target: UInt64) -> Bool {
        current.contains { $0.src != caps && $0.dst == target }
    }

    /// Caps가 우리 것이 아닌 다른 값을 내는가.
    public static func capsTaken(current: [KeyMapping], target: UInt64, record: KeyMappingRecord?) -> Bool {
        guard let dst = capsOutput(current) else { return false }
        if dst == target { return false }
        if let record, record.isOurs(dst) || record.isAwayOriginal(dst) { return false }
        return true
    }

    /// 순서를 무시한 비교.
    public static func sameSet(_ a: [KeyMapping], _ b: [KeyMapping]) -> Bool {
        func key(_ m: KeyMapping) -> (UInt64, UInt64) { (m.src, m.dst) }
        let sa = a.sorted { key($0) < key($1) }
        let sb = b.sorted { key($0) < key($1) }
        return sa == sb
    }
}

/// 키보드별 결과.
public struct MappingReport: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        case ok, unchanged, conflict, capsTaken, failed
    }

    public var results: [UInt64: Result] = [:]
    /// 복원 때 열거가 실패했거나 목록이 비어 있는데 기록이 남아 있었다.
    public var enumerationFailed = false
    /// 같은 키보드에서 연속 실패가 `KeyMappingManager.warnThreshold`회에 이르렀다.
    public var shouldWarn = false
    /// 목록에 없어 기록만 지운 키보드.
    public var droppedRecords: [UInt64] = []

    public init() {}

    public var anyFailed: Bool { results.values.contains(.failed) }
    public var anyConflict: Bool { results.values.contains(.conflict) }
    public var anyCapsTaken: Bool { results.values.contains(.capsTaken) }

    /// 적용: 키보드가 하나 이상이고 전부 ok 또는 unchanged.
    public var allApplied: Bool {
        !results.isEmpty && results.values.allSatisfy { $0 == .ok || $0 == .unchanged }
    }

    /// 복원: 열거가 성공했고 실패한 키보드가 없다.
    public var restoreComplete: Bool { !enumerationFailed && !anyFailed }
}

/// 매핑 적용과 복원. 쓰기 전에 되돌림 기록을 저장하고, 쓴 뒤 다시 읽어 확인한다.
public final class KeyMappingManager {
    static let recordsKey = "keyMappingRecords"
    static let bootKey = "keyMappingBoot"

    /// 이 횟수만큼 연속으로 실패해야 경고한다. 일시적 실패를 사용자에게 보이지 않기 위해서다.
    public static let warnThreshold = 3

    private let defaults: UserDefaults
    private var failStreak: [UInt64: Int] = [:]

    /// bootSession이 이전 실행과 다르면 기록을 지운다(레지스트리 ID 재사용 방지, 재부팅하면 매핑도 사라진다).
    public init(defaults: UserDefaults, bootSession: String) {
        self.defaults = defaults
        guard !bootSession.isEmpty else { return }
        let stored = defaults.string(forKey: Self.bootKey)
        if let stored, stored != bootSession {
            defaults.removeObject(forKey: Self.recordsKey)
        }
        if stored != bootSession {
            defaults.set(bootSession, forKey: Self.bootKey)
            defaults.synchronize()
        }
    }

    public var hasRecords: Bool { !loadRecords().isEmpty }

    // MARK: 기록 저장소

    func loadRecords() -> [String: KeyMappingRecord] {
        guard let raw = defaults.dictionary(forKey: Self.recordsKey) else { return [:] }
        var out: [String: KeyMappingRecord] = [:]
        for (k, v) in raw {
            if let data = v as? Data, let r = try? JSONDecoder().decode(KeyMappingRecord.self, from: data) {
                out[k] = r
            }
        }
        return out
    }

    private func store(_ records: [String: KeyMappingRecord]) {
        if records.isEmpty {
            defaults.removeObject(forKey: Self.recordsKey)
        } else {
            var raw: [String: Any] = [:]
            for (k, r) in records {
                if let data = try? JSONEncoder().encode(r) { raw[k] = data }
            }
            defaults.set(raw, forKey: Self.recordsKey)
        }
        defaults.synchronize()
    }

    private func save(_ record: KeyMappingRecord?, id: String) {
        var all = loadRecords()
        all[id] = record
        store(all)
    }

    // MARK: 적용

    public func apply(devices: [KeyboardDevice], target: UInt64) -> MappingReport {
        var report = MappingReport()
        for device in devices {
            let result = apply(device, target: target)
            report.results[device.registryID] = result
            switch result {
            case .failed:
                failStreak[device.registryID, default: 0] += 1
                if failStreak[device.registryID, default: 0] >= Self.warnThreshold { report.shouldWarn = true }
            case .ok, .unchanged:
                failStreak[device.registryID] = nil
            case .conflict, .capsTaken:
                break
            }
        }
        return report
    }

    private func apply(_ device: KeyboardDevice, target: UInt64) -> MappingReport.Result {
        let id = String(device.registryID)
        let before: [KeyMapping]
        do { before = try device.readMappings() } catch { return .failed }
        let record = loadRecords()[id]
        if KeyMappingOps.targetConflict(current: before, target: target) { return .conflict }
        if KeyMappingOps.capsTaken(current: before, target: target, record: record) { return .capsTaken }

        let capsDst = KeyMappingOps.capsOutput(before)
        // 기록 없이 Caps가 이미 target을 내면 앱 값이라고 볼 근거가 없으므로 원래 값으로 남긴다(CR-01).
        // 이 경우 capsTaken은 거짓이므로 capsDst == target이다.
        var original: UInt64?
        if record == nil, let capsDst {
            original = capsDst
        } else if let record, let capsDst, record.isOurs(capsDst) || record.isAwayOriginal(capsDst) {
            original = record.original
        } else if let record, record.away, capsDst == nil {
            // 부재 중 매핑을 내려 둔 기록: 원래 값은 그대로 이어받는다.
            original = record.original
        }

        if let record, capsDst == target, record.target == target, record.pendingTarget == nil {
            return .unchanged
        }

        // 쓰기보다 먼저 저장한다.
        save(KeyMappingRecord(original: original, target: target, pendingTarget: target, away: false), id: id)
        let expected = KeyMappingOps.merged(current: before, target: target)
        do {
            try device.writeMappings(expected)
            let after = try device.readMappings()
            if KeyMappingOps.sameSet(after, expected) {
                save(KeyMappingRecord(original: original, target: target, pendingTarget: nil, away: false), id: id)
                return .ok
            }
        } catch {}
        // 실패: 쓰기 전 값으로 되돌린다. 되돌렸다고 확인되면 기록도 쓰기 전 상태로 되돌린다(WR-04).
        // 쓰기 전 기록이 있었다면(앱 매핑이 `before`에 남아 있다) 지우면 안 된다. 없었을 때만 지워진다.
        try? device.writeMappings(before)
        if let now = try? device.readMappings(), KeyMappingOps.sameSet(now, before) {
            save(record, id: id)
        }
        return .failed
    }

    /// 쓰기 없이 충돌과 Caps 점유만 확인한다. 적용 전에 #60보다 먼저 부른다.
    public func check(devices: [KeyboardDevice], target: UInt64) -> MappingReport {
        var report = MappingReport()
        let records = loadRecords()
        for device in devices {
            guard let current = try? device.readMappings() else {
                report.results[device.registryID] = .failed
                continue
            }
            if KeyMappingOps.targetConflict(current: current, target: target) {
                report.results[device.registryID] = .conflict
            } else if KeyMappingOps.capsTaken(
                current: current, target: target, record: records[String(device.registryID)])
            {
                report.results[device.registryID] = .capsTaken
            } else {
                report.results[device.registryID] = .ok
            }
        }
        return report
    }

    // MARK: 부재 (잠금 화면, 다른 사용자 세션)

    /// 매핑만 원래 값으로 내리고 기록은 지우지 않는다. 기록에 away 표시만 남겨 다시 적용할 때 original을 잇는다.
    /// 부재 중 다른 사용자가 만든 F18을 원래 값으로 착각하지 않기 위해서다.
    public func markAway(devices: [KeyboardDevice]?) -> MappingReport {
        var report = MappingReport()
        let records = loadRecords()
        guard !records.isEmpty else { return report }
        guard let devices, !devices.isEmpty else {
            report.enumerationFailed = true
            return report
        }
        for device in devices {
            let id = String(device.registryID)
            guard var record = records[id] else { continue }
            let current: [KeyMapping]
            do { current = try device.readMappings() } catch {
                report.results[device.registryID] = .failed
                continue
            }
            if let capsDst = KeyMappingOps.capsOutput(current), record.isOurs(capsDst) {
                let expected = KeyMappingOps.restored(current: current, original: record.original)
                var done = false
                do {
                    try device.writeMappings(expected)
                    done = KeyMappingOps.sameSet(try device.readMappings(), expected)
                } catch {}
                guard done else {
                    report.results[device.registryID] = .failed
                    continue
                }
            }
            record.away = true
            record.pendingTarget = nil
            save(record, id: id)
            report.results[device.registryID] = .ok
        }
        return report
    }

    // MARK: 복원

    /// devices가 nil이면 열거 실패다. 기록이 있는데 열거가 실패했거나 비어 있으면 아무것도 지우지 않고 실패로 보고한다.
    public func restore(devices: [KeyboardDevice]?) -> MappingReport {
        var report = MappingReport()
        let records = loadRecords()
        guard !records.isEmpty else { return report }
        guard let devices, !devices.isEmpty else {
            report.enumerationFailed = true
            return report
        }
        let present = Set(devices.map { String($0.registryID) })
        var kept = records
        for (id, _) in records where !present.contains(id) {
            kept[id] = nil
            if let n = UInt64(id) { report.droppedRecords.append(n) }
        }
        if kept.count != records.count { store(kept) }

        for device in devices {
            let id = String(device.registryID)
            guard let record = kept[id] else { continue }
            report.results[device.registryID] = restore(device, id: id, record: record)
        }
        return report
    }

    private func restore(_ device: KeyboardDevice, id: String, record: KeyMappingRecord) -> MappingReport.Result {
        let current: [KeyMapping]
        do { current = try device.readMappings() } catch { return .failed }
        guard let capsDst = KeyMappingOps.capsOutput(current), record.isOurs(capsDst) else {
            // Caps가 이미 우리 값이 아니다: 건드리지 않고 기록만 지운다.
            save(nil, id: id)
            return .ok
        }
        let expected = KeyMappingOps.restored(current: current, original: record.original)
        do {
            try device.writeMappings(expected)
            let after = try device.readMappings()
            if KeyMappingOps.sameSet(after, expected) {
                save(nil, id: id)
                return .ok
            }
        } catch {}
        return .failed
    }
}
