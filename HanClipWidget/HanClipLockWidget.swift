import SwiftUI
import WidgetKit

private struct HanClipLockEntry: TimelineEntry {
    let date: Date
}

private struct HanClipLockProvider: TimelineProvider {
    func placeholder(in context: Context) -> HanClipLockEntry {
        HanClipLockEntry(date: Date())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (HanClipLockEntry) -> Void
    ) {
        completion(HanClipLockEntry(date: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<HanClipLockEntry>) -> Void
    ) {
        let entry = HanClipLockEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

private struct HanClipLockWidgetView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            Image("AppIcon-Light")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(7)
                .accessibilityHidden(true)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
        .widgetURL(URL(string: "hanclip://home"))
        .accessibilityLabel("HanClip 열기")
    }
}

@main
struct HanClipLockWidget: Widget {
    private let kind = "HanClipLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: HanClipLockProvider()
        ) { _ in
            HanClipLockWidgetView()
        }
        .configurationDisplayName("HanClip 바로 실행")
        .description("잠금 화면에서 HanClip을 바로 엽니다.")
        .supportedFamilies([.accessoryCircular])
    }
}
