import WidgetKit
import SwiftUI

@main
struct CapitalGrilleWatchWidgets: WidgetBundle {
    var body: some Widget {
        CapitalGrilleComplication()
        BlankRecordComplication()
        if #available(watchOS 26.0, *) {
            OpenControl()
        }
    }
}

/// A watch-face button that opens the app straight into a recording (`capitalgrille://record`, answered
/// in WatchContentView). It draws nothing, like StatusHub's: a clear view filling the slot, so the face
/// shows no trace of it and the whole empty slot is still the tap target.
struct CapitalGrilleComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CapitalGrilleComplication", provider: Provider()) { _ in
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetURL(URL(string: "capitalgrille://record"))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Capital Grille")
        .description("Capital Grille")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// The same button under a new kind, so a face that cached the first complication's old drawing can
/// take one that has never been drawn any other way. Leave both: a kind that disappears drops off
/// every face that holds it.
struct BlankRecordComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BlankRecordComplication", provider: Provider()) { _ in
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .widgetURL(URL(string: "capitalgrille://record"))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Capital Grille Blank")
        .description("Capital Grille Blank")
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
