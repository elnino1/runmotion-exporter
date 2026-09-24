//
//  ScreenshotTextExtractorTests.swift
//  runmotion_exporterTests
//

import Testing
@testable import runmotion_exporter

struct ScreenshotTextExtractorTests {
    private typealias Fragment = ScreenshotTextExtractor.Fragment

    @Test func joinsFragmentsOnTheSameRowLeftToRight() {
        let fragments = [
            Fragment(text: "12 km/h", minX: 0.7, midY: 0.50, height: 0.02),
            Fragment(text: "Échauffement", minX: 0.1, midY: 0.80, height: 0.02),
            Fragment(text: "Effort 1'", minX: 0.1, midY: 0.505, height: 0.02),
            Fragment(text: "15'", minX: 0.7, midY: 0.795, height: 0.02),
        ]

        #expect(ScreenshotTextExtractor.groupIntoLines(fragments) == ["Échauffement 15'", "Effort 1' 12 km/h"])
    }

    @Test func keepsDistinctRowsApart() {
        let fragments = [
            Fragment(text: "Récup 1'30", minX: 0.1, midY: 0.47, height: 0.02),
            Fragment(text: "Effort 1'", minX: 0.1, midY: 0.50, height: 0.02),
        ]

        #expect(ScreenshotTextExtractor.groupIntoLines(fragments) == ["Effort 1'", "Récup 1'30"])
    }
}
