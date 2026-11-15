import Foundation
import Testing
@testable import FnCapsCore

@Suite struct PromptMemoryTests {
    @Test func emptyIsNotShown() {
        let d = MemoryDefaults()
        let m = PromptMemory(defaults: d)
        #expect(m.shown == false)
        #expect(PermissionButton.action(didRequestPrompt: m.shown) == .prompt)
    }

    @Test func markShownPersistsAcrossInstances() {
        let d = MemoryDefaults()
        PromptMemory(defaults: d).markShown()
        let m = PromptMemory(defaults: d)
        #expect(m.shown == true)
        #expect(PermissionButton.action(didRequestPrompt: m.shown) == .openSettings)
    }

    @Test func missingKeyWithLaunchedBeforeMigratesToShown() {
        let d = MemoryDefaults()
        d.set(true, forKey: PromptMemory.launchedKey)
        let m = PromptMemory(defaults: d)
        #expect(m.shown == true)
        #expect(PermissionButton.action(didRequestPrompt: m.shown) == .openSettings)
    }

    @Test func explicitFalseWinsOverLaunchedBefore() {
        let d = MemoryDefaults()
        d.set(true, forKey: PromptMemory.launchedKey)
        d.set(false, forKey: PromptMemory.key)
        let m = PromptMemory(defaults: d)
        #expect(m.shown == false)
        #expect(PermissionButton.action(didRequestPrompt: m.shown) == .prompt)
    }

    @Test func freshInstallWithoutLaunchedKeyIsNotShown() {
        let d = MemoryDefaults()
        d.set(false, forKey: PromptMemory.launchedKey)
        #expect(PromptMemory(defaults: d).shown == false)
    }
}
