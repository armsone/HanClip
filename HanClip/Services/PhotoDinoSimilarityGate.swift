import CoreGraphics
import CoreML
import Foundation
import HanAIApple
import Photos

/// 기존 fingerprint 유사 판정에 DINO cosine-distance veto를 더하는 최소 adapter.
///
/// 이 타입은 새 유사 그룹을 만들지 않는다. 기존 fingerprint 판정이 true일
/// 때만 호출되어, 거리가 멀면 그 판정을 거부(veto)하는 AND 게이트 역할만
/// 한다. 배치 내 모든 사진의 임베딩을 얻지 못하면 배치 전체가 기존 판정
/// 으로 되돌아간다 — pair별 부분 fallback은 하지 않는다. 임베딩은 호출
/// 당 메모리에만 머물고 디스크·로그·네트워크에 남지 않는다.
///
/// `prepareEmbeddings`는 decode·preprocess·CPU 모델 추론을 모두 비
/// MainActor 컨텍스트(`Task.detached`)에서 사진 한 장씩 직렬 수행한다.
/// 호출자는 그 결과(완성된 배치)만 동기 veto 비교에 넘겨야 한다.
enum PhotoDinoSimilarityGate {
    /// 48장 소규모 평가(biased, 일반화 주장 없음)에서 선택된 고정 threshold.
    static let cosineDistanceThreshold = 0.06911703708590078

    private static let embeddingDimension = 384

    private static let modelLock = NSLock()
    private static var cachedModel: DinoImageFeatures?

    /// `clips` 전원의 384차원 임베딩을 성공적으로 얻었을 때만 non-nil을
    /// 반환한다. 하나라도 디코딩/모델 실패면 nil — 호출자는 전체 배치를
    /// 기존 판정으로 되돌려야 한다. 취소는 삼키지 않고 그대로 던진다.
    /// decode·preprocess·모델 추론은 모두 `Task.detached`로 넘겨 호출자의
    /// actor(일반적으로 MainActor)를 블록하지 않는다.
    static func prepareEmbeddings(
        for clips: [ClipItem]
    ) async throws -> [UUID: [Float]]? {
        guard !clips.isEmpty else { return [:] }

        let worker = Task.detached(priority: .utility) {
            try await embeddingsOffMain(for: clips)
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// 기존 fingerprint 유사 판정이 true인 경우에만 호출되는 AND veto.
    /// `embeddings`가 배치 전체에 대해 유효하지 않으면 veto하지 않는다
    /// (기존 판정 그대로 유지). 순수 메모리 비교만 수행하며 decode나
    /// 모델 호출은 절대 하지 않는다.
    static func vetoesSimilar(
        _ lhs: ClipItem,
        _ rhs: ClipItem,
        embeddings: [UUID: [Float]]?
    ) -> Bool {
        guard let embeddings,
              let lhsVector = embeddings[lhs.id],
              let rhsVector = embeddings[rhs.id]
        else { return false }

        return cosineDistance(lhsVector, rhsVector) > cosineDistanceThreshold
    }

    private static func embeddingsOffMain(
        for clips: [ClipItem]
    ) async throws -> [UUID: [Float]]? {
        guard let model = loadedModel() else { return nil }

        var result: [UUID: [Float]] = [:]
        result.reserveCapacity(clips.count)

        for clip in clips {
            try Task.checkCancellation()
            let data: Data
            do {
                data = try await imageData(for: clip)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                return nil
            }
            try Task.checkCancellation()
            guard let vector = embedding(for: data, model: model),
                  isValidEmbedding(vector)
            else { return nil }
            try Task.checkCancellation()
            result[clip.id] = vector
        }
        return result
    }

    private static func imageData(for clip: ClipItem) async throws -> Data {
        switch clip.source {
        case .imageFile(let url):
            guard url.isFileURL else { throw MediaError.imageUnavailable }
            return try Data(contentsOf: url)
        case .livePhotoFiles(let imageURL, _):
            guard imageURL.isFileURL else { throw MediaError.imageUnavailable }
            return try Data(contentsOf: imageURL)
        case .photoAsset(let localIdentifier):
            guard let asset = PhotoLibraryService.asset(
                localIdentifier: localIdentifier
            ) else {
                throw MediaError.imageUnavailable
            }
            return try await PhotoLibraryService.originalImageData(for: asset)
        case .videoFile:
            throw MediaError.imageUnavailable
        }
    }

    private static func embedding(
        for data: Data,
        model: DinoImageFeatures
    ) -> [Float]? {
        guard let decoded = try? DinoImageSource.decode(data: data),
              let pixels = try? DinoImagePreprocessor.normalizedInput(
                rgb: decoded.rgb,
                width: decoded.width,
                height: decoded.height
              ),
              let vector = try? model.embedding(preprocessedPixels: pixels)
        else { return nil }
        return vector
    }

    private static func isValidEmbedding(_ vector: [Float]) -> Bool {
        vector.count == embeddingDimension
            && vector.allSatisfy(\.isFinite)
            && vector.contains { $0 != 0 }
    }

    private static func cosineDistance(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }

        var dot = 0.0
        var lhsNormSquared = 0.0
        var rhsNormSquared = 0.0
        for i in 0..<lhs.count {
            let l = Double(lhs[i])
            let r = Double(rhs[i])
            dot += l * r
            lhsNormSquared += l * l
            rhsNormSquared += r * r
        }
        guard lhsNormSquared > 0, rhsNormSquared > 0 else { return .infinity }

        let similarity = dot / (lhsNormSquared.squareRoot() * rhsNormSquared.squareRoot())
        return 1 - similarity
    }

    private static func loadedModel() -> DinoImageFeatures? {
        modelLock.lock()
        defer { modelLock.unlock() }
        if let cachedModel { return cachedModel }

        guard let modelURL = Bundle.main.url(
            forResource: "HanAIDino",
            withExtension: "mlmodelc"
        ) else { return nil }

        guard let model = try? DinoImageFeatures(
            compiledModelURL: modelURL,
            computeUnits: .cpuOnly
        ) else { return nil }

        cachedModel = model
        return model
    }
}
