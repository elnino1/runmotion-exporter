//
//  WorkoutReviewView.swift
//  Shared (app + share extension)
//

import SwiftUI
import WorkoutKit

/// Review/correct the parsed steps, pick Tapis/Extérieur, send to the Watch.
struct WorkoutReviewView: View {
    @Bindable var model: WorkoutReviewModel
    let onClose: () -> Void

    @State private var previewPlan: WorkoutPlan?
    @State private var showPreview = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Séance RunMotion")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .workoutPreview(previewPlan ?? WorkoutPlan(.custom(model.build.workout)), isPresented: $showPreview)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .reading(let message):
            ProgressView(message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .sent(let message):
            ContentUnavailableView {
                Label("Envoyé", systemImage: "applewatch.radiowaves.left.and.right")
            } description: {
                Text(message + "\nOuvre Exercice sur la montre, la séance apparaît dans les entraînements programmés.")
            } actions: {
                Button("Terminé", action: onClose)
                    .buttonStyle(.borderedProminent)
            }
        case .editing, .sending:
            form
        }
    }

    private var form: some View {
        Form {
            if let notice = model.readingNotice {
                Section {
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Picker("Lieu", selection: $model.location) {
                    ForEach(RunLocation.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach($model.steps) { $step in
                    NavigationLink {
                        StepEditorView(step: $step)
                    } label: {
                        Text(step.summary)
                    }
                }
                .onDelete { model.steps.remove(atOffsets: $0) }
                .onMove { model.steps.move(fromOffsets: $0, toOffset: $1) }
                Button("Ajouter une étape", systemImage: "plus") {
                    model.addStep()
                }
            } header: {
                Text("Étapes")
            } footer: {
                if !model.steps.isEmpty {
                    Text("Durée totale : \(PlanStep.formatDuration(model.totalSeconds))")
                }
            }

            let warnings = model.build.warnings
            if !warnings.isEmpty {
                Section("Avertissements") {
                    ForEach(warnings, id: \.self) { Text($0).font(.footnote) }
                }
            }

            if let error = model.sendError {
                Section {
                    Label(error, systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await model.send() }
                } label: {
                    HStack {
                        Text("Envoyer à la montre")
                        if model.phase == .sending {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!model.canSend)

                Button("Aperçu système (ajout manuel)") {
                    previewPlan = WorkoutPlan(.custom(model.build.workout))
                    showPreview = true
                }
                .disabled(!model.canSend)
            } footer: {
                Text("Remplace la séance « \(model.location.workoutDisplayName) » déjà programmée, s'il y en a une.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Fermer", action: onClose)
        }
        if case .editing = model.phase, !model.steps.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
    }
}

private struct StepEditorView: View {
    @Binding var step: PlanStep

    var body: some View {
        Form {
            Picker("Type", selection: $step.kind) {
                ForEach(PlanStep.Kind.allCases) { Text($0.label).tag($0) }
            }

            Section("Durée") {
                HStack(spacing: 0) {
                    Picker("Minutes", selection: minutes) {
                        ForEach(0..<181) { Text("\($0) min").tag($0) }
                    }
                    Picker("Secondes", selection: seconds) {
                        ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text("\($0) s").tag($0) }
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 140)
            }

            Section {
                Toggle("Vitesse cible", isOn: hasSpeed)
                if step.speedKmh != nil {
                    LabeledContent("Vitesse (km/h)") {
                        TextField("km/h", value: $step.speedKmh, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Tolérance ± (km/h)") {
                        TextField("km/h", value: tolerance, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                Text("La montre alerte quand la vitesse sort de la plage.")
            }

            Section {
                Toggle("Fréquence cardiaque cible", isOn: hasHeartRate)
                if step.heartRateBpm != nil {
                    LabeledContent("Fréquence (bpm)") {
                        TextField("bpm", value: $step.heartRateBpm, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                Text("Utilisée seulement si aucune vitesse n'est fixée (± \(WorkoutKitBuilder.heartRateToleranceBpm) bpm).")
            }
        }
        .navigationTitle(step.kind.label)
    }

    private var minutes: Binding<Int> {
        Binding(
            get: { step.durationSeconds / 60 },
            set: { step.durationSeconds = max($0 * 60 + step.durationSeconds % 60, 5) }
        )
    }

    private var seconds: Binding<Int> {
        Binding(
            get: { step.durationSeconds % 60 / 5 * 5 },
            set: { step.durationSeconds = max(step.durationSeconds / 60 * 60 + $0, 5) }
        )
    }

    private var tolerance: Binding<Double?> {
        Binding(
            get: { step.speedToleranceKmh ?? WorkoutKitBuilder.defaultSpeedToleranceKmh },
            set: { step.speedToleranceKmh = $0 }
        )
    }

    private var hasSpeed: Binding<Bool> {
        Binding(
            get: { step.speedKmh != nil },
            set: { step.speedKmh = $0 ? (step.speedKmh ?? 10) : nil }
        )
    }

    private var hasHeartRate: Binding<Bool> {
        Binding(
            get: { step.heartRateBpm != nil },
            set: { step.heartRateBpm = $0 ? (step.heartRateBpm ?? 150) : nil }
        )
    }
}

#Preview {
    WorkoutReviewView(
        model: WorkoutReviewModel(steps: [
            PlanStep(kind: .warmup, durationSeconds: 900),
            PlanStep(kind: .work, durationSeconds: 60, speedKmh: 12),
            PlanStep(kind: .recovery, durationSeconds: 90),
            PlanStep(kind: .cooldown, durationSeconds: 600),
        ]),
        onClose: {}
    )
}
