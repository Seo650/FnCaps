import Foundation
import Testing
@testable import FnCapsCore

@Suite struct SourceRefreshTests {
    @Test func missingSourceDetected() {
        #expect(SelectFailure.indicatesMissingSource("status=-50/-50 delay=30ms"))
        #expect(SelectFailure.indicatesMissingSource("status=0/-50 delay=30ms"))
        #expect(SelectFailure.indicatesMissingSource("status=-50"))
        #expect(SelectFailure.indicatesMissingSource("source not found"))
    }

    @Test func notMissingSource() {
        #expect(!SelectFailure.indicatesMissingSource("status=0/0 delay=30ms"))
        #expect(!SelectFailure.indicatesMissingSource("status=-500/0"))
        #expect(!SelectFailure.indicatesMissingSource("status=-5/0"))
        #expect(!SelectFailure.indicatesMissingSource("timeout"))
        #expect(!SelectFailure.indicatesMissingSource("superseded"))
        #expect(!SelectFailure.indicatesMissingSource(""))
    }

    @Test func malformedIgnored() {
        #expect(!SelectFailure.indicatesMissingSource("status=-50x/0"))
        #expect(!SelectFailure.indicatesMissingSource("status=abc"))
        #expect(!SelectFailure.indicatesMissingSource("status="))
        #expect(!SelectFailure.indicatesMissingSource("status=0/0 note=status=-50"))
    }

    @Test func twoConsecutiveFailuresReject() {
        var r = RejectedSources()
        #expect(r.noteFailure(Fx.ja.id) == false)
        #expect(!r.contains(Fx.ja.id))
        #expect(r.noteFailure(Fx.ja.id) == true)
        #expect(r.contains(Fx.ja.id))
    }

    @Test func successResetsStreak() {
        var r = RejectedSources()
        _ = r.noteFailure(Fx.ja.id)
        r.noteSuccess(Fx.ja.id)
        #expect(r.noteFailure(Fx.ja.id) == false)
        #expect(!r.contains(Fx.ja.id))
    }

    @Test func otherSourceDoesNotAffectStreak() {
        var r = RejectedSources()
        _ = r.noteFailure(Fx.ja.id)
        _ = r.noteFailure(Fx.ko2.id)
        #expect(!r.contains(Fx.ja.id))
        #expect(!r.contains(Fx.ko2.id))
        #expect(r.noteFailure(Fx.ja.id) == true)
        #expect(!r.contains(Fx.ko2.id))
    }

    @Test func applyClearUnreject() {
        var r = RejectedSources()
        r.reject(Fx.ja.id)
        #expect(r.apply([Fx.abc, Fx.ko2, Fx.ja]) == [Fx.abc, Fx.ko2])
        r.clear()
        #expect(r.apply([Fx.abc, Fx.ko2, Fx.ja]) == [Fx.abc, Fx.ko2, Fx.ja])
        r.reject(Fx.ja.id)
        r.unreject(Fx.ja.id)
        #expect(r.apply([Fx.abc, Fx.ja]).contains(Fx.ja))
    }

    @Test func rejectionLeadsToWaiting() {
        let all = [Fx.abc, Fx.ko2, Fx.ja]
        let before = SourceClassifier.classify(all)
        #expect(before.modes.count == 2)
        #expect(AppStatus.resolve(trusted: true, enabled: true, hasActiveList: before.modes.count >= 2) == .running)
        #expect(TapInstallPolicy.shouldInstall(trusted: true, enabled: true, hasActiveList: before.modes.count >= 2))

        var r = RejectedSources()
        r.reject(Fx.ja.id)
        let after = SourceClassifier.classify(r.apply(all))
        #expect(after.modes.count == 1)
        #expect(AppStatus.resolve(trusted: true, enabled: true, hasActiveList: after.modes.count >= 2) == .waiting)
        #expect(!TapInstallPolicy.shouldInstall(trusted: true, enabled: true, hasActiveList: after.modes.count >= 2))

        r.clear()
        let back = SourceClassifier.classify(r.apply(all))
        #expect(AppStatus.resolve(trusted: true, enabled: true, hasActiveList: back.modes.count >= 2) == .running)
    }
}

extension SourceRefreshTests {
    @Suite struct ListCoding {
        @Test func roundTripKeepsOrderAndModes() {
            let list = [Fx.ja, Fx.abc, Fx.gureum, Fx.ko2, Fx.zh]
            let decoded = EnabledSourceList.decode(EnabledSourceList.encode(list))
            #expect(decoded == list)
            #expect(decoded.map { SourceClassifier.classify($0).modes } == SourceClassifier.classify(list).modes)
        }

        @Test func brokenDataIsNil() {
            #expect(EnabledSourceList.decode(Data("not json".utf8)) == nil)
            #expect(EnabledSourceList.decode(Data()) == nil)
            #expect(EnabledSourceList.decode(Data("{\"id\":\"a\"}".utf8)) == nil)
        }

        @Test func emptyListIsNil() {
            #expect(EnabledSourceList.decode(Data("[]".utf8)) == nil)
            #expect(EnabledSourceList.decode(EnabledSourceList.encode([])) == nil)
        }
    }}

/// 예약과 읽기를 모아 두고 테스트가 원하는 순서로 실행한다.
private final class RefreshRig {
    var scheduled: [(offset: TimeInterval, run: () -> Void)] = []
    var reads: [([SourceInfo]?) -> Void] = []
    var applied: [[SourceInfo]] = []
    var refresh: DebouncedRefresh!

