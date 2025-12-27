import SwiftUI
import Foundation

struct MonitorView: View {
    @EnvironmentObject var model: AppModel
    @State private var timer: Timer?
    @State private var showingSecretPanel = false
    @State private var tapCount = 0
    @State private var lastTapTime: Date?
    
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
                                .onTapGesture {
                                    handleCountdownTap()
                                }
                        } else {
                            Text("00:00:00:00")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .onTapGesture {
                                    handleCountdownTap()
                                }
                        }
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
                model.refreshWeekStatus()
            }
            .onDisappear {
                stopTimer()
            }
            .sheet(isPresented: $showingSecretPanel) {
                SecretSettlementPanel(
                    status: model.weekStatus,
                    isLoading: model.isLoadingWeekStatus,
                    errorMessage: model.weekStatusError,
                    onRefresh: { model.refreshWeekStatus() }
                )
                .environmentObject(model)
            }
        }
    }
    
    private func handleCountdownTap() {
        let now = Date()
        
        // Reset tap count if more than 1 second has passed since last tap
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) > 1.0 {
            tapCount = 0
        }
        
        tapCount += 1
        lastTapTime = now
        
        // If we've reached 3 taps, show the secret panel
        if tapCount >= 3 {
            showingSecretPanel = true
            tapCount = 0
            lastTapTime = nil
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
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

// Secret panel that shows test actions and weekly settlement
struct SecretSettlementPanel: View {
    @EnvironmentObject var model: AppModel
    let status: WeekStatusResponse?
    let isLoading: Bool
    let errorMessage: String?
    var onRefresh: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingUsageReportAlert = false
    @State private var usageReportMessage = ""
    @State private var isSyncing = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Test Actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Test Actions")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            Button(action: {
                                Task { @MainActor in
                                    await testReportUsage()
                                }
                            }) {
                                Text("🧪 Test Report Usage")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                            
                            Button(action: {
                                Task { @MainActor in
                                    await manualSync()
                                }
                            }) {
                                HStack {
                                    if isSyncing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    }
                                    Text(isSyncing ? "Syncing..." : "🔄 Manual Sync")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                            }
                            .disabled(isSyncing)
                            
                            Button(action: {
                                Task { @MainActor in
                                    skipToNearDeadline()
                                }
                            }) {
                                Text("⏰ Skip to 1 Minute")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red)
                                    .cornerRadius(12)
                            }
                            
                            Button(action: {
                                Task { @MainActor in
                                    NSLog("RESET SecretPanel: ⏭️ Skip to deadline clicked - clearing monitoring state")
                                    UsageTracker.shared.clearExpiredMonitoringState()
                                    model.navigate(.bulletin)
                                    dismiss()
                                }
                            }) {
                                Text("Skip to next deadline")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // Weekly Settlement Information
                    SettlementStatusView(
                        status: status,
                        isLoading: isLoading,
                        errorMessage: errorMessage,
                        onRefresh: onRefresh
                    )
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("Debug Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Usage Report Result", isPresented: $showingUsageReportAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(usageReportMessage)
            }
        }
    }
    
    private func testReportUsage() async {
        // Calculate used minutes
        let usedSeconds = model.currentUsageSeconds - model.baselineUsageSeconds
        let usedMinutes = max(0, Int(Double(usedSeconds) / 60.0))
        
        // Get today's date
        let today = Date()
        
        // Get the deadline (weekStartDate) from the commitment
        guard let deadline = UsageTracker.shared.getCommitmentDeadline() else {
            usageReportMessage = "❌ No commitment deadline found. Please create a commitment first."
            showingUsageReportAlert = true
            return
        }
        
        NSLog("USAGE SecretPanel: Testing usage report - usedMinutes: \(usedMinutes), today: \(today), deadline: \(deadline)")
        
        do {
            let response = try await BackendClient.shared.reportUsage(
                date: today,
                weekStartDate: deadline,
                usedMinutes: usedMinutes
            )
            
            usageReportMessage = """
            ✅ Usage reported successfully!
            
            Date: \(response.date)
            Used: \(response.usedMinutes) min
            Limit: \(response.limitMinutes) min
            Exceeded: \(response.exceededMinutes) min
            Daily Penalty: $\(Double(response.penaltyCents) / 100.0)
            Your Week Total: $\(Double(response.userWeekTotalCents) / 100.0)
            Pool Total: \(Double(response.poolTotalCents) / 100.0)
            """
            showingUsageReportAlert = true
        } catch {
            NSLog("USAGE SecretPanel: ❌ Failed to report usage: \(error)")
            usageReportMessage = "❌ Failed to report usage: \(error.localizedDescription)"
            showingUsageReportAlert = true
        }
    }
    
    private func manualSync() async {
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            try await UsageSyncManager.shared.syncToBackend()
            usageReportMessage = "✅ Sync completed successfully!"
            showingUsageReportAlert = true
        } catch {
            NSLog("SYNC SecretPanel: ❌ Failed to sync: \(error)")
            usageReportMessage = "❌ Failed to sync: \(error.localizedDescription)"
            showingUsageReportAlert = true
        }
    }
    
    private func skipToNearDeadline() {
        // Set deadline to 1 minute from now
        let newDeadline = Date().addingTimeInterval(60) // 1 minute from now
        
        // Update the countdown model if it exists
        if let countdownModel = model.countdownModel {
            countdownModel.updateDeadline(newDeadline)
        }
        
        // Update the stored deadline in App Group
        UsageTracker.shared.storeCommitmentDeadline(newDeadline)
        
        NSLog("SKIP SecretPanel: ⏰ Skipped deadline to 1 minute from now: \(newDeadline)")
        usageReportMessage = "✅ Deadline skipped to 1 minute from now!"
        showingUsageReportAlert = true
    }
}

