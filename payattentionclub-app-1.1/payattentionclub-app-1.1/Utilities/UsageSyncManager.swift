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
        NSLog("SYNC SyncCoordinator: 📥 tryStartSync() called, entering continuation...")
        return await withCheckedContinuation { continuation in
            NSLog("SYNC SyncCoordinator: 📥 Continuation created, dispatching to queue...")
            queue.async { [weak self] in
                NSLog("SYNC SyncCoordinator: 📥 Queue block executing...")
                guard let self = self else {
                    NSLog("SYNC SyncCoordinator: ❌ Self is nil, rejecting")
                    continuation.resume(returning: false)
                    return
                }
                
                let isSyncing = self._isSyncing
                let now = Date().timeIntervalSince1970
                let timeSinceLastSync = now - self._lastSyncTimestamp
                
                NSLog("SYNC SyncCoordinator: 🔍 State check - isSyncing: \(isSyncing), timeSinceLastSync: \(Int(timeSinceLastSync))s, minInterval: \(Int(self.minSyncInterval))s")
                print("SYNC SyncCoordinator: 🔍 State check - isSyncing: \(isSyncing), timeSinceLastSync: \(Int(timeSinceLastSync))s, minInterval: \(Int(self.minSyncInterval))s")
                fflush(stdout)
                
                guard !isSyncing else {
                    NSLog("SYNC SyncCoordinator: ❌ Sync already in progress - REJECTING")
                    print("SYNC SyncCoordinator: ❌ Sync already in progress - REJECTING")
                    fflush(stdout)
                    continuation.resume(returning: false)
                    return
                }
                
                guard timeSinceLastSync >= self.minSyncInterval else {
                    NSLog("SYNC SyncCoordinator: ❌ Sync throttled (last sync was \(Int(timeSinceLastSync))s ago, need \(Int(self.minSyncInterval))s) - REJECTING")
                    print("SYNC SyncCoordinator: ❌ Sync throttled (last sync was \(Int(timeSinceLastSync))s ago, need \(Int(self.minSyncInterval))s) - REJECTING")
                    fflush(stdout)
                    continuation.resume(returning: false)
                    return
                }
                
                self._isSyncing = true
                self._lastSyncTimestamp = now
                NSLog("SYNC SyncCoordinator: ✅ Sync started - APPROVED (isSyncing set to true)")
                continuation.resume(returning: true)
            }
        }
    }
    
    func endSync() async {
        NSLog("SYNC SyncCoordinator: 🔚 endSync() called, entering continuation...")
        await withCheckedContinuation { continuation in
            NSLog("SYNC SyncCoordinator: 🔚 endSync() continuation created, dispatching to queue...")
            queue.async { [weak self] in
                NSLog("SYNC SyncCoordinator: 🔚 endSync() queue block executing...")
                guard let self = self else {
                    NSLog("SYNC SyncCoordinator: 🔚 Self is nil in endSync()")
                    continuation.resume()
                    return
                }
                let wasSyncing = self._isSyncing
                NSLog("SYNC SyncCoordinator: 🔚 Clearing isSyncing flag (was: \(wasSyncing))")
                self._isSyncing = false
                NSLog("SYNC SyncCoordinator: 🔚 isSyncing flag cleared (now: \(self._isSyncing))")
                continuation.resume()
            }
        }
        NSLog("SYNC SyncCoordinator: 🔚 endSync() completed")
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
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            SyncLogger.error("SYNC UsageSyncManager: ❌ Failed to access App Group '\(appGroupIdentifier)'")
            return []
        }
        
        SyncLogger.info("SYNC UsageSyncManager: ✅ Successfully accessed App Group '\(appGroupIdentifier)'")
        
        var unsyncedEntries: [DailyUsageEntry] = []
        
        // NOTE: dictionaryRepresentation() includes standard UserDefaults keys too
        // Filter out system keys and only look for App Group keys
        let allKeys = userDefaults.dictionaryRepresentation().keys
        
        // Filter to exclude system keys (these shouldn't be in App Group)
        let systemKeyPrefixes = ["Apple", "NS", "AK", "PK", "IN", "MSV", "Car", "TV", "Adding", "Hyphenates"]
        let appGroupKeys = allKeys.filter { key in
            !systemKeyPrefixes.contains { key.hasPrefix($0) }
        }
        
        SyncLogger.info("SYNC UsageSyncManager: Total keys: \(allKeys.count), After filtering system keys: \(appGroupKeys.count)")
        
        // Scan App Group keys for daily_usage_* pattern
        let dailyUsageKeys = appGroupKeys.filter { $0.hasPrefix("daily_usage_") }
        
        SyncLogger.info("SYNC UsageSyncManager: Scanning App Group - Total keys: \(allKeys.count), Daily usage keys: \(dailyUsageKeys.count)")
        
        // Debug: Show App Group keys (excluding system keys)
        if !appGroupKeys.isEmpty {
            SyncLogger.info("SYNC UsageSyncManager: App Group keys found: \(appGroupKeys.sorted().joined(separator: ", "))")
        } else {
            SyncLogger.error("SYNC UsageSyncManager: ⚠️ No App Group keys found (after filtering system keys)")
        }
        
        // Debug: Show all keys that might be related
        let relatedKeys = appGroupKeys.filter { 
            $0.contains("daily") || 
            $0.contains("usage") || 
            $0.contains("entry") ||
            $0.contains("sync")
        }
        if !relatedKeys.isEmpty {
            SyncLogger.info("SYNC UsageSyncManager: Related keys found: \(relatedKeys.sorted().joined(separator: ", "))")
        } else {
            SyncLogger.info("SYNC UsageSyncManager: ⚠️ No related keys found (daily/usage/entry/sync)")
        }
        
        // Debug: Show keys that start with common prefixes to see what's actually stored
        let datePrefixKeys = appGroupKeys.filter { key in
            // Check if key looks like a date-based key (YYYY-MM-DD pattern)
            key.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
        }
        if !datePrefixKeys.isEmpty {
            SyncLogger.info("SYNC UsageSyncManager: Date-pattern keys found: \(datePrefixKeys.sorted().joined(separator: ", "))")
        }
        
        if !dailyUsageKeys.isEmpty {
            SyncLogger.info("SYNC UsageSyncManager: Daily usage keys found: \(dailyUsageKeys.sorted().joined(separator: ", "))")
        }
        
        var totalEntries = 0
        var syncedEntries = 0
        
        for key in dailyUsageKeys.sorted() {
            SyncLogger.debug("SYNC UsageSyncManager: Processing key: \(key)")
            if let data = userDefaults.data(forKey: key) {
                SyncLogger.debug("SYNC UsageSyncManager: Key \(key) has data, size: \(data.count) bytes")
                do {
                    let entry = try JSONDecoder().decode(DailyUsageEntry.self, from: data)
                    totalEntries += 1
                    SyncLogger.info("SYNC UsageSyncManager: ✅ Decoded entry for \(entry.date) - synced: \(entry.synced), usedMinutes: \(entry.usedMinutes)")
                    if !entry.synced {
                        unsyncedEntries.append(entry)
                        SyncLogger.info("SYNC UsageSyncManager: 📋 Found unsynced entry for \(entry.date) - \(entry.usedMinutes) min")
                    } else {
                        syncedEntries += 1
                        SyncLogger.debug("SYNC UsageSyncManager: ✅ Entry for \(entry.date) already synced, skipping")
                    }
                } catch {
                    SyncLogger.error("SYNC UsageSyncManager: ❌ Failed to decode entry for key \(key): \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        SyncLogger.error("SYNC UsageSyncManager: Raw JSON data: \(jsonString.prefix(200))")
                    }
                }
            } else {
                SyncLogger.debug("SYNC UsageSyncManager: Key \(key) has no data")
            }
        }
        
        // Sort by date (oldest first) to sync in chronological order
        unsyncedEntries.sort { $0.date < $1.date }
        
        SyncLogger.info("SYNC UsageSyncManager: 📊 Total entries: \(totalEntries), Synced: \(syncedEntries), Unsynced: \(unsyncedEntries.count)")
        return unsyncedEntries
    }
    
    // MARK: - Sync to Backend
    
    /// Sync all unsynced daily usage entries to the backend
    /// Uploads entries in batches and marks them as synced after successful upload
    /// Prevents concurrent syncs and throttles sync frequency
    /// Uses serial queue for atomic check-and-set (async-safe)
    func syncToBackend() async throws {
        SyncLogger.info("SYNC UsageSyncManager: 📞 syncToBackend() called")
        
        // Use coordinator to atomically check and set sync flag (async-safe)
        // CRITICAL: This must be the FIRST thing we do - no other work before this
        NSLog("SYNC UsageSyncManager: 🔄 Calling syncCoordinator.tryStartSync()...")
        let canStart = await SyncCoordinator.shared.tryStartSync()
        NSLog("SYNC UsageSyncManager: 🔄 syncCoordinator returned: canStart=\(canStart)")
        
        guard canStart else {
            NSLog("SYNC UsageSyncManager: ⏸️ Sync already in progress or throttled, skipping")
            return
        }
        
        NSLog("SYNC UsageSyncManager: ✅ Got permission, proceeding with sync")
        
        // Always clear syncing flag when done (use async defer pattern)
        defer {
            NSLog("SYNC UsageSyncManager: 🔚 defer block executing, scheduling endSync()")
            Task { @MainActor in
                NSLog("SYNC UsageSyncManager: 🔚 Task executing, calling endSync()")
                await SyncCoordinator.shared.endSync()
                NSLog("SYNC UsageSyncManager: 🔚 endSync() completed in defer")
            }
        }
        
        // Check for unsynced entries
        let unsyncedEntries = getUnsyncedUsage()
        
        guard !unsyncedEntries.isEmpty else {
            NSLog("SYNC UsageSyncManager: ✅ No unsynced entries to sync")
            return
        }
        
        NSLog("SYNC UsageSyncManager: 🚀 Starting sync of \(unsyncedEntries.count) entries")
        
        do {
            // Sync all entries at once using batch method
            NSLog("SYNC UsageSyncManager: 📤 Calling backendClient.syncDailyUsage() with \(unsyncedEntries.count) entries")
            print("SYNC UsageSyncManager: 📤 Calling backendClient.syncDailyUsage() with \(unsyncedEntries.count) entries")
            fflush(stdout)
            let syncedDates = try await backendClient.syncDailyUsage(unsyncedEntries)
            NSLog("SYNC UsageSyncManager: 📥 Received \(syncedDates.count) synced dates from backend")
            print("SYNC UsageSyncManager: 📥 Received \(syncedDates.count) synced dates from backend")
            fflush(stdout)
            
            NSLog("SYNC UsageSyncManager: 📥 Received \(syncedDates.count) synced dates from backend")
            
            // Only mark as synced if we have successfully synced dates
            guard !syncedDates.isEmpty else {
                NSLog("SYNC UsageSyncManager: ⚠️ No dates were synced, skipping markAsSynced()")
                return
            }
            
            // Mark entries as synced after successful upload
            markAsSynced(dates: syncedDates)
            
            NSLog("SYNC UsageSyncManager: ✅ Successfully synced \(syncedDates.count) entries")
        } catch {
            NSLog("SYNC UsageSyncManager: ❌ Failed to sync entries: \(error)")
            throw error
        }
    }
    
    // MARK: - Mark as Synced
    
    /// Mark daily usage entries as synced in App Group
    /// Updates the `synced` flag to true for the specified dates
    /// Idempotent: skips entries that are already synced
    func markAsSynced(dates: [String]) {
        guard !dates.isEmpty else {
            NSLog("SYNC UsageSyncManager: ⚠️ markAsSynced() called with empty dates array")
            return
        }
        
        NSLog("SYNC UsageSyncManager: 📝 markAsSynced() called for \(dates.count) dates: \(dates.joined(separator: ", "))")
        
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
                
                // Mark as synced
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