    init(offsets: [TimeInterval] = DebouncedRefresh.defaultOffsets) {
        refresh = DebouncedRefresh(
            offsets: offsets,
            schedule: { [unowned self] offset, run in self.scheduled.append((offset, run)) },
            read: { [unowned self] done in self.reads.append(done) },
            apply: { [unowned self] list in self.applied.append(list) })
    }

    /// 쌓인 예약을 모두 실행하고 비운다.
    func fireAll() {
        let pending = scheduled
        scheduled = []
        pending.forEach { $0.run() }
    }
}

extension SourceRefreshTests {
    @Suite struct Debounce {
        private let base = [Fx.abc, Fx.ko2, Fx.ja]

        @Test func triggerSchedulesEachOffsetAndReadsOncePerOffset() {
            let rig = RefreshRig()
            rig.refresh.trigger()
            #expect(rig.scheduled.map { $0.offset } == DebouncedRefresh.defaultOffsets)
            #expect(rig.reads.isEmpty)
            rig.scheduled[0].run()
            #expect(rig.reads.count == 1)
            rig.scheduled[1].run()
            #expect(rig.reads.count == 2)
        }

        @Test func defaultOffsets() {
            #expect(DebouncedRefresh.defaultOffsets == [0.15, 1.0])
        }

        @Test func seedDoesNotApply() {
            let rig = RefreshRig()
            rig.refresh.seed(base)
            #expect(rig.applied.isEmpty)
            #expect(rig.scheduled.isEmpty)
            #expect(rig.reads.isEmpty)
        }

        @Test func sameAsSeedDoesNotApply() {
            let rig = RefreshRig()
            rig.refresh.seed(base)
            rig.refresh.trigger()
            rig.fireAll()
            rig.reads.forEach { $0(base) }
            #expect(rig.applied.isEmpty)
        }

        @Test func differentResultAppliesOnceAcrossBothReads() {
            let rig = RefreshRig()
            rig.refresh.seed(base)
            rig.refresh.trigger()
            rig.fireAll()
            let next = [Fx.abc, Fx.ko2]
            rig.reads[0](next)
            #expect(rig.applied == [next])
            rig.reads[1](next)
            #expect(rig.applied == [next])
        }

        @Test func failureKeepsBaseline() {
            let rig = RefreshRig()
            rig.refresh.seed(base)
            rig.refresh.trigger()
            rig.fireAll()
            rig.reads[0](nil)
            #expect(rig.applied.isEmpty)
            // 비교 기준이 그대로이므로 seed와 같은 결과는 여전히 변경이 아니다.
            rig.reads[1](base)
            #expect(rig.applied.isEmpty)
        }

        @Test func triggerBeforeFireCancelsOldSchedule() {
            let rig = RefreshRig()
            rig.refresh.trigger()
            let old = rig.scheduled
            rig.scheduled = []
            rig.refresh.trigger()
            old.forEach { $0.run() }
            #expect(rig.reads.isEmpty)
            rig.fireAll()
            #expect(rig.reads.count == 2)
        }

        @Test func triggerDuringReadDropsOldResult() {
            let rig = RefreshRig()
            rig.refresh.seed(base)
            rig.refresh.trigger()
            rig.scheduled.removeFirst().run()
            let late = rig.reads.removeFirst()
            rig.scheduled = []
            rig.refresh.trigger()
            late([Fx.abc])
            #expect(rig.applied.isEmpty)
            // 옛 결과가 비교 기준도 바꾸지 않았다.
            rig.fireAll()
            rig.reads[0](base)
            #expect(rig.applied.isEmpty)
        }

        @Test func stopSilencesScheduleAndLateResult() {
            let rig = RefreshRig()
            rig.refresh.seed(base)
            rig.refresh.trigger()
            rig.scheduled.removeFirst().run()
            let late = rig.reads.removeFirst()
            rig.refresh.stop()
            rig.fireAll()
            #expect(rig.reads.isEmpty)
            late([Fx.abc])
            #expect(rig.applied.isEmpty)
        }

        @Test func removedAndAddedSourcesReachApply() {
            let rig = RefreshRig()
            rig.refresh.seed(base)
            rig.refresh.trigger()
            rig.fireAll()
            let removed = [Fx.abc, Fx.ko2]
            rig.reads[0](removed)
            #expect(rig.applied.last == removed)

            rig.reads = []
            rig.refresh.trigger()
            rig.fireAll()
            let added = [Fx.abc, Fx.ko2, Fx.zh]
            rig.reads[0](added)
            #expect(rig.applied.last == added)
            #expect(rig.applied.count == 2)
        }

        /// 02-20 1부 재현: 지운 소스로 외국어가 1개가 되면 대기 상태, 되돌리면 실행 상태.
        @Test func removalReachesWaitingAndReAddRunning() {
            let rig = RefreshRig()
            rig.refresh.seed(base)
            rig.refresh.trigger()
            rig.fireAll()
            rig.reads[0]([Fx.abc, Fx.ko2])
            let after = SourceClassifier.classify(rig.applied[0])
            #expect(AppStatus.resolve(trusted: true, enabled: true, hasActiveList: after.modes.count >= 2) == .waiting)

            rig.reads = []
            rig.refresh.trigger()
            rig.fireAll()
            rig.reads[0](base)
            let back = SourceClassifier.classify(rig.applied[1])
            #expect(AppStatus.resolve(trusted: true, enabled: true, hasActiveList: back.modes.count >= 2) == .running)
        }
    }}
