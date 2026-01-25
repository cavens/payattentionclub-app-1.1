import Foundation
import os.log

/// Simple synchronization using a serial queue and atomic operations
/// More reliable than actors for this use case
final class SyncCoordinator {
    static let shared = SyncCoordinator()
    
    private let queue = DispatchQueue(label: "com.payattentionclub2.0.app.sync", qos: .userInitiated)
    private var _isSyncing = false
    private var _lastSyncTimestamp: TimeInterval = 0
    private let minSyncInterval: TimeInterval = 5.0
    
    private init() {}
    
    func tryStartSync() async -> Bool {
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }
                
                let isSyncing = self._isSyncing
                let now = Date().timeIntervalSince1970
                let timeSinceLastSync = now - self._lastSyncTimestamp
                
                guard !isSyncing else {
                    continuation.resume(returning: false)
                    return
                }
                
                guard timeSinceLastSync >= self.minSyncInterval else {
                    continuation.resume(returning: false)
                    return
                }
                
                self._isSyncing = true
                self._lastSyncTimestamp = now
                continuation.resume(returning: true)
            }
        }
    }
    
    func endSync() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                self._isSyncing = false
                continuation.resume()
            }
        }
    }
}

/// Manages syncing daily usage entries from App Group to backend
/// Phase 3: Reads unsynced entries and uploads them to the server
@MainActor
class UsageSyncManager {
    static let shared = UsageSyncManager()
    
    private let appGroupIdentifier = "group.com.payattentionclub2.0.app"
    private let backendClient = BackendClient.shared
    
    private init() {}
    
    // MARK: - Read Unsynced Usage
    
    /// Read all unsynced daily usage entries from App Group
    /// Returns entries sorted by date (oldest first)
    func getUnsyncedUsage() -> [DailyUsageEntry] {
        NSLog("SYNC UsageSyncManager: 🔍 getUnsyncedUsage() called - scanning App Group for usage entries...")
        
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            SyncLogger.error("SYNC UsageSyncManager: ❌ Failed to access App Group '\(appGroupIdentifier)'")
            return []
        }
        
        var unsyncedEntries: [DailyUsageEntry] = []
        
        // NOTE: dictionaryRepresentation() includes standard UserDefaults keys too
        // Filter out system keys and only look for App Group keys
        let allKeys = userDefaults.dictionaryRepresentation().keys
        NSLog("SYNC UsageSyncManager: 📋 Found \(allKeys.count) total keys in App Group")
        
        // Filter to exclude system keys (these shouldn't be in App Group)
        let systemKeyPrefixes = ["Apple", "NS", "AK", "PK", "IN", "MSV", "Car", "TV", "Adding", "Hyphenates"]
        let appGroupKeys = allKeys.filter { key in
            !systemKeyPrefixes.contains { key.hasPrefix($0) }
        }
        NSLog("SYNC UsageSyncManager: 📋 After filtering system keys: \(appGroupKeys.count) app group keys")
        
        // Scan App Group keys for daily_usage_* pattern
        let dailyUsageKeys = appGroupKeys.filter { $0.hasPrefix("daily_usage_") }
        NSLog("SYNC UsageSyncManager: 📋 Found \(dailyUsageKeys.count) daily_usage_* keys")
        
        var totalEntries = 0
        var syncedEntries = 0
        var failedEntries = 0
        
        for key in dailyUsageKeys.sorted() {
            if let data = userDefaults.data(forKey: key) {
                do {
                    let entry = try JSONDecoder().decode(DailyUsageEntry.self, from: data)
                    totalEntries += 1
                    if !entry.synced {
                        unsyncedEntries.append(entry)
                        NSLog("SYNC UsageSyncManager: 📝 Found UNSYNCED entry: date=\(entry.date), usedMinutes=\(max(0, Int(entry.totalMinutes - entry.baselineMinutes))), weekStartDate=\(entry.weekStartDate)")
                    } else {
                        syncedEntries += 1
                        NSLog("SYNC UsageSyncManager: ✅ Found SYNCED entry: date=\(entry.date), usedMinutes=\(max(0, Int(entry.totalMinutes - entry.baselineMinutes)))")
                    }
                } catch {
                    failedEntries += 1
                    // Log only errors
                    SyncLogger.error("SYNC UsageSyncManager: ❌ Failed to decode entry for key \(key): \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        SyncLogger.error("SYNC UsageSyncManager: Raw JSON data: \(jsonString.prefix(200))")
                    }
                }
            }
        }
        
        NSLog("SYNC UsageSyncManager: 📊 Summary - Total: \(totalEntries), Synced: \(syncedEntries), Unsynced: \(unsyncedEntries.count), Failed: \(failedEntries)")
        
