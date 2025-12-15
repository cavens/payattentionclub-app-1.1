import SwiftUI
import Foundation

struct MonitorView: View {
    @EnvironmentObject var model: AppModel
    @State private var timer: Timer?
    @State private var deadlineCheckTimer: Timer?
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 24) {
                    // Countdown to next deadline
                    VStack(spacing: 8) {
                        Text("Next deadline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let countdownModel = model.countdownModel {
                            CountdownView(model: countdownModel)
                                .onChange(of: countdownModel.nowSnapshot) { _ in
                                    // Check deadline immediately when countdown updates
                                    // This provides faster response than the 5-second timer
                                    _ = model.checkDeadlineAndNavigate()
                                }
                        } else {
                            Text("00:00:00:00")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, 20)

                SettlementStatusView(
                    status: model.weekStatus,
                    isLoading: model.isLoadingWeekStatus,
                    errorMessage: model.weekStatusError,
                    onRefresh: { model.refreshWeekStatus() }
                )
                .padding(.horizontal)

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
                }
                
                // Loading overlay during startMonitoring()
                if model.isStartingMonitoring {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        
                        Text("Starting monitoring...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                }
            }
            .navigationTitle("Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .withLogoutButton()
            .onAppear {
                startTimer()
                startDeadlineCheckTimer()
                model.refreshWeekStatus()
                // Check deadline immediately when view appears
                _ = model.checkDeadlineAndNavigate()
            }
            .onDisappear {
                stopTimer()
                stopDeadlineCheckTimer()
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
        // Read from App Group in background (non-blocking)
        // This prevents blocking the main thread and countdown timer
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
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func startDeadlineCheckTimer() {
        stopDeadlineCheckTimer()
        // Check deadline every 5 seconds (aligned with usage updates)
        deadlineCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            _ = model.checkDeadlineAndNavigate()
        }
    }
    
    private func stopDeadlineCheckTimer() {
        deadlineCheckTimer?.invalidate()
        deadlineCheckTimer = nil
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

