//
//  WatchScheduler.swift
//  Shared (app + share extension)
//

import Foundation
import WorkoutKit

/// Schedules workouts on the paired Apple Watch through `WorkoutScheduler`.
enum WatchScheduler {
    static var isSupported: Bool { WorkoutScheduler.isSupported }

    static func authorizationState() async -> WorkoutScheduler.AuthorizationState {
        await WorkoutScheduler.shared.authorizationState
    }

    static func requestAuthorization() async -> WorkoutScheduler.AuthorizationState {
        await WorkoutScheduler.shared.requestAuthorization()
    }

    static func scheduledWorkouts() async -> [ScheduledWorkoutPlan] {
        await WorkoutScheduler.shared.scheduledWorkouts
    }

    static func remove(_ scheduled: ScheduledWorkoutPlan) async {
        await WorkoutScheduler.shared.remove(scheduled.plan, at: scheduled.date)
    }

    /// Replaces any scheduled workout with the same display name, then schedules this one now,
    /// so each location (Tapis / Extérieur) keeps a single slot on the Watch.
    /// Returns how many previous workouts were removed.
    @discardableResult
    static func send(_ workout: CustomWorkout) async throws -> Int {
        try await ensureAuthorized()
        var removed = 0
        for scheduled in await scheduledWorkouts() where displayName(of: scheduled.plan) == workout.displayName {
            await remove(scheduled)
            removed += 1
        }
        let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: .now)
        await WorkoutScheduler.shared.schedule(WorkoutPlan(.custom(workout)), at: now)
        return removed
    }

    enum SchedulerError: LocalizedError {
        case notAuthorized(WorkoutScheduler.AuthorizationState)

        var errorDescription: String? {
            switch self {
            case .notAuthorized(.notDetermined):
                "Programmation sur la montre pas encore autorisée. "
                    + "Ouvre l'app RunMotion Exporter une fois et touche « Autoriser »."
            case .notAuthorized(let state):
                "Programmation sur la montre non autorisée (\(state)). "
                    + "Réactive l'accès dans Réglages > Santé > Accès aux données et appareils."
            }
        }
    }

    /// Scheduling (unlike the system preview sheet) requires WorkoutKit authorization:
    /// ask for it on first use, fail with a readable error if it was denied.
    static func ensureAuthorized() async throws {
        var state = await authorizationState()
        if state == .notDetermined {
            state = await requestAuthorization()
        }
        guard state == .authorized else {
            throw SchedulerError.notAuthorized(state)
        }
    }

    static func displayName(of plan: WorkoutPlan) -> String? {
        if case .custom(let workout) = plan.workout {
            return workout.displayName
        }
        return nil
    }
}

/// WorkoutKit doesn't mark this plain `Int` enum as `Sendable`, but it holds no mutable state,
/// so it's safe to pass across actors (e.g. from `WorkoutScheduler` back to the main actor).
extension WorkoutScheduler.AuthorizationState: @retroactive @unchecked Sendable {}
