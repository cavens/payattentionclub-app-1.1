import SwiftUI
import FamilyControls

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAppPicker = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // Countdown
                    VStack(spacing: 8) {
                        Text("Next deadline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let countdownModel = model.countdownModel {
                            CountdownView(model: countdownModel)
                        } else {
                            Text("00:00:00:00")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, 20)
                    
                    // Time Limit Slider
                    VStack(alignment: .leading, spacing: 15) {
                        Text(formatDeadlineLabel())
                            .font(.headline)
                        
                        Text(formatTime(model.limitMinutes))
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Slider(
                            value: $model.limitMinutes,
                            in: 30...2520, // 30 minutes to 42 hours (in minutes)
                            step: 15
                        )
                        
                        HStack {
                            Text("30 min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("42 hours")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Testing button to set limit to 1 minute
                        Button(action: {
                            model.limitMinutes = 1.0
                        }) {
                            Text("Set to 1 min (testing)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Penalty Slider
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Penalty per minute over limit")
                            .font(.headline)
                        
                        Text("$\(model.penaltyPerMinute, specifier: "%.2f")")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Slider(value: $model.penaltyPerMinute, in: 0.01...5.00, step: 0.01)
                        
                        HStack {
                            Text("$0.01")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("$5.00")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // App Selector
                    Button(action: {
                        showAppPicker = true
                    }) {
                        Label("Select Apps to Limit (\(model.selectedApps.applicationTokens.count + model.selectedApps.categoryTokens.count))", systemImage: "app.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .familyActivityPicker(isPresented: $showAppPicker, selection: $model.selectedApps)
                    
                    // Commit Button
                    Button(action: {
                        model.savePersistedValues()
                        
                        // Start preparing thresholds asynchronously (non-blocking)
                        // This happens in background while user goes through ScreenTime access and authorization
                        if #available(iOS 16.0, *) {
                            Task {
                                await MonitoringManager.shared.prepareThresholds(
                                    selection: model.selectedApps,
                                    limitMinutes: Int(model.limitMinutes)
                                )
                            }
                        }
                        
                        model.navigate(.screenTimeAccess)
                    }) {
                        Text("Commit")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.pink)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func formatTime(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
    
    private func formatDeadlineLabel() -> String {
        let deadlineEST = nextMondayNoonEST()
        let localDeadline = deadlineEST // Date automatically converts to local timezone when formatted
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmm" // 24-hour format: 1400
        formatter.timeZone = TimeZone.current // Use device's local timezone
        
        let timeString = formatter.string(from: localDeadline)
        // Format as "1400h" (add 'h' at the end)
        let formattedTime = "\(timeString)h"
        
        return "Time limit till next Monday \(formattedTime)"
    }
}

