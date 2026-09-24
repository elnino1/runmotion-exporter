//
//  WorkoutPlanParserTests.swift
//  runmotion_exporterTests
//
//  Mapping from guided-generation output to plan steps (no live model call).
//

import Testing
@testable import runmotion_exporter

struct WorkoutPlanParserTests {
    @Test func expandsRepeatedBlocks() {
        let plan = GeneratedPlan(blocks: [
            GeneratedBlock(steps: [GeneratedStep(kind: .warmup, durationSeconds: 900)]),
            GeneratedBlock(repetitions: 3, steps: [
                GeneratedStep(kind: .work, durationSeconds: 60, speedKmh: 12),
                GeneratedStep(kind: .recovery, durationSeconds: 90),
            ]),
            GeneratedBlock(steps: [GeneratedStep(kind: .cooldown, durationSeconds: 600)]),
        ])

        let steps = WorkoutPlanParser.steps(from: plan)

        #expect(steps.map(\.kind) == [.warmup, .work, .recovery, .work, .recovery, .work, .recovery, .cooldown])
        #expect(steps.map(\.durationSeconds) == [900, 60, 90, 60, 90, 60, 90, 600])
        #expect(Set(steps.map(\.id)).count == steps.count, "repeated steps need distinct ids for SwiftUI")
    }

    @Test func pyramidKeepsEachDuration() {
        let plan = GeneratedPlan(blocks: [
            GeneratedBlock(steps: [1, 2, 3, 2, 1].map { GeneratedStep(kind: .work, durationSeconds: $0 * 60, speedKmh: 12) }),
        ])

        #expect(WorkoutPlanParser.steps(from: plan).map(\.durationSeconds) == [60, 120, 180, 120, 60])
    }

    @Test func clampsRepetitions() {
        let step = GeneratedStep(kind: .work, durationSeconds: 30)
        #expect(WorkoutPlanParser.steps(from: GeneratedPlan(blocks: [GeneratedBlock(repetitions: 0, steps: [step])])).count == 1)
        #expect(WorkoutPlanParser.steps(from: GeneratedPlan(blocks: [GeneratedBlock(repetitions: 500, steps: [step])])).count
            == WorkoutPlanParser.maxRepetitions)
    }

    @Test func speedRangeBecomesCenterAndTolerance() throws {
        let step = try #require(WorkoutPlanParser.planStep(from: GeneratedStep(kind: .work, durationSeconds: 60, speedKmh: 11, speedMaxKmh: 12)))
        #expect(step.speedKmh == 11.5)
        #expect(step.speedToleranceKmh == 0.5)
    }

    @Test func singleSpeedKeepsDefaultTolerance() throws {
        let step = try #require(WorkoutPlanParser.planStep(from: GeneratedStep(kind: .work, durationSeconds: 60, speedKmh: 12.5)))
        #expect(step.speedKmh == 12.5)
        #expect(step.speedToleranceKmh == nil)
    }

    @Test func paceIsConvertedToSpeed() throws {
        let fiveMinutes = try #require(WorkoutPlanParser.planStep(from: GeneratedStep(kind: .work, durationSeconds: 60, paceSecondsPerKm: 300)))
        #expect(fiveMinutes.speedKmh == 12)
        let fourFifty = try #require(WorkoutPlanParser.planStep(from: GeneratedStep(kind: .work, durationSeconds: 60, paceSecondsPerKm: 290)))
        #expect(fourFifty.speedKmh == 12.4)
    }

    @Test func distanceIsConvertedToDurationWithSpeed() throws {
        let step = try #require(WorkoutPlanParser.planStep(from: GeneratedStep(kind: .work, distanceMeters: 400, speedKmh: 12)))
        #expect(step.durationSeconds == 120)
    }

    @Test func dropsStepsWithoutUsableDuration() {
        #expect(WorkoutPlanParser.planStep(from: GeneratedStep(kind: .recovery)) == nil)
        #expect(WorkoutPlanParser.planStep(from: GeneratedStep(kind: .recovery, durationSeconds: 0)) == nil)
        #expect(WorkoutPlanParser.planStep(from: GeneratedStep(kind: .work, distanceMeters: 400)) == nil)
    }

    @Test func keepsHeartRateAndIgnoresNonsense() throws {
        let step = try #require(WorkoutPlanParser.planStep(from: GeneratedStep(kind: .work, durationSeconds: 60, speedKmh: -3, heartRateBpm: 165)))
        #expect(step.speedKmh == nil)
        #expect(step.heartRateBpm == 165)
    }
}
