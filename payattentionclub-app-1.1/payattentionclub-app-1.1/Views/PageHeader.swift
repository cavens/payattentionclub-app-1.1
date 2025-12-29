import SwiftUI
import UIKit

// Fixed header component with logo and countdown - appears on every page (except loading)
// Positioned absolutely at the top with consistent spacing
struct PageHeader: View {
    @EnvironmentObject var model: AppModel
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Logo - fixed absolute position, centered horizontally
                if let uiImage = UIImage(named: "PayAttentionClubLogo") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: 115, height: 115)
                        .frame(maxWidth: .infinity) // Center horizontally
                        .padding(.top, geometry.safeAreaInsets.top + 50) // 5 times larger spacing at top - consistent across all pages
                } else {
                    Text("Logo not found")
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.top, geometry.safeAreaInsets.top + 50) // 5 times larger spacing at top - consistent across all pages
                }
                
                // Countdown - fixed position below logo, centered horizontally
                VStack(spacing: 8) {
                    if let countdownModel = model.countdownModel {
                        CountdownView(model: countdownModel)
                    } else {
                        Text("00:00:00:00")
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity) // Center horizontally
                .padding(.top, -15)
            }
        }
        .frame(height: 180) // Fixed height for header - consistent across all pages
    }
}

// Reusable black rectangle container - content and height can vary
struct ContentCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    
    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(Color.black)
            .cornerRadius(12)
            .padding(.horizontal)
    }
}

