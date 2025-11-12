import SwiftUI

struct MonitorView: View {
    @EnvironmentObject var model: AppModel
    @State private var timer: Timer?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Countdown to next deadline
                VStack(spacing: 8) {
                    Text("Next deadline")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CountdownView(model: model)
                }
                .padding(.top, 20)
                
                // Progress Bar
                VStack(alignment: .leading, spacing: 15) {
                    Text("Time Spent")
                        .font(.headline)
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 40)
                                .cornerRadius(8)
                            
                            // Progress
                            let usageMinutes = Double(model.currentUsageSeconds - model.baselineUsageSeconds) / 60.0
                            let progress = min(usageMinutes / model.limitMinutes, 1.0)
                            
                            Rectangle()
                                .fill(Color.pink)
                                .frame(
                                    width: min(geometry.size.width * CGFloat(progress), geometry.size.width),
                                    height: 40
                                )
                                .cornerRadius(8)
                            
                            // Time label
                            HStack {
                                Text(formatTime(Double(model.currentUsageSeconds - model.baselineUsageSeconds)))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(formatTime(model.limitMinutes * 60))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .frame(height: 40)
                }
                .padding(.horizontal)
                
                // Current Penalty
                VStack(spacing: 10) {
                    Text("Current Penalty")
                        .font(.headline)
                    
                    Text("$\(model.currentPenalty, specifier: "%.2f")")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // Skip Button (temporary)
                Button(action: {
                    model.navigate(.bulletin)
                }) {
                    Text("Skip to next deadline")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .navigationTitle("Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                startTimer()
            }
            .onDisappear {
                stopTimer()
            }
        }
    }
    
    private func startTimer() {
        stopTimer()
        // Update every 5 seconds to read from App Group (written by Monitor Extension)
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            updateUsage()
        }
        // Initial update
        updateUsage()
    }
    
    private func updateUsage() {
        // Read consumed time from App Group (written by Monitor Extension)
        let currentTotal = UsageTracker.shared.getCurrentTimeSpent()
        
        // Subtract baseline to get time since "Lock in" was pressed
        let baseline = UsageTracker.shared.getBaselineTime()
        let previousUsage = model.currentUsageSeconds
        model.currentUsageSeconds = Int(currentTotal) - Int(baseline)
        model.updateCurrentPenalty()
        
        NSLog("MARKERS MonitorView: 🔄 updateUsage() - currentTotal: %.0f, baseline: %.0f, usage: %d seconds (was: %d)",
              currentTotal, baseline, model.currentUsageSeconds, previousUsage)
        print("MARKERS MonitorView: 🔄 updateUsage() - currentTotal: \(currentTotal), baseline: \(baseline), usage: \(model.currentUsageSeconds) seconds (was: \(previousUsage))")
        fflush(stdout)
        
        // Check if we have real threshold data
        let isActive = UsageTracker.shared.isMonitoringActive()
        NSLog("MARKERS MonitorView: Monitoring active: %@", isActive ? "YES ✅" : "NO ❌")
        print("MARKERS MonitorView: Monitoring active: \(isActive ? "YES ✅" : "NO ❌")")
        fflush(stdout)
        
        if model.currentUsageSeconds == 0 && isActive {
            NSLog("MARKERS MonitorView: ⚠️ Usage is 0 but monitoring is active")
            print("MARKERS MonitorView: ⚠️ Usage is 0 but monitoring is active")
            NSLog("MARKERS MonitorView: 💡 Make sure you're actually USING the selected apps!")
            print("MARKERS MonitorView: 💡 Make sure you're actually USING the selected apps!")
            NSLog("MARKERS MonitorView: 💡 Check Console.app for 'MARKERS MonitorExtension' logs")
            print("MARKERS MonitorView: 💡 Check Console.app for 'MARKERS MonitorExtension' logs")
            fflush(stdout)
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

