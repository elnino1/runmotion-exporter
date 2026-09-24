//
//  WorkoutPlanParser.swift
//  Shared (app + share extension)
//

import Foundation
import FoundationModels

/// Turns OCR'd RunMotion text into plan steps with the on-device Foundation Models.
///
/// The model only transcribes what the screenshot says (blocks, repetitions, durations,
/// speeds or paces); unit conversion and repetition expansion happen in `steps(from:)`,
/// which is plain code and unit-tested.
enum WorkoutPlanParser {
    static let maxRepetitions = 30

    enum ParserError: LocalizedError {
        case modelUnavailable(SystemLanguageModel.Availability.UnavailableReason)
        case noText

        var errorDescription: String? {
            switch self {
            case .modelUnavailable(.appleIntelligenceNotEnabled):
                "Apple Intelligence est désactivé (Réglages > Apple Intelligence et Siri)."
            case .modelUnavailable(.modelNotReady):
                "Le modèle Apple Intelligence n'est pas encore prêt (téléchargement en cours ?)."
            case .modelUnavailable(.deviceNotEligible):
                "Cet appareil ne prend pas en charge Apple Intelligence."
            case .modelUnavailable:
                "Apple Intelligence n'est pas disponible."
            case .noText:
                "Aucun texte trouvé dans la capture."
            }
        }
    }

    static func parse(_ text: String) async throws -> [PlanStep] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParserError.noText
        }
        let model = SystemLanguageModel.default
        if case .unavailable(let reason) = model.availability {
            throw ParserError.modelUnavailable(reason)
        }
        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: "Texte de la capture :\n\n\(text)",
            generating: GeneratedPlan.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        return steps(from: response.content)
    }

    // MARK: - Mapping (pure)

    static func steps(from plan: GeneratedPlan) -> [PlanStep] {
        plan.blocks.flatMap { block in
            let steps = block.steps.compactMap { planStep(from: $0) }
            let repetitions = min(max(block.repetitions, 1), maxRepetitions)
            return (0..<repetitions).flatMap { _ in
                steps.map { step in
                    var copy = step
                    copy.id = UUID()
                    return copy
                }
            }
        }
    }

    /// Returns `nil` for a step without a usable duration (or distance + speed to derive one).
    static func planStep(from generated: GeneratedStep) -> PlanStep? {
        var speed: Double?
        var tolerance: Double?
        if let low = generated.speedKmh, low > 0 {
            if let high = generated.speedMaxKmh, high > low {
                speed = (low + high) / 2
                tolerance = (high - low) / 2
            } else {
                speed = low
            }
        } else if let pace = generated.paceSecondsPerKm, pace > 0 {
            speed = (3600 / Double(pace) * 10).rounded() / 10
        }

        var duration = generated.durationSeconds.flatMap { $0 > 0 ? $0 : nil }
        if duration == nil, let meters = generated.distanceMeters, meters > 0, let speed {
            duration = Int((Double(meters) / (speed / 3.6)).rounded())
        }
        guard let duration else { return nil }

        return PlanStep(
            kind: kind(of: generated.kind),
            durationSeconds: duration,
            speedKmh: speed,
            speedToleranceKmh: tolerance,
            heartRateBpm: generated.heartRateBpm.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    private static func kind(of kind: GeneratedStepKind) -> PlanStep.Kind {
        switch kind {
        case .warmup: .warmup
        case .work: .work
        case .recovery: .recovery
        case .cooldown: .cooldown
        }
    }

    // MARK: - Prompt

    static let instructions = """
        Tu lis le texte (issu d'une reconnaissance de caractères) d'une capture d'écran \
        de l'application RunMotion Coach qui décrit une séance de course à pied, et tu la \
        transcris en blocs structurés.

        Règles :
        - Ignore tout ce qui n'est pas la séance (heure, batterie, menus, conseils, titres).
        - Garde l'ordre de la séance.
        - Types d'étape : warmup = échauffement, work = effort / fractionné / rapide / \
        allure spécifique, recovery = récupération / récup / trot / marche / repos, \
        cooldown = retour au calme.
        - Un bloc répété (« 3 x », « 3× », « à répéter 3 fois ») a repetitions = 3 et ne \
        contient les étapes que d'une seule répétition. Sinon repetitions = 1.
        - Une pyramide ou des fractions de durées différentes s'écrivent étape par étape, \
        dans un bloc à repetitions = 1.
        - durationSeconds : durée en secondes. 1'30 ou 1:30 ou 1 min 30 = 90 ; 15' ou \
        15 min = 900 ; 45" ou 45 s = 45 ; 1h05 = 3900.
        - distanceMeters : seulement si l'étape est définie par une distance (400 m = 400, \
        1 km = 1000, 1,5 km = 1500) et non par une durée.
        - speedKmh : vitesse en km/h si elle est indiquée (virgule décimale : 12,5 = 12.5). \
        Pour une plage « 11-12 km/h », speedKmh = 11 et speedMaxKmh = 12.
        - paceSecondsPerKm : allure en secondes par km si une allure est indiquée au lieu \
        d'une vitesse (5'00/km = 300, 4:45 min/km = 285).
        - heartRateBpm : fréquence cardiaque cible en battements par minute si indiquée.
        - Laisse vide toute valeur absente de la capture. N'invente rien.
        """
}

// MARK: - Guided generation types

@Generable(description: "Séance de course à pied transcrite depuis la capture")
nonisolated struct GeneratedPlan {
    @Guide(description: "Blocs de la séance, dans l'ordre")
    var blocks: [GeneratedBlock]

    init(blocks: [GeneratedBlock]) {
        self.blocks = blocks
    }
}

@Generable
nonisolated struct GeneratedBlock {
    @Guide(description: "Nombre de répétitions du bloc, 1 s'il n'est pas répété")
    var repetitions: Int
    @Guide(description: "Étapes d'une seule répétition, dans l'ordre")
    var steps: [GeneratedStep]

    init(repetitions: Int = 1, steps: [GeneratedStep]) {
        self.repetitions = repetitions
        self.steps = steps
    }
}

@Generable
nonisolated enum GeneratedStepKind {
    case warmup, work, recovery, cooldown
}

@Generable
nonisolated struct GeneratedStep {
    var kind: GeneratedStepKind
    @Guide(description: "Durée de l'étape en secondes")
    var durationSeconds: Int?
    @Guide(description: "Distance de l'étape en mètres, seulement si elle n'a pas de durée")
    var distanceMeters: Int?
    @Guide(description: "Vitesse cible en km/h, ou borne basse d'une plage de vitesses")
    var speedKmh: Double?
    @Guide(description: "Borne haute d'une plage de vitesses en km/h")
    var speedMaxKmh: Double?
    @Guide(description: "Allure cible en secondes par kilomètre")
    var paceSecondsPerKm: Int?
    @Guide(description: "Fréquence cardiaque cible en battements par minute")
    var heartRateBpm: Int?

    init(
        kind: GeneratedStepKind,
        durationSeconds: Int? = nil,
        distanceMeters: Int? = nil,
        speedKmh: Double? = nil,
        speedMaxKmh: Double? = nil,
        paceSecondsPerKm: Int? = nil,
        heartRateBpm: Int? = nil
    ) {
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.speedKmh = speedKmh
        self.speedMaxKmh = speedMaxKmh
        self.paceSecondsPerKm = paceSecondsPerKm
        self.heartRateBpm = heartRateBpm
    }
}
