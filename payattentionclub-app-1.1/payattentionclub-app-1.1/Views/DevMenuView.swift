import SwiftUI
import Foundation

/// Developer Menu for testing and debugging
/// Access via triple-tap on countdown timer
/// Only visible in staging mode or for test users
struct DevMenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isTestingBackend = false
    @State private var backendResult: String = ""
    @State private var isReportingUsage = false
    @State private var usageResult: String = ""
    @State private var isResettingData = false
    @State private var resetResult: String = ""
    @State private var isTriggeringClose = false
    @State private var closeResult: String = ""
    @State private var selectedTestDeadlineMinutes: Int = 1
    @State private var testDeadlineResult: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Environment Badge
                    environmentSection
                    
                    // Quick Actions
                    quickActionsSection
                    
                    // Week Controls
                    weekControlsSection
                    
                    // Debug Info
                    debugInfoSection
                }
                .padding()
            }
            .navigationTitle("🛠️ Dev Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Environment Section
    
    private var environmentSection: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(AppConfig.isProduction ? Color.red : Color.green)
                    .frame(width: 12, height: 12)
                Text(AppConfig.environment.displayName.uppercased())
                    .font(.headline)
                    .foregroundColor(AppConfig.isProduction ? .red : .green)
            }
            
            if let session = getCurrentUserEmail() {
                Text("User: \(session)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            
            // Set Limit to 1 minute
            Button(action: {
                model.limitMinutes = 1.0
                model.savePersistedValues()
            }) {
                HStack {
                    Image(systemName: "timer")
                    Text("Set Limit to 1 min")
                    Spacer()
                }
                .padding()
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // Test Backend Connection
            Button(action: testBackendConnection) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Test Backend Connection")
                    Spacer()
                    if isTestingBackend {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isTestingBackend)
            
            if !backendResult.isEmpty {
                Text(backendResult)
                    .font(.caption)
                    .foregroundColor(backendResult.contains("✅") ? .green : .red)
                    .padding(.horizontal)
            }
            
            // Test Report Usage
            Button(action: testReportUsage) {
                HStack {
                    Image(systemName: "chart.bar")
                    Text("Test Report Usage")
                    Spacer()
                    if isReportingUsage {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()
                .background(Color.purple.opacity(0.2))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isReportingUsage)
            
            if !usageResult.isEmpty {
                Text(usageResult)
                    .font(.caption)
                    .foregroundColor(usageResult.contains("✅") ? .green : .red)
                    .padding(.horizontal)
            }
            
            // Sync Daily Usage
            Button(action: syncDailyUsage) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync Daily Usage (\(UsageSyncManager.shared.getUnsyncedCount()) unsynced)")
                    Spacer()
                }
                .padding()
                .background(Color.teal.opacity(0.2))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Week Controls Section
    
    private var weekControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Week Controls")
                .font(.headline)
            
            // Set Test Deadline
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock.badge")
                    Text("Set Test Deadline")
                        .font(.headline)
                    Spacer()
                }
                
                HStack {
                    Picker("Minutes", selection: $selectedTestDeadlineMinutes) {
                        Text("1 min").tag(1)
                        Text("2 min").tag(2)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("30 min").tag(30)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 120)
                    
                    Button(action: setTestDeadline) {
                        Text("Set")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                }
                
                if !testDeadlineResult.isEmpty {
                    Text(testDeadlineResult)
                        .font(.caption)
                        .foregroundColor(testDeadlineResult.contains("✅") ? .green : .red)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            // Skip to Deadline / Bulletin
            Button(action: {
                NSLog("DEVMENU: Skipping to deadline - clearing monitoring state")
                UsageTracker.shared.clearExpiredMonitoringState()
                model.navigate(.bulletin)
                dismiss()
            }) {
                HStack {
                    Image(systemName: "forward.end")
                    Text("Skip to Deadline (→ Bulletin)")
                    Spacer()
                }
                .padding()
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            // Trigger Weekly Close
            Button(action: triggerWeeklyClose) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                    Text("Trigger Weekly Close")
                    Spacer()
                    if isTriggeringClose {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.2))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isTriggeringClose)
            
            if !closeResult.isEmpty {
                Text(closeResult)
                    .font(.caption)
                    .foregroundColor(closeResult.contains("✅") ? .green : .red)
                    .padding(.horizontal)
            }
            
            // Reset Test Data
            Button(action: resetTestData) {
                HStack {
                    Image(systemName: "trash")
                    Text("Reset Test Data")
                    Spacer()
                    if isResettingData {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.2))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isResettingData)
            
            if !resetResult.isEmpty {
                Text(resetResult)
                    .font(.caption)
                    .foregroundColor(resetResult.contains("✅") ? .green : .red)
                    .padding(.horizontal)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Debug Info Section
    
    private var debugInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug Info")
                .font(.headline)
            
            Group {
                debugRow("Environment", AppConfig.environment.displayName)
                debugRow("Supabase URL", SupabaseConfig.projectURL)
                debugRow("Stripe Mode", StripeConfig.environment)
                debugRow("Limit (min)", String(format: "%.0f", model.limitMinutes))
                debugRow("Penalty/min", String(format: "$%.2f", model.penaltyPerMinute))
                debugRow("Current Screen", String(describing: model.currentScreen))
                
                if let deadline = UsageTracker.shared.getCommitmentDeadline() {
                    debugRow("Deadline", deadline.formatted())
                }
            }
            .font(.caption)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
    
    // MARK: - Actions
    
    private func getCurrentUserEmail() -> String? {
        // This would ideally come from the auth session
        // For now return nil - can be enhanced later
        return nil
    }
    
    private func testBackendConnection() {
        isTestingBackend = true
        backendResult = ""
        
        Task {
            let startTime = Date()
            do {
                let response = try await BackendClient.shared.checkBillingStatus()
                let duration = Date().timeIntervalSince(startTime)
                
                await MainActor.run {
                    backendResult = "✅ Connected (\(String(format: "%.2f", duration))s) - hasPayment: \(response.hasPaymentMethod)"
                    isTestingBackend = false
                }
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                await MainActor.run {
                    backendResult = "❌ Failed (\(String(format: "%.2f", duration))s): \(error.localizedDescription)"
                    isTestingBackend = false
                }
            }
        }
    }
    
    private func testReportUsage() {
        isReportingUsage = true
        usageResult = ""
        
        Task {
            let usedSeconds = model.currentUsageSeconds - model.baselineUsageSeconds
            let usedMinutes = max(0, Int(Double(usedSeconds) / 60.0))
            let today = Date()
            
            guard let deadline = UsageTracker.shared.getCommitmentDeadline() else {
                await MainActor.run {
                    usageResult = "❌ No commitment deadline found"
                    isReportingUsage = false
                }
                return
            }
            
            do {
                let response = try await BackendClient.shared.reportUsage(
                    date: today,
                    weekStartDate: deadline,
                    usedMinutes: usedMinutes
                )
                
                await MainActor.run {
                    usageResult = "✅ Reported: \(response.usedMinutes)min, penalty: $\(Double(response.penaltyCents) / 100.0)"
                    isReportingUsage = false
                }
            } catch {
                await MainActor.run {
                    usageResult = "❌ Failed: \(error.localizedDescription)"
                    isReportingUsage = false
                }
            }
        }
    }
    
    private func syncDailyUsage() {
        Task {
            do {
                try await UsageSyncManager.shared.syncToBackend()
                NSLog("DEVMENU: ✅ Daily usage synced")
            } catch {
                NSLog("DEVMENU: ❌ Sync failed: \(error)")
            }
        }
    }
    
    private func triggerWeeklyClose() {
        isTriggeringClose = true
        closeResult = ""
        
        Task {
            // This would call the admin-close-week-now edge function
            // For now, just simulate
            do {
                // TODO: Implement actual edge function call
                // let response = try await BackendClient.shared.triggerWeeklyClose()
                try await Task.sleep(nanoseconds: 1_000_000_000)
                
                await MainActor.run {
                    closeResult = "⚠️ Not yet implemented - use Supabase dashboard"
                    isTriggeringClose = false
                }
            } catch {
                await MainActor.run {
                    closeResult = "❌ Failed: \(error.localizedDescription)"
                    isTriggeringClose = false
                }
            }
        }
    }
    
    private func setTestDeadline() {
        testDeadlineResult = ""
        
        // Calculate deadline: current time + selected minutes
        let deadline = Date().addingTimeInterval(TimeInterval(selectedTestDeadlineMinutes * 60))
        
        // Store the test deadline
        UsageTracker.shared.storeCommitmentDeadline(deadline)
        
        // Ensure monitoring is active (set the flag if not already set)
        guard let userDefaults = UserDefaults(suiteName: "group.com.payattentionclub.app") else {
            testDeadlineResult = "❌ Failed to access App Group"
            return
        }
        
        // Set monitoring flag if not already set
        if !userDefaults.bool(forKey: "monitoringSelectionSet") {
            userDefaults.set(true, forKey: "monitoringSelectionSet")
            userDefaults.synchronize()
        }
        
        // Update countdown model with test deadline (don't call refreshCachedDeadline as it would recalculate)
        if let countdownModel = model.countdownModel {
            countdownModel.updateDeadline(deadline)
        } else {
            // Create countdown model if it doesn't exist
            model.countdownModel = CountdownModel(deadline: deadline)
        }
        
        // Navigate to monitor screen if not already there
        if model.currentScreen != .monitor {
            model.navigate(.monitor)
        }
        
        let deadlineFormatted = deadline.formatted(date: .omitted, time: .shortened)
        testDeadlineResult = "✅ Test deadline set: \(deadlineFormatted) (\(selectedTestDeadlineMinutes) min from now)"
        
        NSLog("DEVMENU: Test deadline set to \(deadlineFormatted) (\(selectedTestDeadlineMinutes) minutes from now)")
    }
    
    private func resetTestData() {
        isResettingData = true
        resetResult = ""
        
        Task {
            // This would call rpc_cleanup_test_data then rpc_setup_test_data
            // For now, just simulate
            do {
                // TODO: Implement actual RPC calls
                try await Task.sleep(nanoseconds: 1_000_000_000)
                
                await MainActor.run {
                    resetResult = "⚠️ Not yet implemented - use Supabase dashboard"
                    isResettingData = false
                }
            } catch {
                await MainActor.run {
                    resetResult = "❌ Failed: \(error.localizedDescription)"
                    isResettingData = false
                }
            }
        }
    }
}

#Preview {
    DevMenuView()
        .environmentObject(AppModel())
}





