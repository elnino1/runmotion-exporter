//
//  PlanStep.swift
//  Shared (app + share extension)
//

import Foundation
import HealthKit

/// One step of a RunMotion plan, as read from a screenshot and corrected by the user.
struct PlanStep: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case warmup, work, recovery, cooldown

        var id: Self { self }

        var label: String {
            switch self {
            case .warmup: "Échauffement"
            case .work: "Effort"
            case .recovery: "Récupération"
            case .cooldown: "Retour au calme"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var durationSeconds: Int
    var speedKmh: Double? = nil
    var speedToleranceKmh: Double? = nil
    var heartRateBpm: Int? = nil

    var summary: String {
        var text = "\(kind.label) — \(Self.formatDuration(durationSeconds))"
        if let speedKmh {
            text += String(format: " @ %.1f ± %.1f km/h", speedKmh, speedToleranceKmh ?? WorkoutKitBuilder.defaultSpeedToleranceKmh)
        } else if let heartRateBpm {
            text += " @ \(heartRateBpm) bpm"
        }
        return text
    }

    /// `90` → `1'30"`, `900` → `15'`.
    static func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let rest = seconds % 60
        return "\(minutes)'\(rest > 0 ? String(format: "%02d\"", rest) : "")"
    }
}

enum RunLocation: String, CaseIterable, Identifiable {
    case tapis, exterieur

    var id: Self { self }

    var label: String {
        switch self {
        case .tapis: "Tapis"
        case .exterieur: "Extérieur"
        }
    }

    var workoutDisplayName: String { "RunMotion - \(label)" }

    var hkLocation: HKWorkoutSessionLocationType {
        switch self {
        case .tapis: .indoor
        case .exterieur: .outdoor
        }
    }
}
