import SwiftUI

@main
struct CapitalGrilleApp: App {
    init() {
        WatchRelayHandler.activate()
        // Diagnostic: fire a heartbeat directly via URLSession on launch. Bypasses
        // AppLogger entirely so we can confirm the new build is running independently
        // of whether logging itself works.
        Task.detached(priority: .background) {
            let url = URL(string: "https://felyggqjjhltwokdfhop.supabase.co/rest/v1/app_logs")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue(Secrets.supabaseKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(Secrets.supabaseKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let body: [String: Any] = [
                "timestamp":      iso.string(from: Date()),
                "interaction_id": UUID().uuidString,
                "kind":           "heartbeat",
                "output":         "build_2026-05-27_logger_test"
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}
