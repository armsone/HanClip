# HanAI v0.7.0 release-candidate sync report

- Started: 2026-09-07 13:16 KST
- Source-sync recorded: 2026-09-07 13:36 KST
- Group: HanAI core, HanClip iOS, HanClip Android
- Status: source and package builds verified; device visual/runtime verification remains open.

## Goal and acceptance evidence

The golf putter detector was advanced from the previously confirmed labelled-session data.  Its strict, time-separated holdout result is 26 correct putter clips in the first 30 ranked clips (86.7%).  Among clips with a known human label, it is 26/27 (96.3%).  This is evidence for the required 80% threshold on the same recorded session with label-adjacent windows excluded; it is not evidence of recall or of generalization to a different venue/camera.

## Capability matrix

| Capability | HanAI | HanClip iOS | HanClip Android | Evidence | Remaining state |
| --- | --- | --- | --- | --- | --- |
| v0.7 visual-backed weak-impact fusion | `GolfPutterDetector` and model metadata | visual evidence is mandatory for weak/audio-only candidates | same policy in `AiShotMotionFusion` | HanAI `swift build`; iOS archive; Android `assembleReleaseQa` | runtime capture open |
| v0.7 impact/motion timing | detector evidence timestamps | motion evidence aligned to impact time | elapsed-time evidence alignment | source review plus platform builds | runtime capture open |
| putter context window | 0.7 detector output | 0.55-second frame/pose evidence window | 0.55-second visual evidence window | source review plus platform builds | real-putt capture open |
| model history shown to users | model v0.7 release date | editor history copy | home history copy | source review | visual capture open |
| release packages | Swift package build | signed iOS archive | signed releaseQa APK | build/archive metadata | public upload/publish pending |

## Problems found and resolved

1. **Problem recognition:** v0.7 weak impacts were specified as visual-backed but platform entry points rejected every non-triggered impact before the fusion policy could evaluate it.
   - **Cause:** an outer `isTriggered` guard preempted the weak-impact exception.
   - **Resolution:** both platforms now forward only the explicitly bounded weak visual-backed candidates (peak, impact score, crossing rate, crest factor, and ready-state suppression gates) to fusion.

2. **Problem recognition:** iOS motion evidence could be treated as recent without proving it belonged to the impact event.
   - **Cause:** the policy checked freshness but not the allowed impact-to-motion interval.
   - **Resolution:** iOS now requires the visual/motion timestamp to be within -0.20 to +0.32 seconds of the audio impact time.

3. **Problem recognition:** Android's normal release output is unsigned in this repository.
   - **Cause:** no production release signing configuration is present.
   - **Resolution:** the repository's existing `releaseQa` public-package lane was built.  Its signing certificate matches the current public APK certificate, and its version is 2.3.0 (code 359356).

## Verification performed

- HanAI: `swift build` succeeded.
- HanClip iOS: device release build and signed archive succeeded; archive metadata is `2.3.0 (202609071316)`.
- HanClip Android: debug, unsigned release compilation, and signed `releaseQa` assembly succeeded; the releaseQa APK certificate matches the current public APK lineage.
- Static parity ledger is valid JSON and structurally valid.  Its two source-only rows intentionally remain open because no iPhone or Android device/capture is connected.

## Explicitly not claimed complete

- No physical iPhone or Android installation/capture was available.
- The strict holdout measures ranked-clip precision at the inspected cutoff, not total-putt recall or independent-scene performance.
- Public TestFlight processing, GitHub publication, and product-site release state are handled after the source commits and are not represented as complete by this report.
