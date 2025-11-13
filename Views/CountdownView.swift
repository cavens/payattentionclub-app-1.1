import SwiftUI

struct CountdownView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: CountdownModel
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let text = format(deadline: model.deadline, now: context.date)
            Text(text)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // one-shot resync: nudge model so we re-render immediately
                        // (TimelineView will tick anyway, this just snaps after resume)
                        model.resync()
                    }
                }
        }
        // Optional: also listen to model.nowSnapshot to trigger an immediate refresh
        // in case TimelineView coalesces; usually not necessary, but harmless:
        .id(model.nowSnapshot.timeIntervalSince1970.rounded())
    }
    
    private func format(deadline: Date, now: Date) -> String {
        let interval = max(0, Int(deadline.timeIntervalSince(now)))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60
        let seconds = interval % 60
        // Show DD:HH:MM:SS
        return String(format: "%02d:%02d:%02d:%02d", days, hours, minutes, seconds)
    }
}

