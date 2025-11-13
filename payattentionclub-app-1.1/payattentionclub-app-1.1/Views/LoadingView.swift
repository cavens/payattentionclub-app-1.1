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
            model.finishInitialization()
        }
    }
}

