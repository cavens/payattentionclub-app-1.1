import SwiftUI

struct LoadingView: View {
    @EnvironmentObject var model: AppModel
    
    var body: some View {
        VStack {
            Spacer()
            
            Text("Pay Attention Club")
                .font(.system(size: 36, weight: .bold))
                .padding()
            
            Spacer()
        }
        .onAppear {
            // Finish initialization after UI has rendered
            // This allows the logo to appear immediately
            NSLog("SYNC LoadingView: 🎬 onAppear called, calling finishInitialization()")
            print("SYNC LoadingView: 🎬 onAppear called, calling finishInitialization()")
            fflush(stdout)
            model.finishInitialization()
            NSLog("SYNC LoadingView: ✅ finishInitialization() call completed")
            print("SYNC LoadingView: ✅ finishInitialization() call completed")
            fflush(stdout)
        }
    }
}

