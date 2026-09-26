import AppIntents

/// What the Control Center button opens. A control that launches its app takes an `OpenIntent`, and
/// an `OpenIntent` opens a target, so this is the one there is. Compiled into both the widget
/// extension and the watch app, since the system runs it in the app it opens.
enum AppTarget: String, AppEnum {
    case app

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Capital Grille"
    static var caseDisplayRepresentations: [AppTarget: DisplayRepresentation] = [.app: "Capital Grille"]
}

struct OpenAppIntent: OpenIntent {
    static var title: LocalizedStringResource = "Capital Grille"

    @Parameter(title: "Target") var target: AppTarget

    init() {
        target = .app
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
