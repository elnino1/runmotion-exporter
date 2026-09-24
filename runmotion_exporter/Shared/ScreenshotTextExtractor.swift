//
//  ScreenshotTextExtractor.swift
//  Shared (app + share extension)
//

import CoreGraphics
import Foundation
import Vision

/// On-device OCR (Vision) of a RunMotion screenshot into reading-order text lines.
enum ScreenshotTextExtractor {
    /// One recognized piece of text, in Vision's normalized coordinates (origin bottom-left).
    struct Fragment: Equatable {
        var text: String
        var minX: Double
        var midY: Double
        var height: Double
    }

    static func lines(from imageData: Data) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "fr-FR"), Locale.Language(identifier: "en-US")]

        let observations = try await request.perform(on: imageData)
        let fragments = observations.compactMap { observation -> Fragment? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox.cgRect
            return Fragment(text: text, minX: box.minX, midY: box.midY, height: box.height)
        }
        return groupIntoLines(fragments)
    }

    /// Joins fragments sitting on the same visual row ("Effort" … "1'30" … "12 km/h")
    /// into one line, left to right, and orders rows top to bottom.
    static func groupIntoLines(_ fragments: [Fragment]) -> [String] {
        var rows: [[Fragment]] = []
        for fragment in fragments.sorted(by: { $0.midY > $1.midY }) {
            if let row = rows.last, let anchor = row.first,
               abs(anchor.midY - fragment.midY) < min(anchor.height, fragment.height) / 2 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            row.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
        }
    }
}
