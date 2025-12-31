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
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            SyncLogger.error("SYNC UsageSyncManager: ❌ Failed to access App Group '\(appGroupIdentifier)'")
            return []
        }
        
        var unsyncedEntries: [DailyUsageEntry] = []
        
        // NOTE: dictionaryRepresentation() includes standard UserDefaults keys too
        // Filter out system keys and only look for App Group keys
        let allKeys = userDefaults.dictionaryRepresentation().keys
        
        // Filter to exclude system keys (these shouldn't be in App Group)
        let systemKeyPrefixes = ["Apple", "NS", "AK", "PK", "IN", "MSV", "Car", "TV", "Adding", "Hyphenates"]
        let appGroupKeys = allKeys.filter { key in
            !systemKeyPrefixes.contains { key.hasPrefix($0) }
        }
        
        // Scan App Group keys for daily_usage_* pattern
        let dailyUsageKeys = appGroupKeys.filter { $0.hasPrefix("daily_usage_") }
        
        var totalEntries = 0
        var syncedEntries = 0
        
        for key in dailyUsageKeys.sorted() {
            if let data = userDefaults.data(forKey: key) {
                do {
                    let entry = try JSONDecoder().decode(DailyUsageEntry.self, from: data)
                    totalEntries += 1
                    if !entry.synced {
                        unsyncedEntries.append(entry)
                    } else {
                        syncedEntries += 1
                    }
                } catch {
                    // Log only errors
                    SyncLogger.error("SYNC UsageSyncManager: ❌ Failed to decode entry for key \(key): \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        SyncLogger.error("SYNC UsageSyncManager: Raw JSON data: \(jsonString.prefix(200))")
                    }
                }
            }
        }
        
        // Sort by date (oldest first) to sync in chronological order
        unsyncedEntries.sort { $0.date < $1.date }
        
        return unsyncedEntries
    }
    
    // MARK: - Sync to Backend
    
    /// Sync all unsynced daily usage entries to the backend
    /// Uploads entries in batches and marks them as synced after successful upload
    /// Prevents concurrent syncs and throttles sync frequency
    /// Uses serial queue for atomic check-and-set (async-safe)
    func syncToBackend() async throws {
        // Use coordinator to atomically check and set sync flag (async-safe)
        // CRITICAL: This must be the FIRST thing we do - no other work before this
        let canStart = await SyncCoordinator.shared.tryStartSync()
        
        guard canStart else {
            return
        }
        
        // Always clear syncing flag when done (use async defer pattern)
        defer {
            Task { @MainActor in
                await SyncCoordinator.shared.endSync()
            }
        }
        
        // Check for unsynced entries
        let unsyncedEntries = getUnsyncedUsage()
        
        guard !unsyncedEntries.isEmpty else {
            return
        }
        
        do {
            // Sync all entries at once using batch method
            let syncedDates = try await backendClient.syncDailyUsage(unsyncedEntries)
            
            // Only mark as synced if we have successfully synced dates
            guard !syncedDates.isEmpty else {
                #if DEBUG
                NSLog("SYNC UsageSyncManager: ⚠️ No dates were synced, skipping markAsSynced()")
                #endif
                return
            }
            
            // Mark entries as synced after successful upload
            markAsSynced(dates: syncedDates)
        } catch {
            // Log only errors
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

