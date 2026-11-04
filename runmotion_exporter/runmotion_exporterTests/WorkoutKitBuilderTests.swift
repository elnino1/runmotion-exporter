//
//  WorkoutKitBuilderTests.swift
//  runmotion_exporterTests
//

import Foundation
import HealthKit
import Testing
import WorkoutKit
@testable import runmotion_exporter

struct WorkoutKitBuilderTests {
    private let pyramid: [PlanStep] = [PlanStep(kind: .warmup, durationSeconds: 900)]
        + [1, 2, 3].flatMap { minutes in
            [
                PlanStep(kind: .work, durationSeconds: minutes * 60, speedKmh: 12),
                PlanStep(kind: .recovery, durationSeconds: 90),
            ]
        }
        + [PlanStep(kind: .cooldown, durationSeconds: 600)]

    @Test func mapsWarmupBlocksAndCooldown() {
        let workout = WorkoutKitBuilder.build(from: pyramid, location: .exterieur).workout

        #expect(workout.activity == .running)
        #expect(workout.location == .outdoor)
        #expect(workout.displayName == "RunMotion - Extérieur")
        #expect(workout.warmup?.goal == .time(900, .seconds))
        #expect(workout.cooldown?.goal == .time(600, .seconds))
        #expect(workout.blocks.count == 3)
        #expect(workout.blocks.allSatisfy { $0.iterations == 1 })
        #expect(workout.blocks.map { $0.steps.map(\.purpose) } == Array(repeating: [.work, .recovery], count: 3))
        #expect(workout.blocks.map { $0.steps[0].step.goal } == [.time(60, .seconds), .time(120, .seconds), .time(180, .seconds)])
    }

    @Test func tapisIsIndoor() {
        let workout = WorkoutKitBuilder.build(from: pyramid, location: .tapis).workout
        #expect(workout.location == .indoor)
        #expect(workout.displayName == "RunMotion - Tapis")
    }

    @Test func speedBecomesRangeAlert() throws {
        let steps = [PlanStep(kind: .work, durationSeconds: 60, speedKmh: 12, speedToleranceKmh: 0.3)]
        let workout = WorkoutKitBuilder.build(from: steps, location: .exterieur).workout

        let alert = try #require(workout.blocks.first?.steps.first?.step.alert as? SpeedRangeAlert)
        #expect(abs(alert.target.lowerBound.converted(to: .kilometersPerHour).value - 11.7) < 0.001)
        #expect(abs(alert.target.upperBound.converted(to: .kilometersPerHour).value - 12.3) < 0.001)
    }

    @Test func recoveryWithoutTargetHasNoAlert() {
        let steps = [PlanStep(kind: .work, durationSeconds: 60), PlanStep(kind: .recovery, durationSeconds: 60)]
        let workout = WorkoutKitBuilder.build(from: steps, location: .exterieur).workout
        #expect(workout.blocks.first?.steps.allSatisfy { $0.step.alert == nil } == true)
    }

    @Test func consecutiveRecoveriesStartNewBlocks() {
        let steps = [
            PlanStep(kind: .work, durationSeconds: 60),
            PlanStep(kind: .recovery, durationSeconds: 60),
            PlanStep(kind: .recovery, durationSeconds: 60),
        ]
        let workout = WorkoutKitBuilder.build(from: steps, location: .exterieur).workout
        #expect(workout.blocks.map(\.steps.count) == [2, 1])
    }

    @Test func roundTripsThroughDataRepresentation() throws {
        let plan = WorkoutPlan(.custom(WorkoutKitBuilder.build(from: pyramid, location: .tapis).workout))
        let decoded = try WorkoutPlan(from: plan.dataRepresentation)

        guard case .custom(let workout) = decoded.workout else {
            Issue.record("expected a custom workout")
            return
        }
        #expect(workout.displayName == "RunMotion - Tapis")
        #expect(workout.blocks.count == 3)
    }
}
