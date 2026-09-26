import WidgetKit
import SwiftUI

@main
struct CapitalGrilleWatchWidgets: WidgetBundle {
    var body: some Widget {
        CapitalGrilleComplication()
        if #available(watchOS 26.0, *) {
            OpenControl()
        }
    }
}

/// A watch-face button that opens the app: the initials, bare on the face like StatusHub's microphone.
struct CapitalGrilleComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CapitalGrilleComplication", provider: Provider()) { _ in
            Text("CG")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .widgetAccentable()
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Capital Grille")
        .description("Capital Grille")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// The Control Center button (watchOS 26), which also sits in the Smart Stack and on an Ultra's
/// Action button. It only opens the app.
@available(watchOS 26.0, *)
struct OpenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.jaredgantt.CapitalGrille.watch.open") {
            ControlWidgetButton(action: OpenAppIntent()) {
                Label("Capital Grille", systemImage: "wineglass.fill")
            }
        }
        .displayName("Capital Grille")
    }
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date())], policy: .never))
    }
}

private struct Entry: TimelineEntry { let date: Date }
