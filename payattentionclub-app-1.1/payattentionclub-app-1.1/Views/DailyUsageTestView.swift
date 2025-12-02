import SwiftUI

struct DailyUsageTestView: View {
    @EnvironmentObject var model: AppModel
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Daily Usage Debug")
                .font(.title2.bold())
            
            Text("Unsynced entries: \(UsageSyncManager.shared.getUnsyncedCount())")
                .font(.headline)
            
            Button("Sync Now") {
                Task {
                    try? await UsageSyncManager.shared.syncToBackend()
                }
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding()
    }
}

