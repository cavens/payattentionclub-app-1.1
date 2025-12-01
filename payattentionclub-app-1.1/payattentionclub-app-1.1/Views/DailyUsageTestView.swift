import SwiftUI
import Foundation

/// Test view for Phase 2: Verify daily usage entries are stored in App Group
/// This view reads and displays all daily usage entries written by the extension
struct DailyUsageTestView: View {
    @EnvironmentObject var model: AppModel
    @State private var entries: [DailyUsageEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSyncing = false
    @State private var syncMessage: String?
    
    private let appGroupIdentifier = "group.com.payattentionclub.app"
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Daily Usage Storage Test")
                    .font(.largeTitle)
                    .padding()
                
                Text("Phase 2: Verify extension writes daily usage entries")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if isLoading {
                    ProgressView("Loading entries...")
                        .padding()
                }
                
                if let error = errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("❌ Error:")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding()
                }
                
                if entries.isEmpty && !isLoading {
                    VStack(spacing: 10) {
                        Text("No daily usage entries found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Create a commitment and use limited apps to trigger thresholds")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(entries, id: \.date) { entry in
                            DailyUsageEntryCard(entry: entry)
                        }
                    }
                    .padding()
                }
                
                // Sync status message
                if let syncMsg = syncMessage {
                    Text(syncMsg)
                        .font(.caption)
                        .foregroundColor(syncMsg.contains("✅") ? .green : .red)
                        .padding(.horizontal)
                }
                
