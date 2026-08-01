import AVFoundation
import OSLog
import Photos
import UIKit

final class VideoComposer {
    private let logger = Logger(
        subsystem: "com.hanclip.app",
        category: "VideoComposer"
    )
    private let frameRate: Int32 = 30

    func compose(
        items: [ClipItem],
        renderSize requestedRenderSize: CGSize,
        progressHandler: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        guard !items.isEmpty else {
            throw MediaError.exportFailed("선택된 사진이 없습니다.")
        }
        let renderSize = Self.codecSafeRenderSize(requestedRenderSize)
        logger.info(
            "영상 생성 시작: 요청 \(Int(requestedRenderSize.width))x\(Int(requestedRenderSize.height)), 출력 \(Int(renderSize.width))x\(Int(renderSize.height)), 클립 \(items.count)개"
        )

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MediaError.videoTrackUnavailable
        }
        var compositionAudioTrack: AVMutableCompositionTrack?

        var cursor = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var temporaryFiles: [URL] = []

        defer {
            for url in temporaryFiles {
                try? FileManager.default.removeItem(at: url)
            }
        }

        await progressHandler(0)

        for (itemIndex, item) in items.enumerated() {
            try Task.checkCancellation()
            let resolved = try await resolveSource(
                for: item,
                renderSize: renderSize
            ) { itemProgress in
                let completedItems = Double(itemIndex)
                let overallProgress = (
                    completedItems + itemProgress
                ) / Double(items.count)
                await progressHandler(overallProgress * 0.82)
            }
            if resolved.isTemporary {
                temporaryFiles.append(resolved.url)
            }
            let asset = AVURLAsset(url: resolved.url)
            guard let sourceVideoTrack = try await asset.loadTracks(
                withMediaType: .video
            ).first else {
                throw MediaError.videoTrackUnavailable
            }

            let sourceAudioTrack = try await asset.loadTracks(
                withMediaType: .audio
            ).first
            let sourceDuration = try await asset.load(.duration)
            var requestedDuration = CMTime(
                seconds: max(0.5, item.duration),
                preferredTimescale: 600
            )

            if item.mediaKind == .video
                || (item.isLivePhoto && item.livePhotoMode == .motion) {
                let sourceStart = CMTime(
                    seconds: max(0, item.trimStart),
                    preferredTimescale: 600
                )
                let available = CMTimeMaximum(
                    .zero,
                    CMTimeSubtract(sourceDuration, sourceStart)
                )
                requestedDuration = CMTimeMinimum(
                    requestedDuration,
                    available
                )
                let sourceRange = CMTimeRange(
                    start: sourceStart,
                    duration: requestedDuration
                )
                try compositionVideoTrack.insertTimeRange(
                    sourceRange,
                    of: sourceVideoTrack,
                    at: cursor
                )
                if let sourceAudioTrack {
                    if compositionAudioTrack == nil {
                        compositionAudioTrack = composition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )
                    }
                    try? compositionAudioTrack?.insertTimeRange(
                        sourceRange,
                        of: sourceAudioTrack,
                        at: cursor
                    )
                }
            } else {
                var inserted = CMTime.zero
                while CMTimeCompare(inserted, requestedDuration) < 0 {
                    let remaining = CMTimeSubtract(requestedDuration, inserted)
                    let partDuration = CMTimeMinimum(sourceDuration, remaining)
                    let sourceRange = CMTimeRange(
                        start: .zero,
                        duration: partDuration
                    )
                    let insertionTime = CMTimeAdd(cursor, inserted)

                    try compositionVideoTrack.insertTimeRange(
                        sourceRange,
                        of: sourceVideoTrack,
                        at: insertionTime
                    )

                    if let sourceAudioTrack {
                        if compositionAudioTrack == nil {
                            compositionAudioTrack = composition.addMutableTrack(
                                withMediaType: .audio,
                                preferredTrackID: kCMPersistentTrackID_Invalid
                            )
                        }
                        try? compositionAudioTrack?.insertTimeRange(
                            sourceRange,
                            of: sourceAudioTrack,
                            at: insertionTime
                        )
                    }
                    inserted = CMTimeAdd(inserted, partDuration)
                }
            }

            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(
                .preferredTransform
            )

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(
                assetTrack: compositionVideoTrack
            )
            let fittedTransform = Self.aspectFillTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                renderSize: renderSize
            )
            let itemTimeRange = CMTimeRange(
                start: cursor,
                duration: requestedDuration
            )

            layerInstruction.setTransform(fittedTransform, at: cursor)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = itemTimeRange
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)
            cursor = CMTimeAdd(cursor, requestedDuration)
            await progressHandler(
                Double(itemIndex + 1) / Double(items.count) * 0.82
            )
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: frameRate
        )
        videoComposition.instructions = instructions

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HanClip-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw MediaError.exportFailed("내보내기 세션을 만들 수 없습니다.")
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = videoComposition
        logger.info("내보내기 시작: 사진 랜덤 줌인·줌아웃 합성 적용")
        await progressHandler(0.86)
        try Task.checkCancellation()
        try await export(
            exporter,
            cancellationSession: ExportSessionReference(exporter)
        ) { exportProgress in
            await progressHandler(0.86 + exportProgress * 0.14)
        }

        try Task.checkCancellation()
        guard exporter.status == .completed else {
            let error = exporter.error as NSError?
            logger.error(
                "내보내기 실패: 상태 \(exporter.status.rawValue), 도메인 \(error?.domain ?? "없음", privacy: .public), 코드 \(error?.code ?? 0), 내용 \(error?.localizedDescription ?? "알 수 없는 오류", privacy: .public)"
            )
            throw MediaError.exportFailed(
                error?.localizedDescription ?? "알 수 없는 오류"
            )
        }
        await progressHandler(1)
        logger.info("영상 생성 완료")
        return outputURL
    }

    private func export(
        _ exporter: AVAssetExportSession,
        cancellationSession: ExportSessionReference,
        progressHandler: @escaping @Sendable (Double) async -> Void
    ) async throws {
        try await withTaskCancellationHandler {
            let exportTask = Task {
                await withCheckedContinuation { continuation in
                    exporter.exportAsynchronously {
                        continuation.resume()
                    }
                }
            }

            while exporter.status == .unknown
                || exporter.status == .waiting
                || exporter.status == .exporting {
                try Task.checkCancellation()
                await progressHandler(
                    min(0.99, max(0, Double(exporter.progress)))
                )
                try await Task.sleep(for: .milliseconds(250))
            }

            await exportTask.value
        } onCancel: {
            cancellationSession.value.cancelExport()
        }
    }

    private func resolveSource(
        for item: ClipItem,
        renderSize: CGSize,
        progressHandler: @escaping @Sendable (Double) async -> Void
    ) async throws -> (
        url: URL,
        isTemporary: Bool,
        isNormalizedStill: Bool
    ) {
        if item.isLivePhoto, item.livePhotoMode == .motion {
            await progressHandler(0.20)
            switch item.source {
            case .photoAsset(let identifier):
                guard let asset = PhotoLibraryService.asset(
                    localIdentifier: identifier
                ) else {
                    throw MediaError.livePhotoVideoUnavailable
                }
                let result = (
                    try await PhotoLibraryService.exportPairedVideo(for: asset),
                    true,
                    false
                )
                await progressHandler(1)
                return result
            case .livePhotoFiles(_, let videoURL):
                await progressHandler(1)
                return (videoURL, false, false)
            case .videoFile(let url):
                await progressHandler(1)
                return (url, false, false)
            case .imageFile:
                break
            }
        }

        if case .videoFile(let url) = item.source {
            await progressHandler(1)
            return (url, false, false)
        }

        let image: UIImage
        switch item.source {
        case .photoAsset(let identifier):
            guard let asset = PhotoLibraryService.asset(
                localIdentifier: identifier
            ) else {
                throw MediaError.imageUnavailable
            }
            image = try await PhotoLibraryService.fullImage(for: asset)
        case .imageFile(let url):
            guard let loaded = UIImage(contentsOfFile: url.path) else {
                throw MediaError.imageUnavailable
            }
            image = loaded
        case .livePhotoFiles(let imageURL, _):
            guard let loaded = UIImage(contentsOfFile: imageURL.path) else {
                throw MediaError.imageUnavailable
            }
            image = loaded
        case .videoFile:
            throw MediaError.imageUnavailable
        }

        let url = try await makeStillVideo(
            image: image,
            duration: max(0.5, item.duration),
            renderSize: renderSize,
            progressHandler: progressHandler
        )
        return (url, true, true)
    }

    private func makeStillVideo(
        image: UIImage,
        duration: Double,
        renderSize: CGSize,
        progressHandler: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        let encodingTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("HanClip-Still-\(UUID().uuidString)")
                .appendingPathExtension("mp4")

            let writer = try AVAssetWriter(
                outputURL: outputURL,
                fileType: .mp4
            )
            defer {
                if writer.status == .writing {
                    writer.cancelWriting()
                }
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: outputURL)
                }
            }
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(renderSize.width),
                AVVideoHeightKey: Int(renderSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoProfileLevelKey:
                        AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: settings
            )
            input.expectsMediaDataInRealTime = false

            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String:
                    Int(renderSize.width),
                kCVPixelBufferHeightKey as String:
                    Int(renderSize.height)
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: attributes
            )

            guard writer.canAdd(input) else {
                throw MediaError.exportFailed("사진 영상 트랙을 만들 수 없습니다.")
            }
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)

            guard let pool = adaptor.pixelBufferPool else {
                throw MediaError.exportFailed("영상 버퍼를 만들 수 없습니다.")
            }
            let fps: Int32 = 30
            let frameCount = max(1, Int(ceil(duration * Double(fps))))
            let zoomsIn = Bool.random()
            let focalPoint = Self.randomFocalPoint(in: renderSize)
            let progressInterval = max(1, frameCount / 100)

            for frame in 0..<frameCount {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(2))
                }
                var optionalBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(
                    nil,
                    pool,
                    &optionalBuffer
                )
                guard let pixelBuffer = optionalBuffer else {
                    throw MediaError.exportFailed(
                        "영상 프레임을 만들 수 없습니다."
                    )
                }

                let linearProgress = frameCount > 1
                    ? CGFloat(frame) / CGFloat(frameCount - 1)
                    : 1
                let easedProgress = linearProgress
                    * linearProgress
                    * (3 - 2 * linearProgress)
                let zoomProgress = zoomsIn
                    ? easedProgress
                    : 1 - easedProgress
                let zoomScale = 1 + 0.10 * zoomProgress

                try Self.draw(
                    image: image,
                    into: pixelBuffer,
                    renderSize: renderSize,
                    zoomScale: zoomScale,
                    focalPoint: focalPoint
                )

                let time = CMTime(value: CMTimeValue(frame), timescale: fps)
                guard adaptor.append(pixelBuffer, withPresentationTime: time)
                else {
                    throw MediaError.exportFailed(
                        writer.error?.localizedDescription
                            ?? "사진 프레임을 기록할 수 없습니다."
                    )
                }
                if frame % progressInterval == 0
                    || frame == frameCount - 1 {
                    await progressHandler(
                        Double(frame + 1) / Double(frameCount)
                    )
                }
            }

            input.markAsFinished()
            await writer.finishWriting()

            guard writer.status == .completed else {
                throw MediaError.exportFailed(
                    writer.error?.localizedDescription
                        ?? "사진 영상을 완성할 수 없습니다."
                )
            }
            return outputURL
        }

        return try await withTaskCancellationHandler {
            try await encodingTask.value
        } onCancel: {
            encodingTask.cancel()
        }
    }

    private static func draw(
        image: UIImage,
        into pixelBuffer: CVPixelBuffer,
        renderSize: CGSize,
        zoomScale: CGFloat,
        focalPoint: CGPoint
    ) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: Int(renderSize.width),
                height: Int(renderSize.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else {
            throw MediaError.exportFailed("그래픽 버퍼를 열 수 없습니다.")
        }

        let scale = max(
            renderSize.width / image.size.width,
            renderSize.height / image.size.height
        )
        let drawSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let aspectFillRect = CGRect(
            x: (renderSize.width - drawSize.width) / 2,
            y: (renderSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        let rect = CGRect(
            x: focalPoint.x
                + (aspectFillRect.minX - focalPoint.x) * zoomScale,
            y: focalPoint.y
                + (aspectFillRect.minY - focalPoint.y) * zoomScale,
            width: aspectFillRect.width * zoomScale,
            height: aspectFillRect.height * zoomScale
        )

        // CVPixelBuffer의 좌표계를 UIKit 좌표계로 한 번만 변환한 뒤
        // UIImage를 직접 그린다. UIImage.draw가 EXIF 방향까지 반영하므로
        // 사진이 영상에서 180도 회전하는 이중 변환을 방지한다.
        context.translateBy(x: 0, y: renderSize.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: renderSize))
        image.draw(in: rect)
    }

    private static func aspectFillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let originalRect = CGRect(origin: .zero, size: naturalSize)
        let orientedRect = originalRect.applying(preferredTransform)
        let orientedSize = CGSize(
            width: abs(orientedRect.width),
            height: abs(orientedRect.height)
        )
        let scale = max(
            renderSize.width / orientedSize.width,
            renderSize.height / orientedSize.height
        )
        let scaled = preferredTransform.concatenating(
            CGAffineTransform(scaleX: scale, y: scale)
        )
        let scaledRect = originalRect.applying(scaled)
        let translation = CGAffineTransform(
            translationX:
                (renderSize.width - scaledRect.width) / 2 - scaledRect.minX,
            y:
                (renderSize.height - scaledRect.height) / 2 - scaledRect.minY
        )
        return scaled.concatenating(translation)
    }

    private static func randomFocalPoint(in renderSize: CGSize) -> CGPoint {
        let horizontalPosition = CGFloat.random(in: 0.15...0.85)
        let verticalPosition = CGFloat.random(in: 0.15...0.85)
        return CGPoint(
            x: renderSize.width * horizontalPosition,
            y: renderSize.height * verticalPosition
        )
    }

    private static func codecSafeRenderSize(_ size: CGSize) -> CGSize {
        func aligned(_ value: CGFloat) -> CGFloat {
            let pixels = max(4, Int(value.rounded()))
            return CGFloat(max(4, pixels - pixels % 4))
        }

        return CGSize(
            width: aligned(size.width),
            height: aligned(size.height)
        )
    }
}

private final class ExportSessionReference: @unchecked Sendable {
    let value: AVAssetExportSession

    init(_ value: AVAssetExportSession) {
        self.value = value
    }
}
