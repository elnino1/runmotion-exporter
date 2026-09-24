//
//  ShareViewController.swift
//  runmotion_exporterShare
//
//  Share-sheet entry point: hosts the SwiftUI review screen for the shared screenshot.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let model = WorkoutReviewModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let host = UIHostingController(rootView: WorkoutReviewView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        model.phase = .reading("Lecture de la capture…")
        Task {
            guard let data = await SharedImageLoader.firstImageData(in: providers) else {
                model.readingNotice = "Aucune image reçue. Ajoute les étapes à la main."
                model.phase = .editing
                return
            }
            await model.read(imageData: data)
        }
    }
}

/// Loads the shared image, which Photos hands over as a file URL and the screenshot
/// editor as a `UIImage`. Nonisolated because `NSItemProvider` calls back on any queue.
nonisolated enum SharedImageLoader {
    static func firstImageData(in providers: [NSItemProvider]) async -> Data? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let data = await imageData(from: provider) {
                return data
            }
        }
        return nil
    }

    private static func imageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                let data: Data? = switch item {
                case let url as URL: try? Data(contentsOf: url)
                case let image as UIImage: image.pngData()
                case let data as Data: data
                default: nil
                }
                continuation.resume(returning: data)
            }
        }
    }
}
