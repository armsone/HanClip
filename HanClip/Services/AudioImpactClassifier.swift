import Foundation

enum AudioImpactSensitivity: Equatable, Sendable {
    case noisy
    case normal
    case quiet
    case automatic
}

struct AudioImpactMetrics: Sendable {
    let rms: Double
    let peak: Double
    let crossingRate: Double

    var impactScore: Double {
        let highFrequencyWeight = min(1, crossingRate * 10)
        return min(
            1,
            rms * 0.55
                + peak * 0.45
                + highFrequencyWeight * rms * 0.35
        )
    }
}

struct AudioImpactFrame: Sendable {
    let time: Double
    let metrics: AudioImpactMetrics
}

struct AudioImpactDecision: Sendable {
    let isTriggered: Bool
    let confidence: Double
}

enum HanClipAiModelVersion: String, CaseIterable, Sendable {
    case v0_1_0 = "0.1.0"
    case v0_2_0 = "0.2.0"
    case v0_2_1 = "0.2.1"

    var title: String {
        switch self {
        case .v0_1_0:
            "소리 중심 Ai"
        case .v0_2_0:
            "소리 + 화면 보조 Ai"
        case .v0_2_1:
            "798 영상 보정 Ai"
        }
    }

    var releaseDate: String {
        switch self {
        case .v0_1_0:
            "2026.08.06"
        case .v0_2_0:
            "2026.08.06"
        case .v0_2_1:
            "2026.08.06"
        }
    }

    var featureSummary: String {
        switch self {
        case .v0_1_0:
            "소리의 피크, 갑작스러운 상승, 이어지는 반응을 중심으로 기억할 순간을 찾습니다."
        case .v0_2_0:
            "소리를 중심으로 보되, AiShot 촬영 중 화면의 움직임과 밝기 변화를 함께 참고해 더 좋은 순간을 찾습니다."
        case .v0_2_1:
            "798개 영상 공부 결과를 반영해, 소리의 피크보다 행복한 순간 뒤에 이어지는 반응과 화면 변화를 더 차분하게 함께 봅니다."
        }
    }

    var supportsRealtimeVisualAssist: Bool {
        switch self {
        case .v0_1_0:
            false
        case .v0_2_0, .v0_2_1:
            true
        }
    }

    var usesAudibleResponseWeight: Bool {
        switch self {
        case .v0_1_0:
            false
        case .v0_2_0, .v0_2_1:
            true
        }
    }
}

enum AudioImpactClassifier {
    static let currentModelVersion = HanClipAiModelVersion.v0_2_1
    static var modelVersion: String { currentModelVersion.rawValue }
    static var modelFeatureSummary: String {
        currentModelVersion.featureSummary
    }

    private struct Thresholds {
        let strongScoreFloor: Double
        let strongBaselineMultiplier: Double
        let strongPeakFloor: Double
        let strongPeakBaselineMultiplier: Double
        let strongRise: Double
        let strongCrossingRate: Double
        let strongCrestFactor: Double
        let distantScoreFloor: Double
        let distantBaselineMultiplier: Double
        let distantPeakFloor: Double
        let distantPeakBaselineMultiplier: Double
        let distantRise: Double
        let distantCrossingRate: Double
        let distantCrestFactor: Double
    }

    static func detectImpact(
        metrics: AudioImpactMetrics,
        baseline: Double,
        previousRecentLevel: Double,
        sensitivity: AudioImpactSensitivity
    ) -> AudioImpactDecision {
        let score = metrics.impactScore
        let referenceLevel = max(
            0.003,
            max(baseline, previousRecentLevel * 0.82)
        )
        let suddenRise = score / referenceLevel
        let crestFactor = metrics.peak / max(0.001, metrics.rms)
        let thresholds = thresholds(
            for: effectiveSensitivity(
                sensitivity,
                baseline: baseline
            )
        )

        let strongScoreRequirement = max(
            thresholds.strongScoreFloor,
            baseline * thresholds.strongBaselineMultiplier
        )
        let strongPeakRequirement = max(
            thresholds.strongPeakFloor,
            baseline * thresholds.strongPeakBaselineMultiplier
        )
        let isStrongImpact = score >= strongScoreRequirement
            && metrics.peak >= strongPeakRequirement
            && suddenRise >= thresholds.strongRise
            && metrics.crossingRate >= thresholds.strongCrossingRate
            && crestFactor >= thresholds.strongCrestFactor

        let distantScoreRequirement = max(
            thresholds.distantScoreFloor,
            baseline * thresholds.distantBaselineMultiplier
        )
        let distantPeakRequirement = max(
            thresholds.distantPeakFloor,
            baseline * thresholds.distantPeakBaselineMultiplier
        )
        let isDistantSharpImpact = score >= distantScoreRequirement
            && metrics.peak >= distantPeakRequirement
            && suddenRise >= thresholds.distantRise
            && metrics.crossingRate >= thresholds.distantCrossingRate
            && crestFactor >= thresholds.distantCrestFactor

        let isSpeechLikePrompt = metrics.rms >= 0.025
            && crestFactor < 3.15
            && metrics.crossingRate < 0.16
            && suddenRise < 4.8
            && score < 0.18

        let confidence = impactConfidence(
            score: score,
            peak: metrics.peak,
            suddenRise: suddenRise,
            crossingRate: metrics.crossingRate,
            crestFactor: crestFactor,
            thresholds: thresholds
        )
        return AudioImpactDecision(
            isTriggered: !isSpeechLikePrompt
                && (isStrongImpact || isDistantSharpImpact),
            confidence: isSpeechLikePrompt ? 0 : confidence
        )
    }

