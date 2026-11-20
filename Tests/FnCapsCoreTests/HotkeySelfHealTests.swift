import Testing
@testable import FnCapsCore

@Suite struct HotkeySelfHealTests {
    @Test func singleTimeoutNoCheck() {
        var heal = HotkeySelfHeal()
        let scheduled = heal.noteTimeout(at: 0)
        #expect(!scheduled)
        #expect(heal.misses == 1)
    }

    @Test func twoTimeoutsCheck() {
        var heal = HotkeySelfHeal()
        let first = heal.noteTimeout(at: 0)
        let second = heal.noteTimeout(at: 1)
        #expect(!first)
        #expect(second)
        #expect(heal.pending)
    }

    @Test func landedResets() {
        var heal = HotkeySelfHeal()
        _ = heal.noteTimeout(at: 0)
        heal.noteLanded()
        let next = heal.noteTimeout(at: 1)
        #expect(heal.misses == 1)
        #expect(!next)
    }

    @Test func pendingBlocksSecondCheck() {
        var heal = HotkeySelfHeal()
        _ = heal.noteTimeout(at: 0)
        _ = heal.noteTimeout(at: 1)
        // 확인을 마치기 전에 또 시간 초과가 나도 예약을 겹쳐 만들지 않는다.
        let third = heal.noteTimeout(at: 2)
        #expect(!third)
    }

    @Test func oursKeeps() {
        var heal = HotkeySelfHeal()
        _ = heal.noteTimeout(at: 0)
        _ = heal.noteTimeout(at: 1)
        let verdict = heal.checked(ours: true, at: 1)
        #expect(verdict == .keep)
        #expect(heal.reapplies == 0)
        #expect(!heal.pending)
        #expect(heal.misses == 0)
    }

    @Test func unreadableNoWrite() {
        var heal = HotkeySelfHeal()
        _ = heal.noteTimeout(at: 0)
        _ = heal.noteTimeout(at: 1)
        let verdict = heal.checked(ours: nil, at: 1)
        #expect(verdict == .unreadable)
        #expect(heal.reapplies == 0)
    }

    @Test func notOursReapplies() {
        var heal = HotkeySelfHeal()
        _ = heal.noteTimeout(at: 0)
        _ = heal.noteTimeout(at: 1)
        let verdict = heal.checked(ours: false, at: 1)
        #expect(verdict == .reapply)
        #expect(heal.reapplies == 1)
    }

    @Test func cooldown() {
        var heal = HotkeySelfHeal()
        _ = heal.noteTimeout(at: 0)
        _ = heal.noteTimeout(at: 1)
        _ = heal.checked(ours: true, at: 1)
        let a = heal.noteTimeout(at: 10)
        let b = heal.noteTimeout(at: 20)
        // 60초가 지나야 다시 확인한다.
        let c = heal.noteTimeout(at: 62)
        #expect(!a)
        #expect(!b)
        #expect(c)
    }

    @Test func skipRetriesSoon() {
        var heal = HotkeySelfHeal()
        _ = heal.noteTimeout(at: 0)
        _ = heal.noteTimeout(at: 1)
        heal.skipCheck()
        // 읽지 못했으면 계수는 그대로 두고 다음 시간 초과에 다시 확인을 건다.
        let again = heal.noteTimeout(at: 2)
        #expect(again)
    }

    @Test func giveUpAfterMax() {
        var heal = HotkeySelfHeal()
        func check(_ now: Double) -> HotkeySelfHeal.Verdict {
            _ = heal.noteTimeout(at: now - 1)
            _ = heal.noteTimeout(at: now)
            return heal.checked(ours: false, at: now)
        }
        let first = check(1)
        let second = check(101)
        let third = check(201)
        #expect(first == .reapply)
        #expect(second == .reapply)
        #expect(third == .reapply)
        #expect(heal.reapplies == HotkeySelfHeal.maxReapplies)
        // 한도를 다 썼으면 더 쓰지 않는다.
        let fourth = check(301)
        #expect(fourth == .giveUp)
        #expect(heal.gaveUp)
        let a = heal.noteTimeout(at: 400)
        let b = heal.noteTimeout(at: 401)
        #expect(!a)
        #expect(!b)
    }

    @Test func landedDoesNotResetBudget() {
        var heal = HotkeySelfHeal()
        _ = heal.noteTimeout(at: 0)
        _ = heal.noteTimeout(at: 1)
        _ = heal.checked(ours: false, at: 1)
        heal.noteLanded()
        // 빼앗기는 사이사이 착지가 있어도 다시 적용 한도는 남는다.
        #expect(heal.reapplies == 1)
    }

    @Test func resetClearsAll() {
        var heal = HotkeySelfHeal()
        for now in [1.0, 101, 201, 301] {
            _ = heal.noteTimeout(at: now - 1)
            _ = heal.noteTimeout(at: now)
            _ = heal.checked(ours: false, at: now)
        }
        #expect(heal.gaveUp)
        heal.reset()
        #expect(heal == HotkeySelfHeal())
        let a = heal.noteTimeout(at: 400)
        let b = heal.noteTimeout(at: 401)
        #expect(!a)
        #expect(b)
    }
}
