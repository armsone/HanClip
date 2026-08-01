import AVFoundation
import Foundation

struct AudioAnalysisResult: Sendable {
    let waveform: [Double]
    let peakTime: Double
    let peakTimes: [Double]

    init(waveform: [Double], peakTime: Double, peakTimes: [Double]? = nil) {
        self.waveform = waveform
        self.peakTime = peakTime
        self.peakTimes = peakTimes ?? [peakTime]
    }
}

enum AudioAnalysisService {
    static func analyze(url: URL, bucketCount: Int = 192) async throws
        -> AudioAnalysisResult {
        try await Task.detached(priority: .userInitiated) {
            let bucketCount = max(1, bucketCount)
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0,
                  let track = try await asset.loadTracks(
                    withMediaType: .audio
                  ).first
            else {
                return AudioAnalysisResult(
                    waveform: Array(repeating: 0.08, count: bucketCount),
                    peakTime: max(0, duration / 2)
                )
            }

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw MediaError.videoTrackUnavailable
            }
            reader.add(output)
            reader.startReading()

            var energy = Array(repeating: 0.0, count: bucketCount)
            var counts = Array(repeating: 0, count: bucketCount)

            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let block = CMSampleBufferGetDataBuffer(sample) else {
                    continue
                }
                var length = 0
                var pointer: UnsafeMutablePointer<Int8>?
                guard CMBlockBufferGetDataPointer(
                    block,
                    atOffset: 0,
                    lengthAtOffsetOut: nil,
                    totalLengthOut: &length,
                    dataPointerOut: &pointer
                ) == kCMBlockBufferNoErr,
                      let pointer,
                      length >= MemoryLayout<Int16>.size
                else { continue }

                let sampleCount = length / MemoryLayout<Int16>.size
                let values = UnsafeRawPointer(pointer)
                    .assumingMemoryBound(to: Int16.self)
                var sum = 0.0
                for index in 0..<sampleCount {
                    let value = Double(values[index]) / Double(Int16.max)
                    sum += value * value
                }
                let rms = sqrt(sum / Double(max(1, sampleCount)))
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                    .seconds
                let bucket = min(
                    bucketCount - 1,
                    max(0, Int(time / duration * Double(bucketCount)))
                )
                energy[bucket] += rms
                counts[bucket] += 1
            }

            var values = zip(energy, counts).map {
                $1 > 0 ? $0 / Double($1) : 0
            }
            let maximum = max(values.max() ?? 0, 0.000_1)
            values = values.map { max(0.04, min(1, $0 / maximum)) }

            var candidates: [(index: Int, score: Double)] = []
            var bestCandidate = (
                index: bucketCount / 2,
                score: -Double.infinity
            )
            for index in 1..<bucketCount {
                let historyStart = max(0, index - 5)
                let history = values[historyStart..<index]
                let baseline = history.reduce(0, +)
                    / Double(max(1, history.count))
                let rise = values[index] - baseline
                let score = rise + values[index] * 0.25
                if score > bestCandidate.score {
                    bestCandidate = (index, score)
                }
                let previous = values[index - 1]
                let next = index + 1 < bucketCount ? values[index + 1] : 0
                if rise > 0.04 {
                    candidates.append((index, score))
                }
                if values[index] >= previous, values[index] >= next {
                    candidates.append((index, score))
                }
            }

            if !candidates.contains(
                where: { $0.index == bestCandidate.index }
            ) {
                candidates.append(bestCandidate)
            }

            for candidate in strongestEnergyCandidates(values: values) {
                candidates.append(candidate)
            }

            let bucketsPerSecond = Double(bucketCount) / max(duration, 0.1)
            let minimumSeparation = max(1, Int((bucketsPerSecond * 0.45).rounded()))
            var selected: [(index: Int, score: Double)] = []
            for candidate in candidates.sorted(by: { $0.score > $1.score }) {
                guard selected.allSatisfy({
                    abs($0.index - candidate.index) >= minimumSeparation
                }) else { continue }
                selected.append(candidate)
                if selected.count >= 12 {
                    break
                }
            }

            if selected.isEmpty {
                selected.append(bestCandidate)
            }

            return AudioAnalysisResult(
                waveform: values,
                peakTime: (Double(selected[0].index) + 0.5)
                    / Double(bucketCount) * duration,
                peakTimes: selected.map {
                    (Double($0.index) + 0.5) / Double(bucketCount) * duration
                }
            )
        }.value
    }

    private static func strongestEnergyCandidates(
        values: [Double]
    ) -> [(index: Int, score: Double)] {
        values.enumerated().map { index, value in
            (index: index, score: value * 0.55)
        }
    }
}
