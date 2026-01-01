import SwiftUI
import Foundation
import FamilyControls

struct MonitorView: View {
    @EnvironmentObject var model: AppModel
    @State private var timer: Timer?
    @State private var showingSecretPanel = false
    @State private var tapCount = 0
    @State private var lastTapTime: Date?
    
    // Pink color constant: #E2CCCD
    private let pinkColor = Color(red: 226/255, green: 204/255, blue: 205/255)
    
    var body: some View {
        GeometryReader { geometry in
                ZStack {
                    // Header absolutely positioned at top - fixed position
                    VStack(alignment: .leading, spacing: 0) {
                        PageHeader()
                            .onTapGesture {
                                handleCountdownTap()
                            }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    // Rectangle absolutely positioned - 20 points below countdown (which is at bottom of 180px header)
                    VStack(spacing: 16) {
                        ZStack {
                            // White rectangle behind (empty, slid down 50 points)
                            VStack(spacing: 0) {
                                Spacer()
                                
                                // Progress bar section at bottom
                                VStack(spacing: 8) {
                                    // Progress bar - same width as sliders in setup screen
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            // Pink background
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(pinkColor)
                                                .frame(height: 4)
                                            
                                            // Black filling part
                                            let progress = min(1.0, max(0.0, Double(model.currentUsageSeconds) / 60.0 / model.limitMinutes))
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.black)
                                                .frame(width: geometry.size.width * CGFloat(progress), height: 4)
                                        }
                                    }
                                    .frame(height: 4)
                                    
                                    // Labels below progress bar
                                    HStack {
                                        // Left: minutes spent
                                        Text("\(Int(Double(model.currentUsageSeconds) / 60.0)) min spent")
                                            .font(.caption)
                                            .foregroundColor(Color(red: 102/255, green: 102/255, blue: 102/255))
                                        
                                        Spacer()
                                        
                                        // Right: time limit (aligned with right of progress bar)
                                        Text("\(Int(model.limitMinutes)) min limit")
                                            .font(.caption)
                                            .foregroundColor(Color(red: 102/255, green: 102/255, blue: 102/255))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 150) // Increased height to make progress bar more visible
                            .background(Color.white)
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .offset(y: 80) // Slide down 80 points (moved down even more)
                            
                            // Black rectangle with current penalty (on top)
                            ContentCard {
                                VStack(spacing: 0) {
                                    VStack(alignment: .center, spacing: 12) {
                                        Text("Current penalty")
                                            .font(.headline)
                                            .foregroundColor(pinkColor)
                                        
                                        Text("$\(model.currentPenalty, specifier: "%.2f")")
                                            .font(.system(size: 56, weight: .bold))
                                            .foregroundColor(pinkColor)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 120) // Double the height (same as authorization screen)
                            }
                        }
                        .frame(height: 210) // Extra height to accommodate offset white rectangle (increased for more offset)
                    }
                    .padding(.top, 220) // 180px (header height) + 40px spacing = 220px from top
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    // Text below white box (almost sticking to bottom of white box)
                    VStack(alignment: .center, spacing: 12) {
                        // Limited apps section
                        VStack(alignment: .center, spacing: 4) {
                            Text("Limited apps:")
                                .font(.body)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            Text(formatAppList())
                                .font(.body)
                                .foregroundColor(.black)
                        }
                        
                        // Space between app list and penalty text
                        Spacer()
                            .frame(height: 8)
                        
                        // Penalty explanation
                        Text("When exceeding the \(formatHours(model.limitMinutes)) hours, you will be charged $\(model.penaltyPerMinute, specifier: "%.2f") per extra minute with a maximum of $\(model.authorizationAmount, specifier: "%.2f").")
                            .font(.body)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    .padding(.top, 280) // Position almost sticking to bottom of white box (220 header + 80 offset + 150 white box = 450, but we want it close to bottom, so ~280)
                    .frame(maxWidth: .infinity, alignment: .center)
                    
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true) // Hide navigation bar to avoid white stripes
            .background(Color(red: 226/255, green: 204/255, blue: 205/255))
            .scrollContentBackground(.hidden)
            .ignoresSafeArea()
            .withLogoutButton()
            .onAppear {
                startTimer()
                model.refreshWeekStatus()
                
                // Check if deadline has already passed when view appears
                let deadlinePassed = UsageTracker.shared.isCommitmentDeadlinePassed()
                if deadlinePassed {
                    NSLog("MONITOR MonitorView: ⏰ Deadline already passed on appear, navigating to bulletin")
                    // Refresh week status to get final penalty data
                    model.refreshWeekStatus()
                    model.navigate(.bulletin)
                    return
                }
                
                // Load authorization amount from backend if not already set
                if model.authorizationAmount == 0.0 {
                    Task {
                        let amount = await model.fetchAuthorizationAmount()
                        await MainActor.run {
                            model.authorizationAmount = amount
                            model.savePersistedValues()
                        }
                    }
                }
            }
            .onChange(of: model.weekStatus) { newStatus in
                // Update authorization amount from week status (comes from backend commitment)
                if let weekStatus = newStatus {
                    let maxChargeDollars = Double(weekStatus.userMaxChargeCents) / 100.0
                    if model.authorizationAmount != maxChargeDollars {
                        model.authorizationAmount = maxChargeDollars
                        model.savePersistedValues()
                    }
                }
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
            
            // Check if deadline has passed while viewing MonitorView
            let deadlinePassed = tracker.isCommitmentDeadlinePassed()
            
            // If deadline just passed, store consumedMinutes at deadline time
            // This prevents post-deadline usage from being included in penalty calculations
            if deadlinePassed {
                let currentConsumedMinutes = await MainActor.run { tracker.getConsumedMinutes() }
                await MainActor.run {
                    tracker.storeConsumedMinutesAtDeadline(currentConsumedMinutes)
                    NSLog("MONITOR MonitorView: ⏰ Deadline passed, stored consumedMinutes at deadline: \(currentConsumedMinutes) min")
                }
            }
            
            // Update daily usage entry from consumedMinutes (periodic update)
            await MainActor.run {
                UsageSyncManager.shared.updateDailyUsageFromConsumedMinutes()
            }
            
            // Update UI on main thread
            await MainActor.run {
                model.currentUsageSeconds = usageSeconds
                model.updateCurrentPenalty()
                
                // If deadline has passed, navigate to bulletin
                if deadlinePassed {
                    NSLog("MONITOR MonitorView: ⏰ Deadline passed while viewing, navigating to bulletin")
                    // Refresh week status to get final penalty data
                    model.refreshWeekStatus()
                    model.navigate(.bulletin)
                }
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
    
    private func formatHours(_ minutes: Double) -> String {
        let hours = minutes / 60.0
        if hours == floor(hours) {
            return String(format: "%.0f", hours)
        } else {
            return String(format: "%.1f", hours)
        }
    }
    
    private func formatAppList() -> String {
        let appCount = model.selectedApps.applicationTokens.count
        let categoryCount = model.selectedApps.categoryTokens.count
        let totalCount = appCount + categoryCount
        
        if totalCount == 0 {
            return "No apps selected"
        }
        
        // Since we can't easily get app names from tokens, show count-based placeholder
        // This can be enhanced later to retrieve actual app names
        var items: [String] = []
        if appCount > 0 {
            items.append("\(appCount) app\(appCount == 1 ? "" : "s")")
        }
        if categoryCount > 0 {
            items.append("\(categoryCount) categor\(categoryCount == 1 ? "y" : "ies")")
        }
        return items.joined(separator: ", ")
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