    static func rankedImpactTimes(
        frames: [AudioImpactFrame],
        duration: Double,
        limit: Int = 12
    ) -> [Double] {
        guard !frames.isEmpty else { return [] }

        var baseline = 0.008
        var recentLevel = 0.008
        var candidates: [(time: Double, score: Double)] = []
        var fallback: [(time: Double, score: Double)] = []

        for (index, frame) in frames.enumerated() {
            let metrics = frame.metrics
            let score = metrics.impactScore
            let previousRecentLevel = recentLevel
            let baselineSample = min(score, max(0.004, baseline * 1.35))
            baseline = baseline * 0.985
                + max(0.002, baselineSample) * 0.015
            recentLevel = recentLevel * 0.72 + max(0.002, score) * 0.28

            let decision = detectImpact(
                metrics: metrics,
                baseline: baseline,
                previousRecentLevel: previousRecentLevel,
                sensitivity: .automatic
            )
            let neighborhoodScore = localContrastScore(
                frames: frames,
                index: index
            )
            let highlightScore = generalHighlightScore(
                frames: frames,
                index: index
            )
            let memorableMomentScore = memorableMomentScore(
                frames: frames,
                index: index
            )
            let combinedScore = decision.confidence
                + neighborhoodScore * 0.45
                + highlightScore * 0.75
                + memorableMomentScore * 0.58
                + score * 0.12

            fallback.append((frame.time, combinedScore))
            if decision.isTriggered
                || highlightScore > 0.82
                || memorableMomentScore > 0.78
                || combinedScore > 1.02 {
                candidates.append((frame.time, combinedScore))
            }
        }

        if candidates.isEmpty {
            candidates = fallback
        }

        let minimumSeparation = max(0.45, duration / 160)
        var selected: [(time: Double, score: Double)] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard selected.allSatisfy({
                abs($0.time - candidate.time) >= minimumSeparation
            }) else { continue }
            selected.append(candidate)
            if selected.count >= limit {
                break
            }
        }
        return selected.map(\.time)
    }

    private static func effectiveSensitivity(
        _ sensitivity: AudioImpactSensitivity,
        baseline: Double
    ) -> AudioImpactSensitivity {
        guard sensitivity == .automatic else { return sensitivity }
        if baseline >= 0.026 {
            return .noisy
        } else if baseline <= 0.009 {
            return .quiet
        }
        return .normal
    }

    private static func thresholds(
        for sensitivity: AudioImpactSensitivity
    ) -> Thresholds {
        switch sensitivity {
        case .noisy:
            return Thresholds(
                strongScoreFloor: 0.10,
                strongBaselineMultiplier: 2.7,
                strongPeakFloor: 0.18,
                strongPeakBaselineMultiplier: 4.2,
                strongRise: 2.2,
                strongCrossingRate: 0.07,
                strongCrestFactor: 2.3,
                distantScoreFloor: 0.065,
                distantBaselineMultiplier: 3.4,
                distantPeakFloor: 0.12,
                distantPeakBaselineMultiplier: 5.0,
                distantRise: 3.0,
                distantCrossingRate: 0.10,
                distantCrestFactor: 3.5
            )
        case .normal, .automatic:
            return Thresholds(
                strongScoreFloor: 0.075,
                strongBaselineMultiplier: 2.3,
                strongPeakFloor: 0.13,
                strongPeakBaselineMultiplier: 3.5,
                strongRise: 1.8,
                strongCrossingRate: 0.05,
                strongCrestFactor: 2.0,
                distantScoreFloor: 0.045,
                distantBaselineMultiplier: 2.8,
                distantPeakFloor: 0.09,
                distantPeakBaselineMultiplier: 4.2,
                distantRise: 2.4,
                distantCrossingRate: 0.08,
                distantCrestFactor: 3.0
            )
        case .quiet:
            return Thresholds(
                strongScoreFloor: 0.055,
                strongBaselineMultiplier: 1.9,
                strongPeakFloor: 0.095,
                strongPeakBaselineMultiplier: 3.0,
                strongRise: 1.55,
                strongCrossingRate: 0.04,
                strongCrestFactor: 1.7,
                distantScoreFloor: 0.035,
                distantBaselineMultiplier: 2.3,
                distantPeakFloor: 0.07,
                distantPeakBaselineMultiplier: 3.4,
                distantRise: 2.0,
                distantCrossingRate: 0.065,
                distantCrestFactor: 2.5
            )
        }
    }

    private static func impactConfidence(
        score: Double,
        peak: Double,
        suddenRise: Double,
        crossingRate: Double,
        crestFactor: Double,
        thresholds: Thresholds
    ) -> Double {
        let scoreRatio = score / max(0.001, thresholds.distantScoreFloor)
        let peakRatio = peak / max(0.001, thresholds.distantPeakFloor)
        let riseRatio = suddenRise / max(0.001, thresholds.distantRise)
        let crossingRatio = crossingRate
            / max(0.001, thresholds.distantCrossingRate)
        let crestRatio = crestFactor
            / max(0.001, thresholds.distantCrestFactor)
        return scoreRatio * 0.28
            + peakRatio * 0.22
            + riseRatio * 0.24
            + min(crossingRatio, 1.8) * 0.13
            + min(crestRatio, 1.8) * 0.13
    }

    private static func localContrastScore(
        frames: [AudioImpactFrame],
        index: Int
    ) -> Double {
        let start = max(0, index - 5)
        let history = frames[start..<index].map { $0.metrics.impactScore }
        let baseline = history.reduce(0, +) / Double(max(1, history.count))
        let value = frames[index].metrics.impactScore
        let previous = index > 0 ? frames[index - 1].metrics.impactScore : 0
        let next = index + 1 < frames.count
            ? frames[index + 1].metrics.impactScore
            : 0
        let rise = max(0, value - baseline)
        let isLocalPeak = value >= previous && value >= next
        return rise * 5.0 + (isLocalPeak ? value * 0.65 : 0)
    }

    private static func generalHighlightScore(
        frames: [AudioImpactFrame],
        index: Int
    ) -> Double {
        let metrics = frames[index].metrics
        let value = metrics.impactScore
        let start = max(0, index - 10)
        let history = frames[start..<index]
        let historyCount = Double(max(1, history.count))
        let baselineScore = history
            .map(\.metrics.impactScore)
            .reduce(0, +) / historyCount
        let baselineRMS = history
            .map(\.metrics.rms)
            .reduce(0, +) / historyCount
        let baselinePeak = history
            .map(\.metrics.peak)
            .reduce(0, +) / historyCount
        let previous = index > 0 ? frames[index - 1].metrics.impactScore : 0
        let next = index + 1 < frames.count
            ? frames[index + 1].metrics.impactScore
            : 0
        let isLocalPeak = value >= previous && value >= next
        let scoreRiseRatio = value / max(0.006, baselineScore)
        let rmsRiseRatio = metrics.rms / max(0.004, baselineRMS)
        let peakRiseRatio = metrics.peak / max(0.012, baselinePeak)
        let directRise = max(0, value - previous)
        let sustainedEnergy = min(1.0, value * 1.25 + metrics.peak * 0.35)

        return min(
            1.6,
            max(0, scoreRiseRatio - 1.0) * 0.22
                + max(0, rmsRiseRatio - 1.0) * 0.16
                + max(0, peakRiseRatio - 1.0) * 0.14
                + directRise * 2.4
                + sustainedEnergy * 0.28
                + (isLocalPeak ? value * 0.45 : 0)
            )
    }

    private static func memorableMomentScore(
        frames: [AudioImpactFrame],
        index: Int
    ) -> Double {
        let frame = frames[index]
        let beforeStart = max(0, index - 8)
        let afterEnd = min(frames.count, index + 9)
        let before = frames[beforeStart..<index]
        let after = frames[(index + 1)..<afterEnd]
        guard before.count >= 2, after.count >= 2 else { return 0 }
        let beforeCount = Double(max(1, before.count))
        let afterCount = Double(max(1, after.count))
        let beforeEnergy = before.map(\.metrics.impactScore).reduce(0, +)
            / beforeCount
        let afterEnergy = after.map(\.metrics.impactScore).reduce(0, +)
            / afterCount
        let afterPeak = after.map(\.metrics.peak).max() ?? 0
        let currentEnergy = frame.metrics.impactScore
        let riseIntoMoment = max(0, currentEnergy - beforeEnergy)
        let heldExcitement = afterEnergy / max(0.008, beforeEnergy)
        let audibleResponseWeight = currentModelVersion.usesAudibleResponseWeight
            ? min(1, afterEnergy / 0.045)
            : 1
        let heldExcitementBonus = min(2.4, max(0, heldExcitement - 1))
            * audibleResponseWeight
        let responsePeak = max(0, afterPeak - frame.metrics.peak * 0.45)
        let crossingTexture = min(1, frame.metrics.crossingRate * 9)
        let distanceFromEdge = min(index, frames.count - 1 - index)
        let edgeConfidence = min(1, Double(distanceFromEdge) / 6.0)

        let score = min(
            1.5,
            riseIntoMoment * 2.2
                + heldExcitementBonus * 0.28
                + responsePeak * 0.45
                + currentEnergy * 0.34
                + crossingTexture * currentEnergy * 0.18
        )
        return score * edgeConfidence
    }
}
