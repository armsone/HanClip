import Foundation
import HanAI

/// One source-video range chosen for a video segment child clip.
struct VideoSegmentRange: Equatable {
    let start: Double
    let duration: Double
    let peak: Double
    let isProtectedAction: Bool
}

/// Adapter from HanClip's analysis to HanAI `VideoHighlightSelector`.
/// Protected action windows (golf stroke context) are kept whole; ordinary
/// highlight peaks keep their usual centered window around the remaining time.
enum ProtectedActionSegmenter {
    /// Returns nil when there is no protected action evidence, so callers keep
    /// the existing peak-centered segmentation unchanged.
    static func ranges(
        peaks: [Double],
        protectedActions: [ClipProtectedAction],
        sourceDuration: Double,
        segmentDuration: Double
    ) -> [VideoSegmentRange]? {
        guard !protectedActions.isEmpty,
              sourceDuration.isFinite, sourceDuration > 0
        else { return nil }

        let duration = min(max(0.1, segmentDuration), sourceDuration)
        // Peaks are already non-overlapping, so every one is kept as an anchor.
        let candidates = peaks.enumerated().map {
            VideoFrameCandidate(
                index: $0.offset,
                timeSeconds: min(max(0, $0.element), sourceDuration),
                qualityScore: 1
            )
        }
        let result = VideoHighlightSelector.select(
            candidates: candidates,
            distances: [],
            durationSeconds: sourceDuration,
            configuration: VideoHighlightConfiguration(
                frameCount: candidates.count,
                similarityThreshold: 0,
                minimumQuality: 0,
                minimumSpacingSeconds: 0,
                localDiversityWindowSeconds: 0,
                preRollSeconds: duration / 2,
                postRollSeconds: duration / 2,
                maxSegmentDurationSeconds: duration,
                totalDurationBudgetSeconds: sourceDuration,
                importanceWeight: 0
            ),
            protectedActions: protectedActions.map {
                VideoProtectedAction(
                    timeSeconds: $0.time,
                    isLoud: $0.isLoud,
                    isSharpTransient: $0.isSharpTransient
                )
            }
        )
        guard result.configurationErrors.isEmpty else { return nil }

        return result.segments.compactMap { segment in
            let length = segment.endSeconds - segment.startSeconds
            guard length >= 0.1 else { return nil }
            let peak: Double
            if let actionIndex = segment.protectedActionIndices.first {
                peak = protectedActions[actionIndex].time
            } else if let anchor = segment.anchorIndices.first {
                peak = candidates[anchor].timeSeconds
            } else {
                peak = segment.startSeconds + length / 2
            }
            return VideoSegmentRange(
                start: segment.startSeconds,
                duration: length,
                peak: peak,
                isProtectedAction: !segment.protectedActionIndices.isEmpty
            )
        }
    }
}
