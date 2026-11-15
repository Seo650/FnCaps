import Foundation
import Testing
@testable import FnCapsCore

// D-18, D-19: 처음 설정(합의어) 진행 상태. 단계는 UserDefaults에 남아 권한 뒤 재시작과
// 새 인스턴스에서도 이어지고, 업데이트 사용자는 키가 없어 처음 설정도 사이드바 항목도 없다.
// T-04.4-04: defaults 없이 만들면 메모리에만 써서 렌더 하니스가 사용자 defaults를 건드리지 않는다.

@Suite struct FirstRunSetupTests {
    @Test func seedsForFirstLaunchOnly() {
        let md = MemoryDefaults()
        FirstRunSetup.seedIfFirstLaunch(true, defaults: md)
        let setup = FirstRunSetup(defaults: md)
        #expect(setup.isTracked)
        #expect(setup.isActive)
        #expect(setup.step == 1)
        #expect(setup.opensInSetupMode)
    }

    @Test func doesNotSeedUpdateUsers() {
        let md = MemoryDefaults()
        FirstRunSetup.seedIfFirstLaunch(false, defaults: md)
        let setup = FirstRunSetup(defaults: md)
        #expect(!setup.isTracked)
        #expect(!setup.isActive)
        #expect(!setup.opensInSetupMode)
    }

    @Test func keepsStoredStepOnReseed() {
        let md = MemoryDefaults()
        md.store[FirstRunSetup.stepKey] = 3
        FirstRunSetup.seedIfFirstLaunch(true, defaults: md)
        #expect(FirstRunSetup(defaults: md).step == 3)
    }

    @Test func stepSurvivesRestart() {
        let md = MemoryDefaults()
        FirstRunSetup.seedIfFirstLaunch(true, defaults: md)
        FirstRunSetup(defaults: md).setStep(3)
        #expect(FirstRunSetup(defaults: md).step == 3)
    }

    @Test func clampsStoredAndWrittenStep() {
        let md = MemoryDefaults()
        md.store[FirstRunSetup.stepKey] = 9
        #expect(FirstRunSetup(defaults: md).step == 1)
        md.store[FirstRunSetup.stepKey] = "x"
        #expect(FirstRunSetup(defaults: md).step == 1)
        md.store[FirstRunSetup.stepKey] = 5
        #expect(FirstRunSetup(defaults: md).step == 5)

        let setup = FirstRunSetup(defaults: md)
        setup.setStep(0)
        #expect(setup.step == 1)
        setup.setStep(7)
        #expect(setup.step == 5)
        #expect(md.integer(forKey: FirstRunSetup.stepKey) == 5)
    }

    @Test func leavingAndResuming() {
        let md = MemoryDefaults()
        FirstRunSetup.seedIfFirstLaunch(true, defaults: md)
        let setup = FirstRunSetup(defaults: md)
        setup.markLeft()
        #expect(setup.isActive)
        #expect(!setup.opensInSetupMode)
        setup.resume()
        #expect(setup.opensInSetupMode)
    }

    @Test func finishEndsSetup() {
        let md = MemoryDefaults()
        FirstRunSetup.seedIfFirstLaunch(true, defaults: md)
        let setup = FirstRunSetup(defaults: md)
        setup.markLeft()
        setup.finish()
        #expect(!setup.isActive)
        #expect(!setup.opensInSetupMode)
        #expect(setup.isFinished)
    }

    @Test func memoryBackedInstanceWorksAlone() {
        let setup = FirstRunSetup(defaults: nil)
        #expect(!setup.isTracked)
        setup.seedIfFirstLaunch(true)
        #expect(setup.step == 1)
        setup.setStep(2)
        #expect(setup.step == 2)
        setup.finish()
        #expect(!setup.isActive)
    }

    // D-17, UI-SPEC §4·§8: 🌐 값이 이미 권장과 같으면 3단계를 건너뛰되 단계 점은 5개 그대로다.
    @Test func nextStepSkipsGlobeWhenSatisfied() {
        #expect(FirstRunSetup.nextStep(after: 0, globeOK: false) == 1)
        #expect(FirstRunSetup.nextStep(after: 1, globeOK: false) == 2)
        #expect(FirstRunSetup.nextStep(after: 2, globeOK: false) == 3)
        #expect(FirstRunSetup.nextStep(after: 2, globeOK: true) == 4)
        #expect(FirstRunSetup.nextStep(after: 3, globeOK: false) == 4)
        #expect(FirstRunSetup.nextStep(after: 4, globeOK: true) == 5)
        #expect(FirstRunSetup.nextStep(after: 4, globeOK: false) == 5)
        #expect(FirstRunSetup.nextStep(after: 5, globeOK: true) == 5)
        #expect(FirstRunSetup.nextStep(after: 5, globeOK: false) == 5)
    }

    @Test func previousStepSkipsGlobeWhenSatisfied() {
        #expect(FirstRunSetup.previousStep(before: 1, globeOK: true) == 1)
        #expect(FirstRunSetup.previousStep(before: 1, globeOK: false) == 1)
        #expect(FirstRunSetup.previousStep(before: 2, globeOK: false) == 1)
        #expect(FirstRunSetup.previousStep(before: 3, globeOK: false) == 2)
        #expect(FirstRunSetup.previousStep(before: 4, globeOK: true) == 2)
        #expect(FirstRunSetup.previousStep(before: 4, globeOK: false) == 3)
        #expect(FirstRunSetup.previousStep(before: 5, globeOK: true) == 4)
        #expect(FirstRunSetup.previousStep(before: 5, globeOK: false) == 4)
    }

    @Test func resumeStepSkipsSatisfiedGlobeStep() {
        #expect(FirstRunSetup.resumeStep(stored: 3, globeOK: true) == 4)
        #expect(FirstRunSetup.resumeStep(stored: 3, globeOK: false) == 3)
        #expect(FirstRunSetup.resumeStep(stored: 2, globeOK: true) == 2)
        #expect(FirstRunSetup.resumeStep(stored: 5, globeOK: true) == 5)
        #expect(FirstRunSetup.resumeStep(stored: 9, globeOK: false) == 5)
        #expect(FirstRunSetup.resumeStep(stored: 0, globeOK: false) == 1)
    }
}
