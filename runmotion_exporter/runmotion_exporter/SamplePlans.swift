//
//  SamplePlans.swift
//  runmotion_exporter
//
//  Hard-coded plans to test sending to the Watch without a screenshot.
//

import Foundation

enum SamplePlan: String, CaseIterable, Identifiable {
    case quickTest, pyramid

    var id: Self { self }

    var label: String {
        switch self {
        case .quickTest: "Test rapide (4 min)"
        case .pyramid: "Pyramide"
        }
    }

    var steps: [PlanStep] {
        switch self {
        case .quickTest:
            [
                PlanStep(kind: .warmup, durationSeconds: 60),
                PlanStep(kind: .work, durationSeconds: 30, speedKmh: 10, speedToleranceKmh: 0.5),
                PlanStep(kind: .recovery, durationSeconds: 30),
                PlanStep(kind: .work, durationSeconds: 60, speedKmh: 11, speedToleranceKmh: 0.5),
                PlanStep(kind: .recovery, durationSeconds: 30),
                PlanStep(kind: .cooldown, durationSeconds: 30),
            ]
        case .pyramid:
            [PlanStep(kind: .warmup, durationSeconds: 15 * 60)]
                + [1, 2, 3, 2, 1].flatMap { minutes in
                    [
                        PlanStep(kind: .work, durationSeconds: minutes * 60, speedKmh: 12, speedToleranceKmh: 0.5),
                        PlanStep(kind: .recovery, durationSeconds: 90),
                    ]
                }
                + [PlanStep(kind: .cooldown, durationSeconds: 10 * 60)]
        }
    }
}
