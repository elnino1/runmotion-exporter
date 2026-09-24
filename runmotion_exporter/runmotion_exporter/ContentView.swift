//
//  ContentView.swift
//  runmotion_exporter
//
//  One-time setup (authorization) + how-to. The regular flow lives in the share extension;
//  importing from Photos here runs the same review screen, as a fallback.
//

import PhotosUI
import SwiftUI
import WorkoutKit

struct ContentView: View {
    @State private var authorization: WorkoutScheduler.AuthorizationState?
    @State private var scheduled: [ScheduledWorkoutPlan] = []
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var review: WorkoutReviewModel?

    var body: some View {
        NavigationStack {
            Form {
                Section("Autorisation") {
                    LabeledContent("Programmation sur la montre", value: authorizationLabel)
                    if authorization != .authorized {
                        Button("Autoriser") {
                            Task { await requestAuthorization() }
                        }
                    }
                    if !WatchScheduler.isSupported {
                        Text("WorkoutKit n'est pas pris en charge sur cet appareil.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Mode d'emploi") {
                    Label("Fais une capture du plan du jour dans RunMotion.", systemImage: "1.circle")
                    Label("Touche Partager, puis « RunMotion Montre ».", systemImage: "2.circle")
                    Label("Vérifie les étapes, choisis Tapis ou Extérieur.", systemImage: "3.circle")
                    Label("Touche « Envoyer à la montre ».", systemImage: "4.circle")
                }

                Section {
                    PhotosPicker(selection: $pickedPhoto, matching: .screenshots) {
                        Label("Importer une capture", systemImage: "photo")
                    }
                    Button("Saisir une séance à la main", systemImage: "square.and.pencil") {
                        review = WorkoutReviewModel()
                    }
                    Menu {
                        ForEach(SamplePlan.allCases) { sample in
                            Button(sample.label) {
                                review = WorkoutReviewModel(steps: sample.steps)
                            }
                        }
                    } label: {
                        Label("Séance de test", systemImage: "testtube.2")
                    }
                } footer: {
                    Text("Sans passer par le partage.")
                }

                Section("Programmés sur la montre") {
                    if scheduled.isEmpty {
                        Text("Aucun").foregroundStyle(.secondary)
                    }
                    ForEach(scheduled.indices, id: \.self) { index in
                        let item = scheduled[index]
                        VStack(alignment: .leading) {
                            Text(WatchScheduler.displayName(of: item.plan) ?? "Sans nom")
                            Text(item.date.date.map { $0.formatted() } ?? "\(item.date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        Task { await remove(at: offsets) }
                    }
                }
            }
            .navigationTitle("RunMotion Montre")
            .refreshable { await refresh() }
            .task { await refresh() }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                pickedPhoto = nil
                let model = WorkoutReviewModel()
                model.phase = .reading("Lecture de la capture…")
                review = model
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        model.readingNotice = "Impossible de charger l'image. Ajoute les étapes à la main."
                        model.phase = .editing
                        return
                    }
                    await model.read(imageData: data)
                }
            }
            .sheet(item: $review, onDismiss: { Task { await refresh() } }) { model in
                WorkoutReviewView(model: model) { review = nil }
            }
        }
    }

    private var authorizationLabel: String {
        switch authorization {
        case nil: "…"
        case .authorized?: "Autorisée"
        case .notDetermined?: "À demander"
        case .denied?: "Refusée (Réglages > Santé)"
        case let state?: "\(state)"
        }
    }

    private func requestAuthorization() async {
        _ = await WatchScheduler.requestAuthorization()
        await refresh()
    }

    private func remove(at offsets: IndexSet) async {
        for index in offsets {
            await WatchScheduler.remove(scheduled[index])
        }
        await refresh()
    }

    private func refresh() async {
        authorization = await WatchScheduler.authorizationState()
        scheduled = await WatchScheduler.scheduledWorkouts()
    }
}

#Preview {
    ContentView()
}
