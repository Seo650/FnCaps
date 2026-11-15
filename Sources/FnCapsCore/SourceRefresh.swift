import Foundation

/// TIS 목록이 enabled-changed 알림 시점에 낡을 수 있어(REVIEW WR-04, 추정),
/// 선택 실패(-50 paramErr)를 「지워진 소스」 증거로 쓴다.
public enum SelectFailure {
    public static func indicatesMissingSource(_ notes: String) -> Bool {
        if notes.contains("source not found") { return true }
        guard let range = notes.range(of: "status=") else { return false }
        let rest = notes[range.upperBound...]
        let token = rest.prefix { !$0.isWhitespace }
        return token.split(separator: "/", omittingEmptySubsequences: false)
            .contains { Int($0) == -50 }
    }
}

/// 지워진 것으로 판단한 소스의 제외 목록과 연속 실패 계수.
public struct RejectedSources: Equatable, Sendable {
    public static let threshold = 2

    public private(set) var ids: Set<SourceID> = []
    private var failureStreak: [SourceID: Int] = [:]

    public init() {}

    public mutating func reject(_ id: SourceID) { ids.insert(id) }

    public mutating func unreject(_ id: SourceID) {
        ids.remove(id)
        failureStreak[id] = nil
    }

    public mutating func clear() {
        ids.removeAll()
        failureStreak.removeAll()
    }

    public func contains(_ id: SourceID) -> Bool { ids.contains(id) }

    public func apply(_ sources: [SourceInfo]) -> [SourceInfo] {
        sources.filter { !ids.contains($0.id) }
    }

    /// 연속 실패를 기록한다. threshold에 도달해 제외하면 true.
    @discardableResult
    public mutating func noteFailure(_ id: SourceID) -> Bool {
        let n = (failureStreak[id] ?? 0) + 1
        failureStreak[id] = n
        if n >= Self.threshold {
            reject(id)
            return true
        }
        return false
    }

    public mutating func noteSuccess(_ id: SourceID) {
        failureStreak[id] = nil
        ids.remove(id)
    }
}

/// 켜진 소스 목록을 새 프로세스에서 앱으로 옮기는 형식.
/// 분류에 언어 값이 필요해 ID 줄이 아니라 SourceInfo 전체를 JSON으로 보낸다.
public enum EnabledSourceList {
    public static func encode(_ sources: [SourceInfo]) -> Data {
        (try? JSONEncoder().encode(sources)) ?? Data()
    }

    /// 파싱 실패나 빈 배열이면 nil. 확인 경로 오류로 모든 소스를 지워 fn이 꺼지는 일을 막는다.
    public static func decode(_ data: Data) -> [SourceInfo]? {
        guard let list = try? JSONDecoder().decode([SourceInfo].self, from: data), !list.isEmpty
        else { return nil }
        return list
    }
}

/// 새 프로세스 읽기를 묶어서 실행하고, 바뀐 목록만 넘긴다. 한 스레드(앱에서는 메인)에서만 쓴다.
///
/// 근거(02-20 1부): 앱 안 TIS는 삭제를 못 보고 지운 소스를 되살렸고, 새 프로세스는 t=0에 감지했다.
/// 1.0 s 읽기는 알림과 시스템 반영 사이가 벌어지는 경우의 보험이다(추정).
public final class DebouncedRefresh {
    public typealias Read = (@escaping ([SourceInfo]?) -> Void) -> Void
    public typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void

    public static let defaultOffsets: [TimeInterval] = [0.15, 1.0]

    private let offsets: [TimeInterval]
    private let schedule: Schedule
    private let read: Read
    private let apply: ([SourceInfo]) -> Void
    private var generation = 0
    private var last: [SourceInfo]?

    public init(
        offsets: [TimeInterval] = DebouncedRefresh.defaultOffsets,
        schedule: @escaping Schedule, read: @escaping Read,
        apply: @escaping ([SourceInfo]) -> Void
    ) {
        self.offsets = offsets
        self.schedule = schedule
        self.read = read
        self.apply = apply
    }

    /// 비교 기준만 정한다. apply를 부르지 않는다.
    public func seed(_ sources: [SourceInfo]) {
        last = sources
    }

    /// 새 세대를 연다. 옛 세대의 예약과 아직 오지 않은 결과는 버려진다.
    public func trigger() {
        generation += 1
        let gen = generation
        for offset in offsets {
            schedule(offset) { [weak self] in self?.fire(gen) }
        }
    }

    public func stop() {
        generation += 1
    }

    private func fire(_ gen: Int) {
        guard gen == generation else { return }
        read { [weak self] list in self?.receive(list, gen) }
    }

    private func receive(_ list: [SourceInfo]?, _ gen: Int) {
        guard gen == generation, let list, list != last else { return }
        last = list
        apply(list)
    }
}
