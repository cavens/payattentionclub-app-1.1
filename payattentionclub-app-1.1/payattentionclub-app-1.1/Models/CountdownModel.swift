import Foundation
import SwiftUI
import Combine

/// Helper function to calculate next Monday noon EST
func nextMondayNoonEST(from now: Date = Date()) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")! // EST/EDT correctly handled
    
    // Find next Monday:
    let weekday = cal.component(.weekday, from: now) // 1=Sun...7=Sat
    let daysUntilMonday = (2 - weekday + 7) % 7  // Monday = 2
    let base = cal.date(byAdding: .day, value: daysUntilMonday == 0 ? 7 : daysUntilMonday, to: cal.startOfDay(for: now))!
    
    // Set 12:00 (noon)
    return cal.date(bySettingHour: 12, minute: 0, second: 0, of: base)!
}

/// Countdown model with background timer for smooth, accurate countdown
@MainActor
final class CountdownModel: ObservableObject {
    @Published private(set) var deadline: Date
    @Published private(set) var nowSnapshot: Date = Date() // view reads this
    
    private var timer: DispatchSourceTimer?
    
    init(deadline: Date) {
        self.deadline = deadline
        // Defer timer start to avoid blocking initialization
        // Start timer asynchronously after a brief delay to let UI render first
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            start()
        }
    }
    
    func updateDeadline(_ new: Date) {
        deadline = new
        // no need to restart timer; it always recomputes from wall clock
    }
    
    /// Resync the now snapshot (useful when app returns to foreground)
    func resync() {
        nowSnapshot = Date()
    }
    
    func start() {
        stop()
        let q = DispatchQueue(label: "pac.countdown", qos: .userInteractive)
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(50)) // small leeway
        t.setEventHandler { [weak self] in
            guard let self else { return }
            // Publish a "now" snapshot; UI will recompute difference
            let now = Date()
            Task { @MainActor in
                self.nowSnapshot = now
            }
        }
        t.resume()
        timer = t
    }
    
    func stop() {
        timer?.cancel()
        timer = nil
    }
    
    deinit {
        // deinit is not isolated, so cancel timer directly
        timer?.cancel()
        timer = nil
    }
}

