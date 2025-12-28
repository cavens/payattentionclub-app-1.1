import SwiftUI

struct BulletinView: View {
    @EnvironmentObject var model: AppModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // Countdown
                    VStack(spacing: 8) {
                        Text("Next deadline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let countdownModel = model.countdownModel {
                            CountdownView(model: countdownModel)
                        } else {
                            Text("00:00:00:00")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, 20)

                    // Recap
                    VStack(spacing: 20) {
                        Text("Week Recap")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        VStack(spacing: 15) {
                            HStack {
                                Text("Time Spent:")
                                    .font(.headline)
                                Spacer()
                                Text(formatTime(Double(model.currentUsageSeconds - model.baselineUsageSeconds)))
                                    .font(.headline)
                            }
                            
                            HStack {
                                Text("Penalty:")
                                    .font(.headline)
                                Spacer()
                                Text("$\(model.currentPenalty, specifier: "%.2f")")
                                    .font(.headline)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Commit Again Button
                    Button(action: {
                        // Reset for new period
                        model.baselineUsageSeconds = 0
                        model.currentUsageSeconds = 0
                        model.currentPenalty = 0.0
                        model.savePersistedValues()
                        model.navigate(.setup)
                    }) {
                        Text("Commit again")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.pink)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Bulletin")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(red: 226/255, green: 204/255, blue: 205/255))
            .scrollContentBackground(.hidden)
            .withLogoutButton()
            .onAppear {
                // Update usage when view appears to show current values
                updateUsage()
                model.refreshWeekStatus()
            }
        }
    }
    
    private func updateUsage() {
        // Read from App Group in background (non-blocking)
        Task.detached(priority: .userInitiated) {
            // Access UsageTracker.shared on main actor, then call nonisolated methods
            let tracker = await MainActor.run { UsageTracker.shared }
            let currentTotal = tracker.getCurrentTimeSpent()
            let baseline = tracker.getBaselineTime()
            let usageSeconds = Int(currentTotal) - Int(baseline)
            
            // Update UI on main thread
            await MainActor.run {
                model.currentUsageSeconds = usageSeconds
                model.updateCurrentPenalty()
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

