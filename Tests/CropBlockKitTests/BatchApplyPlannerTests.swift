import Foundation
import Testing
@testable import CropBlockKit

@Suite("BatchApplyPlanner eligibility rules")
struct BatchApplyPlannerTests {
    @Test("Selects only Detected and confirmed Variable AR items while skipping all others")
    func batchSelectionSafetySkips() {
        let detected = UUID()
        let detectedZero = UUID()
        let varUnconfirmed = UUID()
        let varConfirmed = UUID()
        let noBars = UUID()
        let cropped = UUID()
        let errored = UUID()
        let pending = UUID()
        let scanning = UUID()
        let applying = UUID()

        let candidates: [BatchCandidate] = [
            BatchCandidate(id: detected, status: .detected, hasNonZeroInsets: true, variableARConfirmed: false),
            BatchCandidate(id: detectedZero, status: .detected, hasNonZeroInsets: false, variableARConfirmed: false),
            BatchCandidate(id: varUnconfirmed, status: .variableAR, hasNonZeroInsets: true, variableARConfirmed: false),
            BatchCandidate(id: varConfirmed, status: .variableAR, hasNonZeroInsets: true, variableARConfirmed: true),
            BatchCandidate(id: noBars, status: .noBars, hasNonZeroInsets: false, variableARConfirmed: false),
            BatchCandidate(id: cropped, status: .cropped, hasNonZeroInsets: true, variableARConfirmed: false),
            BatchCandidate(id: errored, status: .error, hasNonZeroInsets: true, variableARConfirmed: false),
            BatchCandidate(id: pending, status: .pending, hasNonZeroInsets: false, variableARConfirmed: false),
            BatchCandidate(id: scanning, status: .scanning, hasNonZeroInsets: false, variableARConfirmed: false),
            BatchCandidate(id: applying, status: .detected, hasNonZeroInsets: true, variableARConfirmed: false, isApplying: true),
        ]

        let selected = BatchApplyPlanner.eligibleIDs(from: candidates)
        #expect(selected == [detected, varConfirmed])
    }
}
