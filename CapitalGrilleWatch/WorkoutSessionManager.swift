import Foundation
import HealthKit

/// Keeps the Capital Grille watch app live and brings it to the foreground on
/// every wrist raise — same trick GolfTracker uses. We use HKWorkoutSession
/// purely for that auto-return-to-app behavior, not for fitness tracking.
///
/// Configuration is intentionally minimal:
///   • activityType .other (no exercise data attribution)
///   • locationType .unknown (no GPS sensor, no location prompt)
///   • no heart rate / sample subscriptions (we never query the health store)
///   • no live workout builder (no metrics, no Health.app workout entry)
///
/// Battery impact comes mainly from screen-on events on wrist raise; sensors
/// stay idle.
@MainActor
final class WorkoutSessionManager: NSObject, ObservableObject, HKWorkoutSessionDelegate {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?

    /// Start the workout session. Safe to call repeatedly — no-ops if already running.
    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Workout sessions need *some* HealthKit authorization. We request the
        // minimum (an empty set is rejected on some OSes) and don't actually
        // read or write anything.
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: typesToShare, read: []) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.startSessionIfNeeded() }
        }
    }

    private func startSessionIfNeeded() {
        if let s = session, s.state == .running || s.state == .prepared { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown
        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            s.delegate = self
            s.startActivity(with: Date())
            session = s
        } catch {
            // Silent — workout session is a UX optimization, not critical.
            print("[WorkoutSessionManager] failed to start: \(error)")
        }
    }

    func stop() {
        session?.end()
        session = nil
    }

    // MARK: HKWorkoutSessionDelegate

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        print("[WorkoutSessionManager] failed: \(error)")
    }
}
