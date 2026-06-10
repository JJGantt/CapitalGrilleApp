import WidgetKit
import SwiftUI

@main
struct CapitalGrilleWatchWidgets: WidgetBundle {
    var body: some Widget {
        CapitalGrilleComplication()
    }
}

struct CapitalGrilleComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CapitalGrilleComplication", provider: Provider()) { _ in
            Text("CG")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .widgetAccentable()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Capital Grille")
        .description("Capital Grille")
        .supportedFamilies([.accessoryCircular])
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
