import Testing
@testable import FnCapsSystem

@Suite(.serialized)
struct MachineInfoReaderSmokeTests {
    @Test func readsWithoutCrash() {
        let model = MachineInfoReader.macModel()
        #expect(!model.isEmpty)

        let layout = MachineInfoReader.layoutType()
        #expect(["ANSI", "ISO", "JIS"].contains(layout) || layout.hasPrefix("unknown("))

        let keyboards = MachineInfoReader.keyboards()
        #expect(Set(keyboards).isSubset(of: ["built-in", "external"]))
        #expect(keyboards.count == Set(keyboards).count)

        let all = ([model, layout] + MachineInfoReader.keyboards()).joined(separator: "\n")
        #expect(!all.lowercased().contains("serial"))
    }
}
