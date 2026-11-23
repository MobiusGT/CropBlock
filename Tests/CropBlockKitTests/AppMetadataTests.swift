import Foundation
import Testing
@testable import CropBlockKit

@Suite("App metadata")
struct AppMetadataTests {
    @Test("Metadata constants match bundle configuration")
    func metadataConstants() {
        #expect(AppMetadata.bundleIdentifier == "io.github.mobiusgt.cropblock")
        #expect(AppMetadata.displayName == "Crop Block")
        #expect(AppMetadata.repositoryURL.absoluteString == "https://github.com/MobiusGT/CropBlock")
    }
}
