import SwiftUI

struct CountdownView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: CountdownModel
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let components = format(deadline: model.deadline, now: context.date)
            HStack(spacing: 8) {
                TimeUnit(value: components.days, label: "D")
                Text(":")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                TimeUnit(value: components.hours, label: "H")
                Text(":")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                TimeUnit(value: components.minutes, label: "M")
                Text(":")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                TimeUnit(value: components.seconds, label: "S")
            }
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
    
    private func format(deadline: Date, now: Date) -> (days: Int, hours: Int, minutes: Int, seconds: Int) {
        let interval = max(0, Int(deadline.timeIntervalSince(now)))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60
        let seconds = interval % 60
        return (days, hours, minutes, seconds)
    }
}

struct TimeUnit: View {
    let value: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", value))
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

