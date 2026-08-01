import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FilePicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onComplete: (Result<[URL], Error>) -> Void

    func makeUIViewController(
        context: Context
    ) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedContentTypes,
            asCopy: false
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: (Result<[URL], Error>) -> Void

        init(onComplete: @escaping (Result<[URL], Error>) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onComplete(.success(urls))
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            onComplete(.success([]))
        }
    }
}
