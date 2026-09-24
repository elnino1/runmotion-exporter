//
//  WorkoutKitBuilder.swift
//  Shared (app + share extension)
//

import Foundation
import HealthKit
import WorkoutKit

/// Maps reviewed plan steps to a WorkoutKit `CustomWorkout`.
enum WorkoutKitBuilder {
    static let defaultSpeedToleranceKmh = 0.5
    static let heartRateToleranceBpm = 5

    struct Result {
        var workout: CustomWorkout
        /// Human-readable notes about targets WorkoutKit refused and that were left out.
        var warnings: [String]
    }

    static func build(from steps: [PlanStep], location: RunLocation) -> Result {
        var warnings: [String] = []
        let step = { (planStep: PlanStep) in
            workoutStep(for: planStep, location: location, warnings: &warnings)
        }

        var remaining = steps[...]

        var warmup: WorkoutStep?
        if let first = remaining.first, first.kind == .warmup {
            warmup = step(first)
            remaining = remaining.dropFirst()
        }

        var cooldown: WorkoutStep?
        if let last = remaining.last, last.kind == .cooldown {
            cooldown = step(last)
            remaining = remaining.dropLast()
        }

        // Each work step opens its own block; a recovery right after it joins that block.
        // Pyramids have a different duration per rep, so no attempt is made to merge
        // identical blocks into iterations.
        var blocks: [IntervalBlock] = []
        for planStep in remaining {
            let purpose: IntervalStep.Purpose = planStep.kind == .recovery ? .recovery : .work
            let interval = IntervalStep(purpose, step: step(planStep))
            if purpose == .recovery, let last = blocks.last,
               last.steps.count == 1, last.steps[0].purpose == .work {
                blocks[blocks.count - 1].steps.append(interval)
            } else {
                blocks.append(IntervalBlock(steps: [interval], iterations: 1))
            }
        }

        let workout = CustomWorkout(
            activity: .running,
            location: location.hkLocation,
            displayName: location.workoutDisplayName,
            warmup: warmup,
            blocks: blocks,
            cooldown: cooldown
        )
        return Result(workout: workout, warnings: warnings)
    }

    private static func workoutStep(for step: PlanStep, location: RunLocation, warnings: inout [String]) -> WorkoutStep {
        let goal = WorkoutGoal.time(Double(step.durationSeconds), .seconds)
        if !CustomWorkout.supportsGoal(goal, activity: .running, location: location.hkLocation) {
            warnings.append("Durée non prise en charge par la montre : \(step.summary)")
        }
        guard let alert = alert(for: step) else {
            return WorkoutStep(goal: goal)
        }
        guard CustomWorkout.supportsAlert(alert, activity: .running, location: location.hkLocation) else {
            warnings.append("Cible ignorée (non prise en charge en \(location.label)) : \(step.summary)")
            return WorkoutStep(goal: goal)
        }
        return WorkoutStep(goal: goal, alert: alert)
    }

    /// Speed wins over heart rate when a step has both: RunMotion plans are paced by speed.
    private static func alert(for step: PlanStep) -> (any WorkoutAlert)? {
        if let speed = step.speedKmh {
            let tolerance = step.speedToleranceKmh ?? defaultSpeedToleranceKmh
            let low = Measurement(value: max(speed - tolerance, 0), unit: UnitSpeed.kilometersPerHour)
            let high = Measurement(value: speed + tolerance, unit: UnitSpeed.kilometersPerHour)
            return SpeedRangeAlert(target: low...high, metric: .current)
        }
        if let bpm = step.heartRateBpm {
            let low = Double(bpm - heartRateToleranceBpm)
            let high = Double(bpm + heartRateToleranceBpm)
            return HeartRateRangeAlert.heartRate(low...high)
        }
        return nil
    }
}
