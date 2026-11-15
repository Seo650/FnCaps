import Testing
import FnCapsCore
import FnCapsSystem

@Suite(.serialized)
@MainActor
struct CatalogSmokeTests {
    @Test func loadsRealSources() {
        let catalog = InputSourceCatalog()
        let sources = catalog.loadEnabled()
        #expect(!sources.isEmpty)
        let classified = SourceClassifier.classify(sources)
        #expect(!classified.base.isEmpty)
        let current = catalog.currentID()
        #expect(current != nil)
        if let current { #expect(sources.contains { $0.id == current }) }
    }
}
