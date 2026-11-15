import Foundation

/// 메모리에만 쓰는 UserDefaults. 시험이 어떤 defaults 도메인에도 파일을 남기지 않게 한다.
/// 읽기·쓰기 접근자를 모두 재정의한다. 재정의하지 않은 접근자는 실제 저장소를 건드릴 수 있다.
class MemoryDefaults: UserDefaults {
    var store: [String: Any] = [:]

    init() { super.init(suiteName: nil)! }

    override func object(forKey defaultName: String) -> Any? { store[defaultName] }
    override func bool(forKey defaultName: String) -> Bool { store[defaultName] as? Bool ?? false }
    override func string(forKey defaultName: String) -> String? { store[defaultName] as? String }
    override func data(forKey defaultName: String) -> Data? { store[defaultName] as? Data }
    override func dictionary(forKey defaultName: String) -> [String: Any]? { store[defaultName] as? [String: Any] }
    override func integer(forKey defaultName: String) -> Int { store[defaultName] as? Int ?? 0 }
    override func set(_ value: Bool, forKey defaultName: String) { store[defaultName] = value }
    override func set(_ value: Int, forKey defaultName: String) { store[defaultName] = value }
    override func set(_ value: Any?, forKey defaultName: String) { store[defaultName] = value }
    override func removeObject(forKey defaultName: String) { store[defaultName] = nil }
    override func synchronize() -> Bool { true }
}

/// 지정한 키의 저장이 조용히 실패하는 저장소. 「저장을 확인하지 못하면 쓰지 않는다」를 시험한다.
final class DroppingDefaults: MemoryDefaults {
    var droppedKeys: Set<String> = []

    override func set(_ value: Bool, forKey defaultName: String) {
        guard !droppedKeys.contains(defaultName) else { return }
        super.set(value, forKey: defaultName)
    }

    override func set(_ value: Int, forKey defaultName: String) {
        guard !droppedKeys.contains(defaultName) else { return }
        super.set(value, forKey: defaultName)
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        guard !droppedKeys.contains(defaultName) else { return }
        super.set(value, forKey: defaultName)
    }
}