        // Sort by date (oldest first) to sync in chronological order
        unsyncedEntries.sort { $0.date < $1.date }
        
        if !unsyncedEntries.isEmpty {
            NSLog("SYNC UsageSyncManager: 📅 Unsynced entries date range: \(unsyncedEntries.first!.date) to \(unsyncedEntries.last!.date)")
        }
        
        return unsyncedEntries
    }
    
    // MARK: - Sync to Backend
    
    /// Sync all unsynced daily usage entries to the backend
    /// Uploads entries in batches and marks them as synced after successful upload
    /// Prevents concurrent syncs and throttles sync frequency
    /// Uses serial queue for atomic check-and-set (async-safe)
    func syncToBackend() async throws {
        NSLog("SYNC UsageSyncManager: 🔄 syncToBackend() called at \(Date())")
        
        // Use coordinator to atomically check and set sync flag (async-safe)
        // CRITICAL: This must be the FIRST thing we do - no other work before this
        let canStart = await SyncCoordinator.shared.tryStartSync()
        
        guard canStart else {
            NSLog("SYNC UsageSyncManager: ⏭️ Sync skipped - already in progress or too soon since last sync")
            return
        }
        
        NSLog("SYNC UsageSyncManager: ✅ Sync coordinator approved - proceeding with sync")
        
        // Always clear syncing flag when done (use async defer pattern)
        defer {
            Task { @MainActor in
                await SyncCoordinator.shared.endSync()
                NSLog("SYNC UsageSyncManager: 🏁 Sync coordinator released")
            }
        }
        
        // Check for unsynced entries
        NSLog("SYNC UsageSyncManager: 🔍 Checking for unsynced entries...")
        let unsyncedEntries = getUnsyncedUsage()
        
        NSLog("SYNC UsageSyncManager: 📊 Found \(unsyncedEntries.count) unsynced entry/entries")
        
        if unsyncedEntries.isEmpty {
            NSLog("SYNC UsageSyncManager: ℹ️ No unsynced entries to sync - exiting")
            return
        }
        
        // Log details of entries to be synced
        for (index, entry) in unsyncedEntries.enumerated() {
            NSLog("SYNC UsageSyncManager: 📝 Entry \(index + 1)/\(unsyncedEntries.count): date=\(entry.date), totalMinutes=\(entry.totalMinutes), baselineMinutes=\(entry.baselineMinutes), usedMinutes=\(max(0, Int(entry.totalMinutes - entry.baselineMinutes))), weekStartDate=\(entry.weekStartDate), synced=\(entry.synced)")
        }
        
        // Check authentication before attempting sync
        let isAuthenticated = await backendClient.isAuthenticated
        NSLog("SYNC UsageSyncManager: 🔐 Authentication status: \(isAuthenticated ? "✅ Authenticated" : "❌ Not authenticated")")
        
        guard isAuthenticated else {
            NSLog("SYNC UsageSyncManager: ❌ Cannot sync - user not authenticated")
            throw NSError(domain: "UsageSyncManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        do {
            NSLog("SYNC UsageSyncManager: 🚀 Starting sync of \(unsyncedEntries.count) entries to backend...")
            // Sync all entries at once using batch method
            let syncedDates = try await backendClient.syncDailyUsage(unsyncedEntries)
            
            NSLog("SYNC UsageSyncManager: 📤 Backend sync completed - \(syncedDates.count) date(s) synced successfully")
            NSLog("SYNC UsageSyncManager: ✅ Synced dates: \(syncedDates.joined(separator: ", "))")
            
            // Only mark as synced if we have successfully synced dates
            guard !syncedDates.isEmpty else {
                NSLog("SYNC UsageSyncManager: ⚠️ No dates were synced by backend, skipping markAsSynced()")
                return
            }
            
            NSLog("SYNC UsageSyncManager: 🏷️ Marking \(syncedDates.count) entries as synced in App Group...")
            // Mark entries as synced after successful upload
            markAsSynced(dates: syncedDates)
            NSLog("SYNC UsageSyncManager: ✅ Successfully marked \(syncedDates.count) entries as synced")
        } catch {
            // Log detailed error information
            NSLog("SYNC UsageSyncManager: ❌ Failed to sync entries: \(error)")
            if let nsError = error as NSError? {
                NSLog("SYNC UsageSyncManager: ❌ Error domain: \(nsError.domain), code: \(nsError.code)")
                NSLog("SYNC UsageSyncManager: ❌ Error description: \(nsError.localizedDescription)")
                if let userInfo = nsError.userInfo as? [String: Any] {
                    NSLog("SYNC UsageSyncManager: ❌ Error userInfo: \(userInfo)")
                }
            }
            throw error
        }
    }
    
    // MARK: - Mark as Synced
    
    /// Mark daily usage entries as synced in App Group
    /// Updates the `synced` flag to true for the specified dates
    /// CRITICAL: Only marks as synced if deadline has passed (usage is finalized)
    /// Before deadline: entries remain unsynced so they can be re-synced as usage increases
    /// After deadline: usage is finalized, safe to mark as synced
    /// Works for both normal mode (7-day week) and testing mode (3-minute week)
    /// Idempotent: skips entries that are already synced
    func markAsSynced(dates: [String]) {
        guard !dates.isEmpty else {
            NSLog("SYNC UsageSyncManager: ⚠️ markAsSynced() called with empty dates array")
            return
        }
        
        NSLog("SYNC UsageSyncManager: 📝 markAsSynced() called for \(dates.count) dates: \(dates.joined(separator: ", "))")
        
        // CRITICAL FIX: Check if deadline has passed before marking as synced
        // Before deadline: usage is still accumulating, so keep entries unsynced
        // After deadline: usage is finalized, safe to mark as synced
        // This works for both normal mode (7-day week) and testing mode (3-minute week)
        let deadlinePassed = UsageTracker.shared.isCommitmentDeadlinePassed()
        
        if !deadlinePassed {
            NSLog("SYNC UsageSyncManager: ⏰ Deadline has not passed yet - keeping entries unsynced so they can be re-synced as usage increases")
            NSLog("SYNC UsageSyncManager: ℹ️ Entries will be marked as synced after deadline passes")
            return
        }
        
        NSLog("SYNC UsageSyncManager: ✅ Deadline has passed - marking entries as synced (usage is finalized)")
        
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("SYNC UsageSyncManager: ❌ Failed to access App Group")
            return
        }
        
        var markedCount = 0
        var skippedCount = 0
        
        for date in dates {
            let key = "daily_usage_\(date)"
            
            guard let data = userDefaults.data(forKey: key) else {
                NSLog("SYNC UsageSyncManager: ⚠️ Entry not found for date \(date)")
                continue
            }
            
            do {
                let entry = try JSONDecoder().decode(DailyUsageEntry.self, from: data)
                
                // Idempotency check: skip if already synced
                if entry.synced {
                    NSLog("SYNC UsageSyncManager: ⏭️ Entry for \(date) already synced, skipping")
                    skippedCount += 1
                    continue
                }
                
                // Mark as synced (only reached if deadline has passed)
                let updatedEntry = entry.markingAsSynced()
                
                // Store updated entry
                let encoded = try JSONEncoder().encode(updatedEntry)
                userDefaults.set(encoded, forKey: key)
                
                markedCount += 1
                NSLog("SYNC UsageSyncManager: ✅ Marked entry for \(date) as synced")
            } catch {
                NSLog("SYNC UsageSyncManager: ❌ Failed to mark entry for \(date) as synced: \(error)")
            }
        }
        
        userDefaults.synchronize()
        NSLog("SYNC UsageSyncManager: ✅ Marked \(markedCount) entries as synced, skipped \(skippedCount) already-synced entries")
    }
    
    // MARK: - Create/Update Daily Usage Entries
    
    /// Create or update daily usage entry from consumedMinutes
    /// This should be called periodically (on app foreground, after commitment creation)
    /// to convert extension's consumedMinutes into DailyUsageEntry objects
    /// IMPORTANT: Only includes usage that happened BEFORE the deadline
    func updateDailyUsageFromConsumedMinutes() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            NSLog("SYNC UsageSyncManager: ❌ Failed to access App Group")
            return
        }
        
        // Get commitment info
        guard let commitmentId = UsageTracker.shared.getCommitmentId(),
              let deadline = UsageTracker.shared.getCommitmentDeadline() else {
            // No active commitment, skip
            return
        }
        
        // CRITICAL: Check if deadline has passed
        // If deadline has passed, we should NOT update entries with post-deadline usage
        let now = Date()
        let deadlinePassed = now >= deadline
        
        // Get consumed minutes - use stored value at deadline if deadline has passed
        let consumedMinutes: Double
        if deadlinePassed {
            // Deadline has passed - try multiple strategies to get pre-deadline value:
            // 1. First, try stored value at deadline (if app was running when deadline passed)
            if let storedMinutes = UsageTracker.shared.getConsumedMinutesAtDeadline() {
                consumedMinutes = storedMinutes
                NSLog("SYNC UsageSyncManager: ⏰ Deadline passed, using stored consumedMinutes at deadline: \(storedMinutes) min")
            } else if let historyMinutes = UsageTracker.shared.getConsumedMinutesAtDeadlineFromHistory(deadline: deadline) {
                // 2. If no stored value, use threshold history to find last threshold before deadline
                // This handles the case where app was killed before deadline
                consumedMinutes = historyMinutes
                NSLog("SYNC UsageSyncManager: ⏰ Deadline passed, using threshold history: \(historyMinutes) min (last threshold before deadline)")
            } else {
                // 3. Fallback: Use current value but log a warning
                // This should rarely happen (only if no thresholds occurred before deadline)
                consumedMinutes = userDefaults.double(forKey: "consumedMinutes")
                NSLog("SYNC UsageSyncManager: ⚠️ Deadline passed but no stored value or history, using current consumedMinutes: \(consumedMinutes) min (may include post-deadline usage)")
            }
        } else {
            // Deadline hasn't passed yet - use current value
            consumedMinutes = userDefaults.double(forKey: "consumedMinutes")
            
            // DIAGNOSTIC: Log what the extension stored
            let lastThresholdEvent = userDefaults.string(forKey: "lastThresholdEvent") ?? "none"
            let lastThresholdTimestamp = userDefaults.double(forKey: "lastThresholdTimestamp")
            let baselineThresholdSeconds = userDefaults.integer(forKey: "baselineThresholdSeconds")
            let consumedMinutesTimestamp = userDefaults.double(forKey: "consumedMinutesTimestamp")
            
            NSLog("SYNC UsageSyncManager: 🔍 DIAGNOSTIC - consumedMinutes: %.1f min, lastThresholdEvent: %@, baselineThresholdSeconds: %d", 
                  consumedMinutes, lastThresholdEvent, baselineThresholdSeconds)
            if lastThresholdTimestamp > 0 {
                let lastThresholdDate = Date(timeIntervalSince1970: lastThresholdTimestamp)
                NSLog("SYNC UsageSyncManager: 🔍 DIAGNOSTIC - lastThresholdTimestamp: %.0f (%@)", 
                      lastThresholdTimestamp, lastThresholdDate.description)
            }
            if consumedMinutesTimestamp > 0 {
                let consumedMinutesDate = Date(timeIntervalSince1970: consumedMinutesTimestamp)
                NSLog("SYNC UsageSyncManager: 🔍 DIAGNOSTIC - consumedMinutesTimestamp: %.0f (%@)", 
                      consumedMinutesTimestamp, consumedMinutesDate.description)
            }
            
            // Check if we're very close to the deadline (within 1 second) and store the value
            // This ensures we capture the value right before the deadline
            let timeUntilDeadline = deadline.timeIntervalSince(now)
            if timeUntilDeadline <= 1.0 && timeUntilDeadline > 0 {
                UsageTracker.shared.storeConsumedMinutesAtDeadline(consumedMinutes)
                NSLog("SYNC UsageSyncManager: ⏰ Near deadline, storing consumedMinutes: \(consumedMinutes) min")
            }
        }
        
        // Get baseline minutes
        let baselineMinutes = UsageTracker.shared.getBaselineTime() / 60.0 // Convert seconds to minutes
        
        // Get today's date in YYYY-MM-DD format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let todayString = dateFormatter.string(from: now)
        
        // Format deadline as YYYY-MM-DD for weekStartDate (extracted from commitment's week_end_timestamp)
        // In testing mode, backend uses UTC date, so we use UTC here too
        // In normal mode, backend uses ET date, so we use ET here
        let deadlineFormatter = DateFormatter()
        deadlineFormatter.dateFormat = "yyyy-MM-dd"
        // Use UTC for date formatting to match backend's formatDate() function
        // The backend's formatDate() uses UTC year/month/day, so we do the same
        deadlineFormatter.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        let weekStartDateString = deadlineFormatter.string(from: deadline)
        
        // Check if entry already exists for today
        let key = "daily_usage_\(todayString)"
        
        if let existingData = userDefaults.data(forKey: key) {
            // Update existing entry
            do {
                var entry = try JSONDecoder().decode(DailyUsageEntry.self, from: existingData)
                
                // Only update if this is for the same commitment
                if entry.commitmentId == commitmentId {
                    if deadlinePassed {
                        // Deadline has passed - only update if new value is HIGHER (from threshold history/stored value)
                        // This ensures we capture the highest pre-deadline usage from threshold history
                        // If new value is lower, skip to avoid post-deadline usage
                        let previousTotal = entry.totalMinutes
                        if consumedMinutes > previousTotal {
                            // New value is higher - this is from threshold history (pre-deadline), safe to update
                            let updatedEntry = entry.updating(totalMinutes: consumedMinutes)
                            let encoded = try JSONEncoder().encode(updatedEntry)
                            userDefaults.set(encoded, forKey: key)
                            NSLog("SYNC UsageSyncManager: ✅ Updated daily usage AFTER deadline for \(todayString): \(previousTotal) → \(consumedMinutes) min (from threshold history, pre-deadline usage)")
                        } else {
                            // New value is lower or same - likely post-deadline usage, skip update
                            NSLog("SYNC UsageSyncManager: ⏰ Deadline has passed, skipping update (new value \(consumedMinutes) ≤ existing \(previousTotal), preserving pre-deadline usage)")
                        }
                    } else {
                        // Deadline hasn't passed yet - safe to update with current usage
                        // CRITICAL: Always use max to ensure we capture the highest usage value
                        // This handles cases where extension thresholds might not fire in sequence
                        let previousTotal = entry.totalMinutes
                        let updatedEntry = entry.updating(totalMinutes: max(entry.totalMinutes, consumedMinutes))
                        
                        let encoded = try JSONEncoder().encode(updatedEntry)
                        userDefaults.set(encoded, forKey: key)
                        
                        if consumedMinutes > previousTotal {
                            NSLog("SYNC UsageSyncManager: ✅ Updated daily usage for \(todayString): \(previousTotal) → \(consumedMinutes) min (increased by %.1f min)", 
                                  consumedMinutes - previousTotal)
                        } else {
                            NSLog("SYNC UsageSyncManager: ℹ️ Daily usage for \(todayString): \(consumedMinutes) min (no change from \(previousTotal))")
                        }
                    }
                } else {
                    NSLog("SYNC UsageSyncManager: ⚠️ Entry exists for different commitment, skipping update")
                }
            } catch {
                NSLog("SYNC UsageSyncManager: ❌ Failed to decode existing entry: \(error)")
            }
        } else {
            // Create new entry
            // If deadline has passed, we still create the entry but with the current consumedMinutes
            // This handles the case where the app was killed before the deadline and never created an entry
            // The backend will calculate the penalty correctly based on the limit
            let entry = DailyUsageEntry(
                date: todayString,
                totalMinutes: consumedMinutes,
                baselineMinutes: baselineMinutes,
                weekStartDate: weekStartDateString,
                commitmentId: commitmentId,
                synced: false
            )
            
            do {
                let encoded = try JSONEncoder().encode(entry)
                userDefaults.set(encoded, forKey: key)
                userDefaults.synchronize()
                if deadlinePassed {
                    NSLog("SYNC UsageSyncManager: ⚠️ Created daily usage entry AFTER deadline for \(todayString): \(consumedMinutes) min (deadline passed, may include post-deadline usage)")
                } else {
                    NSLog("SYNC UsageSyncManager: ✅ Created daily usage entry for \(todayString): \(consumedMinutes) min, weekStartDate: \(weekStartDateString)")
                }
            } catch {
                NSLog("SYNC UsageSyncManager: ❌ Failed to encode entry: \(error)")
            }
        }
    }
    
    // MARK: - Automatic Sync Trigger
    
    /// Update daily usage and sync to backend
    /// This should be called on app foreground, after commitment creation, etc.
    func updateAndSync() async {
        NSLog("SYNC UsageSyncManager: 🔄 updateAndSync() called at \(Date())")
        
        // First, update daily usage entries from consumedMinutes
        NSLog("SYNC UsageSyncManager: 📝 Step 1: Updating daily usage entries from consumedMinutes...")
        updateDailyUsageFromConsumedMinutes()
        NSLog("SYNC UsageSyncManager: ✅ Step 1 complete: Daily usage entries updated")
        
        // Then, sync to backend
        NSLog("SYNC UsageSyncManager: 📤 Step 2: Syncing to backend...")
        do {
            try await syncToBackend()
            NSLog("SYNC UsageSyncManager: ✅ Update and sync completed successfully")
        } catch {
            NSLog("SYNC UsageSyncManager: ❌ Update and sync failed: \(error)")
            if let nsError = error as NSError? {
                NSLog("SYNC UsageSyncManager: ❌ Error details - domain: \(nsError.domain), code: \(nsError.code), description: \(nsError.localizedDescription)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get count of unsynced entries (for UI display)
    func getUnsyncedCount() -> Int {
        return getUnsyncedUsage().count
    }
    
    /// Check if there are any unsynced entries
    func hasUnsyncedEntries() -> Bool {
        return !getUnsyncedUsage().isEmpty
    }
}