                // Test entry creation button
                Button(action: {
                    createTestEntry()
                }) {
                    Text("🧪 Create Test Entry (5 min)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
                HStack(spacing: 20) {
                    Button(action: {
                        loadEntries()
                    }) {
                        Text("Refresh")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        syncToBackend()
                    }) {
                        HStack {
                            if isSyncing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isSyncing ? "Syncing..." : "Sync Now")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isSyncing ? Color.gray : Color.green)
                        .cornerRadius(10)
                    }
                    .disabled(isSyncing)
                    
                    Button(action: {
                        clearAllEntries()
                    }) {
                        Text("Clear All")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("Daily Usage Test")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        model.currentScreen = .monitor
                    }
                }
            }
            .onAppear {
                loadEntries()
            }
        }
    }
    
    private func loadEntries() {
        isLoading = true
        errorMessage = nil
        
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            errorMessage = "Failed to access App Group"
            isLoading = false
            return
        }
        
        var foundEntries: [DailyUsageEntry] = []
        
        // Scan all keys for daily_usage_* pattern
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let dailyUsageKeys = allKeys.filter { $0.hasPrefix("daily_usage_") }
        
        NSLog("DAILY_USAGE_TEST: Found \(dailyUsageKeys.count) daily usage keys")
        
        for key in dailyUsageKeys.sorted() {
            if let data = userDefaults.data(forKey: key) {
                do {
                    let entry = try JSONDecoder().decode(DailyUsageEntry.self, from: data)
                    foundEntries.append(entry)
                    NSLog("DAILY_USAGE_TEST: ✅ Decoded entry for \(entry.date)")
                } catch {
                    NSLog("DAILY_USAGE_TEST: ❌ Failed to decode entry for key \(key): \(error)")
                    errorMessage = "Failed to decode entry for \(key): \(error.localizedDescription)"
                }
            }
        }
        
        // Sort by date (newest first)
        foundEntries.sort { $0.date > $1.date }
        
        DispatchQueue.main.async {
            self.entries = foundEntries
            self.isLoading = false
        }
    }
    
    private func clearAllEntries() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }
        
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let dailyUsageKeys = allKeys.filter { $0.hasPrefix("daily_usage_") }
        
        for key in dailyUsageKeys {
            userDefaults.removeObject(forKey: key)
        }
        
        // Also clear last_threshold_* keys
        let thresholdKeys = allKeys.filter { $0.hasPrefix("last_threshold_") }
        for key in thresholdKeys {
            userDefaults.removeObject(forKey: key)
        }
        
        userDefaults.synchronize()
        
        NSLog("DAILY_USAGE_TEST: 🧹 Cleared \(dailyUsageKeys.count) daily usage entries and \(thresholdKeys.count) threshold keys")
        
        loadEntries()
    }
    
    private func syncToBackend() {
        isSyncing = true
        syncMessage = nil
        
        Task {
            do {
                NSLog("DAILY_USAGE_TEST: 🚀 Manual sync triggered")
                try await UsageSyncManager.shared.syncToBackend()
                await MainActor.run {
                    syncMessage = "✅ Sync completed successfully!"
                    isSyncing = false
                    // Reload entries to see updated sync status
                    loadEntries()
                }
            } catch {
                NSLog("DAILY_USAGE_TEST: ❌ Sync failed: \(error)")
                await MainActor.run {
                    syncMessage = "❌ Sync failed: \(error.localizedDescription)"
                    isSyncing = false
                }
            }
        }
    }
    
    private func createTestEntry() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            syncMessage = "❌ Failed to access App Group"
            return
        }
        
        // Get today's date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let today = dateFormatter.string(from: Date())
        
        // Get commitment data from App Group (or use defaults for testing)
        let commitmentId = userDefaults.string(forKey: "commitmentId") ?? "TEST-COMMITMENT-ID"
        let deadlineTimestamp = userDefaults.double(forKey: "commitmentDeadline")
        let baselineTimeSpent = userDefaults.double(forKey: "baselineTimeSpent")
        let baselineMinutes = baselineTimeSpent / 60.0
        
        // Calculate week start date
        let weekStartDate: String
        if deadlineTimestamp > 0 {
            let deadlineDate = Date(timeIntervalSince1970: deadlineTimestamp)
            weekStartDate = dateFormatter.string(from: deadlineDate)
        } else {
            // Default to next Monday if no deadline
            let calendar = Calendar.current
            let todayDate = Date()
            let weekday = calendar.component(.weekday, from: todayDate)
            let daysUntilMonday = (2 - weekday + 7) % 7
            let nextMonday = calendar.date(byAdding: .day, value: daysUntilMonday == 0 ? 7 : daysUntilMonday, to: todayDate) ?? todayDate
            weekStartDate = dateFormatter.string(from: nextMonday)
        }
        
        // Create test entry: 5 minutes used (totalMinutes = baselineMinutes + 5)
        let testTotalMinutes = baselineMinutes + 5.0
        let testEntry = DailyUsageEntry(
            date: today,
            totalMinutes: testTotalMinutes,
            baselineMinutes: baselineMinutes,
            weekStartDate: weekStartDate,
            commitmentId: commitmentId,
            synced: false
        )
        
        // Store in App Group (same format as extension)
        do {
            let encoded = try JSONEncoder().encode(testEntry)
            let entryKey = "daily_usage_\(today)"
            userDefaults.set(encoded, forKey: entryKey)
            userDefaults.synchronize()
            
            NSLog("DAILY_USAGE_TEST: ✅ Created test entry: date=\(today), total=\(testTotalMinutes) min, used=\(testEntry.usedMinutes) min")
            
            syncMessage = "✅ Test entry created: \(testEntry.usedMinutes) min used"
            loadEntries()
        } catch {
            NSLog("DAILY_USAGE_TEST: ❌ Failed to create test entry: \(error)")
            syncMessage = "❌ Failed to create test entry: \(error.localizedDescription)"
        }
    }
}

struct DailyUsageEntryCard: View {
    let entry: DailyUsageEntry
    
    private func formatDate(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.date)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if entry.synced {
                    Text("✅ Synced")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                } else {
                    Text("⏳ Unsynced")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(entry.totalMinutes))")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Used Minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(entry.usedMinutes)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Baseline")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(entry.baselineMinutes))")
                        .font(.title2)
                        .fontWeight(.bold)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Week Start: \(entry.weekStartDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Commitment ID: \(entry.commitmentId)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Last Updated: \(formatDate(entry.lastUpdatedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    DailyUsageTestView()
}

