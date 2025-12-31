import SwiftUI
import Foundation
import FamilyControls

struct BulletinView: View {
    @EnvironmentObject var model: AppModel
    
    // Pink color constant: #E2CCCD
    private let pinkColor = Color(red: 226/255, green: 204/255, blue: 205/255)
    
    // Computed property for week penalty from backend
    private var weekPenaltyDollars: Double {
        if let weekStatus = model.weekStatus, weekStatus.userTotalPenaltyCents > 0 {
            // Use backend penalty if available and non-zero
            let penalty = Double(weekStatus.userTotalPenaltyCents) / 100.0
            NSLog("BULLETIN BulletinView: Using backend penalty: \(penalty) (from \(weekStatus.userTotalPenaltyCents) cents)")
            return penalty
        }
        // If backend penalty is 0 or not available, use calculated penalty from current usage
        // This handles cases where backend hasn't synced yet or penalty hasn't been calculated
        let calculatedPenalty = model.currentPenalty
        NSLog("BULLETIN BulletinView: Using calculated penalty: \(calculatedPenalty) (weekStatus: \(model.weekStatus != nil ? "available but 0" : "nil"), backend cents: \(model.weekStatus?.userTotalPenaltyCents ?? 0))")
        return calculatedPenalty
    }
    
    // Computed property for total minutes spent
    // Use currentUsageSeconds from monitor extension (most accurate)
    // This is updated from the DeviceActivityMonitor extension
    private var totalMinutesSpent: Int {
        // Use the usage data from monitor extension
        // This should be accurate as it comes from DeviceActivityMonitor
        return Int(Double(model.currentUsageSeconds) / 60.0)
    }
    
    var body: some View {
        GeometryReader { geometry in
                ZStack {
                    // Header absolutely positioned at top - fixed position
                    VStack(alignment: .leading, spacing: 0) {
                        PageHeader()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    // Rectangle absolutely positioned - 20 points below countdown (which is at bottom of 180px header)
                    VStack(spacing: 16) {
                        ZStack {
                            // White rectangle behind (empty, slid down 80 points)
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
                                            let progress = min(1.0, max(0.0, Double(totalMinutesSpent) / model.limitMinutes))
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.black)
                                                .frame(width: geometry.size.width * CGFloat(progress), height: 4)
                                        }
                                    }
                                    .frame(height: 4)
                                    
                                    // Labels below progress bar
                                    HStack {
                                        // Left: minutes spent
                                        Text("\(totalMinutesSpent) min spent")
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
                            .offset(y: 80) // Slide down 80 points
                            
                            // Black rectangle with week penalty (on top)
                            ContentCard {
                                VStack(spacing: 0) {
                                    VStack(alignment: .center, spacing: 12) {
                                        Text("Your week penalty")
                                            .font(.headline)
                                            .foregroundColor(pinkColor)
                                        
                                        Text("$\(weekPenaltyDollars, specifier: "%.2f")")
                                            .font(.system(size: 56, weight: .bold))
                                            .foregroundColor(pinkColor)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 120) // Double the height (same as authorization screen)
                            }
                        }
                        .frame(height: 210) // Extra height to accommodate offset white rectangle
                    }
                    .padding(.top, 220) // 180px (header height) + 40px spacing = 220px from top
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    // Text below white box (almost sticking to bottom of white box)
                    VStack(alignment: .center, spacing: 12) {
                        Text("The total weekly penalties will be used for activist anti-screentime campaigns.")
                            .font(.body)
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    .padding(.top, 280) // Position almost sticking to bottom of white box
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Commit Again Button at bottom
                    VStack {
                        Spacer()
                        Button(action: {
                            // Reset for new period
                            model.baselineUsageSeconds = 0
                            model.currentUsageSeconds = 0
                            model.currentPenalty = 0.0
                            model.savePersistedValues()
                            model.navigate(.setup)
                        }) {
                            Text("Commit Again")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.black)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true) // Hide navigation bar to avoid white stripes
            .background(Color(red: 226/255, green: 204/255, blue: 205/255))
            .scrollContentBackground(.hidden)
            .ignoresSafeArea()
            .withLogoutButton()
            .onAppear {
                // Update usage when view appears to show current values
                updateUsage()
                model.refreshWeekStatus()
            }
            .onChange(of: model.weekStatus) { newStatus in
                // Week status loaded - penalty should now be available from backend
                if let weekStatus = newStatus {
                    NSLog("BULLETIN BulletinView: Week status loaded - penalty: \(weekStatus.userTotalPenaltyCents) cents ($\(Double(weekStatus.userTotalPenaltyCents) / 100.0))")
                } else {
                    NSLog("BULLETIN BulletinView: Week status is nil")
                }
            }
            .onChange(of: model.weekStatus) { newStatus in
                // Week status loaded - penalty should now be available from backend
                if let weekStatus = newStatus {
                    NSLog("BULLETIN BulletinView: Week status loaded - penalty: \(weekStatus.userTotalPenaltyCents) cents")
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

