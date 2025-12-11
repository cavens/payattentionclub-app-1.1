import Foundation
import os.log

/// Simple synchronization using a serial queue and atomic operations
/// More reliable than actors for this use case
final class SyncCoordinator {
    static let shared = SyncCoordinator()
    
    private let queue = DispatchQueue(label: "com.payattentionclub.sync", qos: .userInitiated)
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
                self?._isSyncing = false
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
    
    private let appGroupIdentifier = "group.com.payattentionclub.app"
    private let backendClient = BackendClient.shared
    
    private init() {}
    
    // MARK: - Read Unsynced Usage
    
    /// Read all unsynced daily usage entries from App Group
    /// Returns entries sorted by date (oldest first)
    func getUnsyncedUsage() -> [DailyUsageEntry] {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            SyncLogger.error("SYNC: Failed to access App Group")
            #endif
            return []
        }
        
        var unsyncedEntries: [DailyUsageEntry] = []
        
        // Filter out system keys
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let systemKeyPrefixes = ["Apple", "NS", "AK", "PK", "IN", "MSV", "Car", "TV", "Adding", "Hyphenates"]
        let appGroupKeys = allKeys.filter { key in
            !systemKeyPrefixes.contains { key.hasPrefix($0) }
        }
        
        // Scan for daily_usage_* keys
        let dailyUsageKeys = appGroupKeys.filter { $0.hasPrefix("daily_usage_") }
        
        for key in dailyUsageKeys.sorted() {
            if let data = userDefaults.data(forKey: key) {
                do {
                    let entry = try JSONDecoder().decode(DailyUsageEntry.self, from: data)
                    if !entry.synced {
                        unsyncedEntries.append(entry)
                    }
                } catch {
                    #if DEBUG
                    SyncLogger.error("SYNC: Failed to decode entry for key \(key): \(error)")
                    #endif
                }
            }
        }
        
        // Sort by date (oldest first)
        unsyncedEntries.sort { $0.date < $1.date }
        
        #if DEBUG
        SyncLogger.info("SYNC: Found \(unsyncedEntries.count) unsynced entries")
        #endif
        
        return unsyncedEntries
    }
    
    // MARK: - Sync to Backend
    
    /// Sync all unsynced daily usage entries to the backend
    func syncToBackend() async throws {
        // Atomic check-and-set
        let canStart = await SyncCoordinator.shared.tryStartSync()
        guard canStart else { return }
        
        // Always clear syncing flag when done
        defer {
            Task { @MainActor in
                await SyncCoordinator.shared.endSync()
            }
        }
        
        let unsyncedEntries = getUnsyncedUsage()
        guard !unsyncedEntries.isEmpty else { return }
        
        #if DEBUG
        SyncLogger.info("SYNC: Starting sync of \(unsyncedEntries.count) entries")
        #endif
        
        do {
            let syncedDates = try await backendClient.syncDailyUsage(unsyncedEntries)
            
            guard !syncedDates.isEmpty else { return }
            
            markAsSynced(dates: syncedDates)
            
            #if DEBUG
            SyncLogger.info("SYNC: Successfully synced \(syncedDates.count) entries")
            #endif
        } catch {
            #if DEBUG
            SyncLogger.error("SYNC: Failed to sync: \(error)")
            #endif
            throw error
        }
    }
    
    // MARK: - Mark as Synced
    
    /// Mark daily usage entries as synced in App Group
    func markAsSynced(dates: [String]) {
        guard !dates.isEmpty else { return }
        
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        
        for date in dates {
            let key = "daily_usage_\(date)"
            
            guard let data = userDefaults.data(forKey: key) else { continue }
            
            do {
                let entry = try JSONDecoder().decode(DailyUsageEntry.self, from: data)
                
                // Skip if already synced
                if entry.synced { continue }
                
                // Mark as synced and store
                let updatedEntry = entry.markingAsSynced()
                let encoded = try JSONEncoder().encode(updatedEntry)
                userDefaults.set(encoded, forKey: key)
            } catch {
                #if DEBUG
                SyncLogger.error("SYNC: Failed to mark \(date) as synced: \(error)")
                #endif
            }
        }
        
        userDefaults.synchronize()
    }
    
    // MARK: - Helper Methods
    
    func getUnsyncedCount() -> Int {
        return getUnsyncedUsage().count
    }
    
    func hasUnsyncedEntries() -> Bool {
        return !getUnsyncedUsage().isEmpty
    }
}
