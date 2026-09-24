//
//  WorkoutReviewModel.swift
//  Shared (app + share extension)
//

import Foundation
import Observation
import WorkoutKit

/// Screenshot → OCR → Apple Intelligence → editable steps → Watch.
@Observable
final class WorkoutReviewModel: Identifiable {
    enum Phase: Equatable {
        case reading(String)
        case editing
        case sending
        case sent(String)
    }

    private static let locationKey = "lastRunLocation"

    let id = UUID()
    var phase: Phase = .editing
    var steps: [PlanStep]
    var location: RunLocation {
        didSet { UserDefaults.standard.set(location.rawValue, forKey: Self.locationKey) }
    }
    /// Why the steps could not be read automatically; the user edits them by hand instead.
    var readingNotice: String?
    var sendError: String?

    init(steps: [PlanStep] = []) {
        self.steps = steps
        let saved = UserDefaults.standard.string(forKey: Self.locationKey)
        self.location = saved.flatMap(RunLocation.init(rawValue:)) ?? .tapis
    }

    var build: WorkoutKitBuilder.Result {
        WorkoutKitBuilder.build(from: steps, location: location)
    }

    var totalSeconds: Int {
        steps.reduce(0) { $0 + $1.durationSeconds }
    }

    var canSend: Bool {
        phase == .editing && steps.contains { $0.kind == .work || $0.kind == .recovery }
    }

    func read(imageData: Data) async {
        readingNotice = nil
        do {
            phase = .reading("Lecture de la capture…")
            let lines = try await ScreenshotTextExtractor.lines(from: imageData)
            phase = .reading("Analyse avec Apple Intelligence…")
            steps = try await WorkoutPlanParser.parse(lines.joined(separator: "\n"))
            if steps.isEmpty {
                readingNotice = "Aucune étape reconnue dans la capture. Ajoute-les à la main."
            }
        } catch {
            steps = []
            readingNotice = "Impossible de lire cette capture : \(error.localizedDescription) "
                + "Ajoute les étapes à la main."
        }
        phase = .editing
    }

    func send() async {
        sendError = nil
        phase = .sending
        do {
            let removed = try await WatchScheduler.send(build.workout)
            let replaced = removed > 0 ? " (séance précédente remplacée)" : ""
            phase = .sent("« \(location.workoutDisplayName) » est programmé sur la montre\(replaced).")
        } catch {
            sendError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            phase = .editing
        }
    }

    func addStep() {
        let kind: PlanStep.Kind = steps.last?.kind == .work ? .recovery : .work
        steps.append(PlanStep(kind: kind, durationSeconds: 60))
    }
}
