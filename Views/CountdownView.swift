import SwiftUI
import Combine

struct CountdownView: View {
    @ObservedObject var model: AppModel
    @State private var countdown: String = "00:00:00:00"
    
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Text(countdown)
            .font(.system(size: 32, weight: .bold, design: .monospaced))
            .onReceive(timer) { _ in
                countdown = model.formatCountdown()
            }
            .onAppear {
                countdown = model.formatCountdown()
            }
    }
}

