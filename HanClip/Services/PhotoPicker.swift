import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PhotoPicker: UIViewControllerRepresentable {
    let onComplete: ([ClipItem]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 0
        configuration.selection = .ordered

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: PHPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onComplete: ([ClipItem]) -> Void

        init(onComplete: @escaping ([ClipItem]) -> Void) {
            self.onComplete = onComplete
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            picker.dismiss(animated: true)

            Task { @MainActor in
                var items: [ClipItem] = []
                for result in results {
                    if let identifier = result.assetIdentifier,
                       let asset = PhotoLibraryService.asset(
                        localIdentifier: identifier
                       ),
                       let thumbnail = try? await PhotoLibraryService.thumbnail(
                        for: asset
                       ) {
                        if asset.mediaType == .video,
                           let item = try? await Self.makeVideoItem(
                            asset: asset,
                            thumbnail: thumbnail
                           ) {
                            items.append(item)
                            continue
                        }
                        let isLive = asset.mediaSubtypes.contains(.photoLive)
                        let duration = isLive
                            ? (try? await PhotoLibraryService
                                .livePhotoVideoDuration(for: asset)) ?? 4
                            : 4
                        items.append(
                            ClipItem(
                                source: .photoAsset(
                                    localIdentifier: identifier
                                ),
                                thumbnail: thumbnail,
                                duration: duration,
                                livePhotoDuration: isLive ? duration : nil,
                                isLivePhoto: isLive,
                                livePhotoMode: isLive ? .motion : .still,
                                mediaKind: isLive ? .livePhoto : .photo,
                                sourceDuration: isLive ? duration : nil,
                                sourcePixelSize: CGSize(
                                    width: asset.pixelWidth,
                                    height: asset.pixelHeight
                                )
                            )
                        )
                    } else if let item = await Self.loadFallback(result) {
                        items.append(item)
                    }
                }
                onComplete(items)
            }
        }

        @MainActor
        private static func loadFallback(
            _ result: PHPickerResult
        ) async -> ClipItem? {
            if result.itemProvider.hasItemConformingToTypeIdentifier(
                UTType.movie.identifier
            ), let item = try? await loadFallbackVideo(result.itemProvider) {
                return item
            }
            guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else {
                return nil
            }

            return await withCheckedContinuation { continuation in
                result.itemProvider.loadObject(ofClass: UIImage.self) {
                    object,
                    _ in
                    guard let image = object as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.95)
                    else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("jpg")
                    do {
                        try data.write(to: url)
                        continuation.resume(
                            returning: ClipItem(
                                source: .imageFile(url),
                                thumbnail: image,
                                sourcePixelSize: image.size
                            )
                        )
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        private static func makeVideoItem(
            asset: PHAsset,
            thumbnail: UIImage
        ) async throws -> ClipItem {
            let url = try await PhotoLibraryService.exportVideo(for: asset)
            let duration = try await PhotoLibraryService.videoDuration(at: url)
            let analysis = try? await AudioAnalysisService.analyze(url: url)
            let selectedDuration = min(4, duration)
            let peak = analysis?.peakTime ?? duration / 2
            let start = max(
                0,
                min(duration - selectedDuration, peak - selectedDuration / 2)
            )
            return ClipItem(
                source: .videoFile(url),
                thumbnail: thumbnail,
                duration: selectedDuration,
                photoDuration: selectedDuration,
                mediaKind: .video,
                sourceDuration: duration,
                trimStart: start,
                audioWaveform: analysis?.waveform ?? [],
                audioPeakTime: peak,
                sourcePixelSize: CGSize(
                    width: asset.pixelWidth,
                    height: asset.pixelHeight
                )
            )
        }

        private static func loadFallbackVideo(
            _ provider: NSItemProvider
        ) async throws -> ClipItem {
            let url = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<URL, Error>) in
                provider.loadFileRepresentation(
                    forTypeIdentifier: UTType.movie.identifier
                ) { source, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let source else {
                        continuation.resume(
                            throwing: MediaError.videoTrackUnavailable
                        )
                        return
                    }
                    do {
                        let target = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(
                                source.pathExtension.isEmpty
                                    ? "mov"
                                    : source.pathExtension
                            )
                        try FileManager.default.copyItem(
                            at: source,
                            to: target
                        )
                        continuation.resume(returning: target)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            let asset = AVURLAsset(url: url)
            let duration = try await PhotoLibraryService.videoDuration(at: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            let thumbnail = UIImage(cgImage: cgImage)
            let analysis = try? await AudioAnalysisService.analyze(url: url)
            let selectedDuration = min(4, duration)
            let peak = analysis?.peakTime ?? duration / 2
            let start = max(
                0,
                min(duration - selectedDuration, peak - selectedDuration / 2)
            )
            return ClipItem(
                source: .videoFile(url),
                thumbnail: thumbnail,
                duration: selectedDuration,
                photoDuration: selectedDuration,
                mediaKind: .video,
                sourceDuration: duration,
                trimStart: start,
                audioWaveform: analysis?.waveform ?? [],
                audioPeakTime: peak,
                sourcePixelSize: thumbnail.size
            )
        }
    }
}
