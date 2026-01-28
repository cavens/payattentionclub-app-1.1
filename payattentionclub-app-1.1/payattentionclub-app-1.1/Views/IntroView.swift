import SwiftUI

// MARK: - Intro Data Models
struct IntroStep {
    let stepNumber: Int
    let title: String
    let description: String
}

struct IntroContent {
    static let steps: [IntroStep] = [
        IntroStep(
            stepNumber: 1,
            title: "Step one",
            description: "Welcome to Pay Attention Club"
        ),
        IntroStep(
            stepNumber: 2,
            title: "Step two",
            description: "Set your weekly limits"
        ),
        IntroStep(
            stepNumber: 3,
            title: "Step three",
            description: "Track your usage"
        ),
        IntroStep(
            stepNumber: 4,
            title: "Step four",
            description: "Stay accountable"
        ),
        IntroStep(
            stepNumber: 5,
            title: "Step five",
            description: "Get started today"
        ),
        IntroStep(
            stepNumber: 6,
            title: "Step six",
            description: "Penalties go to non-profit."
        )
    ]
}

// MARK: - Progress Dots Component
struct ProgressDots: View {
    let totalSteps: Int
    let currentStep: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.primary : Color.primary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - SVG Path Animation Component
struct SVGPathAnimation: View {
    let circleImageName: String
    let sphereImageName: String
    let animationDuration: Double
    
    @State private var animationProgress: Double = 0
    @State private var startTime: Date?
    
    init(circleImageName: String = "circle", sphereImageName: String = "sphere", animationDuration: Double = 2.0) {
        self.circleImageName = circleImageName
        self.sphereImageName = sphereImageName
        self.animationDuration = animationDuration
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated text above circle
            AnimatedText()
                .padding(.bottom, 20)
            
            // Circle and sphere animation
            ZStack {
                // Circle SVG - 25% smaller (225x225 instead of 300x300)
                Image(circleImageName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 225, height: 225)
                
                // Sphere SVG that follows the circle path
                GeometryReader { geometry in
                    let centerX = geometry.size.width / 2
                    let centerY = geometry.size.height / 2
                    // Radius should be half the circle size, adjusted slightly to account for circle stroke width
                    // The circle SVG likely has a stroke, so we adjust the radius slightly inward
                    // to center the sphere on the stroke path center
                    let baseRadius = min(geometry.size.width, geometry.size.height) / 2
                    // Small adjustment to account for stroke width (typically 1-2px, so ~1pt adjustment)
                    let radius = baseRadius - 1.0
                    
                    // Calculate position on circle path
                    // Start at top (angle = -π/2), then rotate 360 degrees
                    let angle = -Double.pi / 2 + (animationProgress * 2 * Double.pi)
                    let x = centerX + radius * cos(angle)
                    let y = centerY + radius * sin(angle)
                    
                    // Sphere SVG - load from Assets.xcassets (same size)
                    Image(sphereImageName)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .position(x: x, y: y) // position centers the sphere at (x, y)
                }
                .frame(width: 225, height: 225)
            }
            .frame(width: 225, height: 225)
        }
        .onAppear {
            startTime = Date()
            startAnimation()
        }
        .onChange(of: animationProgress) { _ in
            // Trigger view update
        }
    }
    
    private func startAnimation() {
        // Reset to start
        animationProgress = 0
        startTime = Date()
        
        // Start the animation loop
        animateLoop()
    }
    
    private func animateLoop() {
        // Calculate elapsed time since start
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        
        // Calculate raw progress (0.0 to 1.0)
        let rawProgress = (elapsed.truncatingRemainder(dividingBy: animationDuration)) / animationDuration
        
        // Apply cubic ease-in-out curve
        // Standard formula: if t < 0.5: 4t³, else: 1 - (-2t + 2)³/2
        let easedProgress: Double
        if rawProgress < 0.5 {
            // Ease-in: 4 * t³
            easedProgress = 4 * pow(rawProgress, 3)
        } else {
            // Ease-out: 1 - (-2t + 2)³/2
            // When rawProgress = 0.5, this should give 0.5
            // When rawProgress = 1.0, this should give 1.0
            easedProgress = 1 - pow(-2 * rawProgress + 2, 3) / 2
        }
        
        animationProgress = easedProgress
        
        // Schedule next update (60 FPS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0/60.0) {
            self.animateLoop()
        }
    }
}

// MARK: - Animated Text Component (MONDAY/NOON EASTERN)
struct AnimatedText: View {
    @State private var showEachMonday: Bool = true
    @State private var animationTask: Task<Void, Never>?
    
    // Helper to get Roboto font or fallback to system font
    private func robotoFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if UIFont(name: "Roboto", size: size) != nil {
            return .custom("Roboto", size: size)
        } else if UIFont(name: "Roboto-Bold", size: size) != nil && weight == .bold {
            return .custom("Roboto-Bold", size: size)
        } else if UIFont(name: "Roboto-Medium", size: size) != nil && weight == .medium {
            return .custom("Roboto-Medium", size: size)
        } else {
            return .system(size: size, weight: weight, design: .default)
        }
    }
    
    var body: some View {
        ZStack {
            // "EACH MONDAY" text (all caps)
            Text("EACH MONDAY")
                .font(robotoFont(size: 24, weight: .regular)) // Regular, not bold
                .foregroundColor(.primary)
                .offset(y: showEachMonday ? 0 : -10)
                .opacity(showEachMonday ? 1 : 0)
                .blur(radius: showEachMonday ? 0 : 2)
            
            // "NOON EASTERN" text (all caps, with "NOON" underlined)
            HStack(spacing: 0) {
                Text("NOON")
                    .font(robotoFont(size: 24, weight: .regular)) // Regular, not bold
                    .foregroundColor(.primary)
                    .underline()
                Text(" EASTERN")
                    .font(robotoFont(size: 24, weight: .regular)) // Regular, not bold
                    .foregroundColor(.primary)
            }
            .offset(y: showEachMonday ? 10 : 0)
            .opacity(showEachMonday ? 0 : 1)
            .blur(radius: showEachMonday ? 2 : 0)
        }
        .frame(height: 50)
        .animation(.easeInOut(duration: 0.6), value: showEachMonday)
        .onAppear {
            startTextAnimation()
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }
    
    private func startTextAnimation() {
        animationTask = Task {
            while !Task.isCancelled {
                // Show "each Monday" for 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                
                showEachMonday = false
                
                // Show "noon Eastern" for 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                
                showEachMonday = true
            }
        }
    }
}


// MARK: - Horizontal Slider Animation Component (Step 2)
struct HorizontalSliderAnimation: View {
    @State private var animationProgress: Double = 0
    @State private var startTime: Date?
    
    let animationDuration: Double = 6.0 // Full cycle duration (slower)
    
    // Helper function for ease-in-out curve
    private func easeInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * pow(t, 3)
        } else {
            return 1 - pow(-2 * t + 2, 3) / 2
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let lineWidth = screenWidth * 0.7 // 70% of screen width
            let lineThickness: CGFloat = 4 // 2 points thicker (was 2, now 4)
            
            // Calculate position: -1 (left) to 1 (right), 0 is center
            // Animation in 3 equal steps with ease-in-out: left -> right -> center
            let position: Double = {
                if animationProgress < 0.333 {
                    // Step 1: Move left (0 to -1) with ease-in-out
                    let t = animationProgress / 0.333
                    let eased = easeInOut(t)
                    return -eased
                } else if animationProgress < 0.667 {
                    // Step 2: Move right (-1 to 1) with ease-in-out
                    let t = (animationProgress - 0.333) / 0.334
                    let eased = easeInOut(t)
                    return -1.0 + (eased * 2.0)
                } else {
                    // Step 3: Move back to center (1 to 0) with ease-in-out
                    let t = (animationProgress - 0.667) / 0.333
                    let eased = easeInOut(t)
                    return 1.0 - eased
                }
            }()
            
            // Calculate target hours based on position
            // Center (0): 21 hours, Left (-1): 11 hours, Right (1): 30 hours
            let currentHours: Int = {
                if position <= 0.0 {
                    // Left side: 21 to 11
                    return Int(21.0 + position * 10.0) // position goes from 0 to -1, so 21 + (-1 * 10) = 11
                } else {
                    // Right side: 21 to 30
                    return Int(21.0 + position * 9.0) // position goes from 0 to 1, so 21 + (1 * 9) = 30
                }
            }()
            
            ZStack {
                // Horizontal line - centered vertically in the middle of the screen
                Rectangle()
                    .fill(Color.black)
                    .frame(width: lineWidth, height: lineThickness)
                    .position(x: screenWidth / 2, y: screenHeight / 2 + 15) // Moved down 15 points
                
                // Sphere with text - moves along line
                // Center the sphere on the line (middle of sphere on middle of line)
                // Text is positioned above the sphere
                VStack(spacing: 8) {
                    // Hours text above sphere
                    Text("\(currentHours)H")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.black)
                        .monospacedDigit() // Smooth number transitions
                    
                    // Sphere element - center aligned with line
                    Image("sphere")
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
                .position(
                    x: screenWidth / 2 + CGFloat(position * Double(lineWidth / 2 - 20)),
                    y: screenHeight / 2 - 1 // Offset up so sphere center aligns with line center (adjusted for 15pt move)
                    // Text ~24pt + spacing 8pt + sphere center at 20pt = 52pt from VStack top
                    // VStack center is at ~36pt, so offset = 52 - 36 = 16pt upward
                )
            }
        }
        .onAppear {
            startTime = Date()
            startAnimation()
        }
    }
    
    private func startAnimation() {
        animationProgress = 0
        startTime = Date()
        animateLoop()
    }
    
    private func animateLoop() {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        
        // Loop the animation - no global easing, each step has its own ease-in-out
        let rawProgress = (elapsed.truncatingRemainder(dividingBy: animationDuration)) / animationDuration
        
        // Use raw progress directly - each step will apply its own ease-in-out
        animationProgress = rawProgress
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0/60.0) {
            self.animateLoop()
        }
    }
}

// MARK: - Horizontal Slider Animation Component for Penalty (Step 3)
struct HorizontalSliderPenaltyAnimation: View {
    @State private var animationProgress: Double = 0
    @State private var startTime: Date?
    
    let animationDuration: Double = 6.0 // Full cycle duration (same as step 2)
    
    // Helper function for ease-in-out curve
    private func easeInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * pow(t, 3)
        } else {
            return 1 - pow(-2 * t + 2, 3) / 2
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let lineWidth = screenWidth * 0.7 // 70% of screen width
            let lineThickness: CGFloat = 4 // Same thickness as step 2
            
            // Calculate position: -1 (left) to 1 (right), 0 is center
            // Animation in 3 equal steps with ease-in-out: left -> right -> center
            let position: Double = {
                if animationProgress < 0.333 {
                    // Step 1: Move left (0 to -1) with ease-in-out
                    let t = animationProgress / 0.333
                    let eased = easeInOut(t)
                    return -eased
                } else if animationProgress < 0.667 {
                    // Step 2: Move right (-1 to 1) with ease-in-out
                    let t = (animationProgress - 0.333) / 0.334
                    let eased = easeInOut(t)
                    return -1.0 + (eased * 2.0)
                } else {
                    // Step 3: Move back to center (1 to 0) with ease-in-out
                    let t = (animationProgress - 0.667) / 0.333
                    let eased = easeInOut(t)
                    return 1.0 - eased
                }
            }()
            
            // Calculate penalty amount based on position
            // Left (-1): $0.05, Right (1): $2.00, Center (0): $1.025 (middle value)
            let currentPenalty: Double = {
                if position <= 0.0 {
                    // Left side: $1.025 to $0.05
                    // position goes from 0 to -1
                    return 1.025 + position * 0.975 // 1.025 + (-1 * 0.975) = 0.05
                } else {
                    // Right side: $1.025 to $2.00
                    // position goes from 0 to 1
                    return 1.025 + position * 0.975 // 1.025 + (1 * 0.975) = 2.00
                }
            }()
            
            ZStack {
                // Horizontal line - centered vertically in the middle of the screen
                Rectangle()
                    .fill(Color.black)
                    .frame(width: lineWidth, height: lineThickness)
                    .position(x: screenWidth / 2, y: screenHeight / 2 + 15) // Moved down 15 points
                
                // Sphere with text - moves along line
                // Center the sphere on the line (middle of sphere on middle of line)
                // Same positioning as step 2
                VStack(spacing: 8) {
                    // Penalty text above sphere with dollar sign in front
                    Text(String(format: "$%.2f", currentPenalty))
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.black)
                        .monospacedDigit() // Smooth number transitions
                    
                    // Sphere element - center aligned with line
                    Image("sphere")
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
                .position(
                    x: screenWidth / 2 + CGFloat(position * Double(lineWidth / 2 - 20)),
                    y: screenHeight / 2 - 1 // Offset up so sphere center aligns with line center (adjusted for 15pt move) (same as step 2)
                )
            }
        }
        .onAppear {
            startTime = Date()
            startAnimation()
        }
    }
    
    private func startAnimation() {
        animationProgress = 0
        startTime = Date()
        animateLoop()
    }
    
    private func animateLoop() {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        
        // Loop the animation
        let rawProgress = (elapsed.truncatingRemainder(dividingBy: animationDuration)) / animationDuration
        
        // Use raw progress directly - each step will apply its own ease-in-out
        animationProgress = rawProgress
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0/60.0) {
            self.animateLoop()
        }
    }
}

// MARK: - App Selection Animation Component (Step 4)
struct AppSelectionAnimation: View {
    @State private var animationPhase: Int = 0 // 0: all stroke, 1: first filled, 2: first+third filled, 3: first empty, 4: all empty
    @State private var animationTask: Task<Void, Never>?
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            
            // Line width: 25% shorter than previous screens (70% * 0.75 = 52.5%)
            let lineWidth = screenWidth * 0.525
            let lineThickness: CGFloat = 4 // Same thickness as previous screens
            let sphereSize: CGFloat = 40 // Same size as previous screens
            let spacingBetweenSphereAndLine: CGFloat = 5 // 5 points between sphere and line
            let verticalSpacing: CGFloat = 55 // 55 points between rows
            
            // Calculate total width of sphere + spacing + line
            let totalWidth = sphereSize + spacingBetweenSphereAndLine + lineWidth
            
            // Center the entire group horizontally
            let centerX = screenWidth / 2
            // Middle element aligned with previous screens' line position (screenHeight / 2 + 15)
            let middleRowY = screenHeight / 2 + 15
            
            // Position of rows: middle row aligned with previous screens, others 55 points above and below
            // First row: 55 points above middle
            // Second row: at middle position (same as previous screens' line)
            // Third row: 55 points below middle
            let firstRowY = middleRowY - verticalSpacing
            let secondRowY = middleRowY
            let thirdRowY = middleRowY + verticalSpacing
            
            // Calculate left edge of the group to center it
            let groupLeftEdge = centerX - totalWidth / 2
            
            // Sphere position (left side)
            let sphereX = groupLeftEdge + sphereSize / 2
            
            // Line position (right side)
            let lineX = groupLeftEdge + sphereSize + spacingBetweenSphereAndLine + lineWidth / 2
            
            ZStack {
                // First row (top) - will be filled first, then empty first
                ZStack {
                    // Sphere with inner stroke only, then filled, then back to stroke
                    if animationPhase == 1 || animationPhase == 2 {
                        // Filled sphere (phases 1 and 2)
                        Image("sphere")
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                            .frame(width: sphereSize, height: sphereSize)
                            .position(x: sphereX, y: firstRowY)
                    } else {
                        // Inner stroke only (using strokeBorder for inner stroke)
                        Circle()
                            .strokeBorder(Color.black, lineWidth: lineThickness)
                            .frame(width: sphereSize, height: sphereSize)
                            .position(x: sphereX, y: firstRowY)
                    }
                    
                    // Line
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: lineWidth, height: lineThickness)
                        .position(x: lineX, y: firstRowY)
                }
                
                // Second row (middle) - always inner stroke only
                ZStack {
                    // Sphere with inner stroke only
                    Circle()
                        .strokeBorder(Color.black, lineWidth: lineThickness)
                        .frame(width: sphereSize, height: sphereSize)
                        .position(x: sphereX, y: secondRowY)
                    
                    // Line
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: lineWidth, height: lineThickness)
                        .position(x: lineX, y: secondRowY)
                }
                
                // Third row (bottom) - will be filled second, then empty second
                ZStack {
                    // Sphere with inner stroke only, then filled, then back to stroke
                    if animationPhase == 2 || animationPhase == 3 {
                        // Filled sphere (phases 2 and 3)
                        Image("sphere")
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                            .frame(width: sphereSize, height: sphereSize)
                            .position(x: sphereX, y: thirdRowY)
                    } else {
                        // Inner stroke only (using strokeBorder for inner stroke)
                        Circle()
                            .strokeBorder(Color.black, lineWidth: lineThickness)
                            .frame(width: sphereSize, height: sphereSize)
                            .position(x: sphereX, y: thirdRowY)
                    }
                    
                    // Line
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: lineWidth, height: lineThickness)
                        .position(x: lineX, y: thirdRowY)
                }
            }
            .onAppear {
                startAnimation()
            }
            .onDisappear {
                animationTask?.cancel()
            }
        }
    }
    
    private func startAnimation() {
        animationPhase = 0 // Start with all stroke only
        animationTask = Task {
            while !Task.isCancelled {
                // Phase 0: All stroke only (initial state)
                // Wait 0.5 seconds
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { break }
                
                // Phase 1: Fill first (top) sphere
                withAnimation(.easeInOut(duration: 0.3)) {
                    animationPhase = 1
                }
                
                // Wait a bit before filling the third
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { break }
                
                // Phase 2: Fill third (bottom) sphere
                withAnimation(.easeInOut(duration: 0.3)) {
                    animationPhase = 2
                }
                
                // Wait 1 second while both filled
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                
                // Phase 3: Empty first (top) sphere
                withAnimation(.easeInOut(duration: 0.3)) {
                    animationPhase = 3
                }
                
                // Wait a bit before emptying the third
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { break }
                
                // Phase 0: Empty third (bottom) sphere, back to all stroke
                withAnimation(.easeInOut(duration: 0.3)) {
                    animationPhase = 0
                }
                
                // Wait 0.5 seconds before repeating
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { break }
            }
        }
    }
}

// MARK: - Lock Animation Component (Step 5)
struct LockAnimation: View {
    @State private var lockOffset: CGFloat = -20 // Start 20 points higher
    @State private var animationTask: Task<Void, Never>?
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            
            // Center position
            let centerX = screenWidth / 2
            let centerY = screenHeight / 2
            
            // Rectangle size: 75x90 points (15 points wider than before)
            let rectangleWidth: CGFloat = 75
            let rectangleHeight: CGFloat = 90
            
            // Lock size - increased more to make stroke 2 points thicker
            let lockSize: CGFloat = 76
            
            // Position rectangle 15 points lower than center
            let rectangleY = centerY + 15
            
            // Base position: lock 25 points above the top of rectangle
            // Top of rectangle is at rectangleY - rectangleHeight/2
            // Top of lock should be 25 points above that
            let rectangleTopY = rectangleY - rectangleHeight / 2
            let baseLockTopY = rectangleTopY - 25
            let baseLockCenterY = baseLockTopY + lockSize / 2
            
            // Apply animation offset
            let lockCenterY = baseLockCenterY + lockOffset
            
            ZStack {
                // Black rectangle - drawn first so lock appears on top
                Rectangle()
                    .fill(Color.black)
                    .frame(width: rectangleWidth, height: rectangleHeight)
                    .position(x: centerX, y: rectangleY)
                
                // Lock image - positioned with animation offset
                Image("lock")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: lockSize, height: lockSize)
                    .position(x: centerX, y: lockCenterY)
            }
            .onAppear {
                startLockAnimation()
            }
            .onDisappear {
                animationTask?.cancel()
            }
        }
    }
    
    private func startLockAnimation() {
        animationTask = Task {
            while !Task.isCancelled {
                // Wait 1 second before dropping
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                
                // Drop down 20 points with bounce animation (10 points less than before)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)) {
                    lockOffset = 0 // 20 points higher -> 0 = 20 points drop
                }
                
                // Wait a bit, then reset to start position
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                
                // Reset to starting position (20 points higher)
                withAnimation(.easeInOut(duration: 0.3)) {
                    lockOffset = -20
                }
                
                // Small pause before repeating
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { break }
            }
        }
    }
}

// MARK: - Individual Intro Step Content View (only the content that changes)
struct IntroStepContentView: View {
    let step: IntroStep
    @State private var contentOpacity: Double = 0 // For fade-in animation on first screen
    
    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let screenWidth = geometry.size.width
            
            ZStack {
                // Animation - centered vertically in the middle of the iPhone (fixed position)
                // Each step can have its own animation component
                switch step.stepNumber {
                case 1:
                    HStack {
                        Spacer()
                        SVGPathAnimation(
                            circleImageName: "circle",
                            sphereImageName: "sphere",
                            animationDuration: 2.0
                        )
                        Spacer()
                    }
                    .position(x: screenWidth / 2, y: screenHeight / 2 + 15) // Moved down 15 points
                    .opacity(contentOpacity)
                case 2:
                    // Horizontal slider - centered in middle of screen
                    HorizontalSliderAnimation()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .position(x: screenWidth / 2, y: screenHeight / 2 + 15) // Moved down 15 points
                case 3:
                    // Horizontal slider for penalty amounts - centered in middle of screen
                    HorizontalSliderPenaltyAnimation()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .position(x: screenWidth / 2, y: screenHeight / 2 + 15) // Moved down 15 points
                case 4:
                    // Three rows of sphere + line, centered horizontally
                    AppSelectionAnimation()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .position(x: screenWidth / 2, y: screenHeight / 2 + 15) // Moved down 15 points
                case 5:
                    // Lock animation - centered in middle of screen
                    LockAnimation()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .position(x: screenWidth / 2, y: screenHeight / 2 + 15) // Moved down 15 points
                case 6:
                    // Center for Humane Technology logo - last intro screen
                    Image("CHT-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 0.6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .position(x: screenWidth / 2, y: screenHeight / 2 + 15)
                default:
                    HStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 225, height: 225)
                        Spacer()
                    }
                    .position(x: screenWidth / 2, y: screenHeight / 2 + 15) // Moved down 15 points
                }
                
                // Text element - positioned 50 points from top of iPhone screen (absolute position)
                let topText: String = {
                    switch step.stepNumber {
                    case 1:
                        return "Monday-to-Monday\nscreentime challenge"
                    case 2:
                        return "Set your weekly time limit"
                    case 3:
                        return "Set your penalty per extra minute"
                    case 4:
                        return "Select apps to limit"
                    case 5:
                        return "COMMIT!"
                    case 6:
                        return "Penalties go to non-profit."
                    default:
                        return step.description
                    }
                }()
                
                Text(topText)
                    .font(.headline)
                    .fontWeight(.regular)
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 60)
                    .frame(maxWidth: .infinity)
                    .position(x: screenWidth / 2, y: 65) // Absolute position: 65 points from top of screen (moved down 15 points)
                    .opacity(step.stepNumber == 1 ? contentOpacity : 1) // Fade-in only for first screen
            }
        }
        .onAppear {
            // Fade-in animation for first screen
            if step.stepNumber == 1 {
                withAnimation(.easeIn(duration: 0.6)) {
                    contentOpacity = 1
                }
            }
        }
        .onChange(of: step.stepNumber) { newStep in
            // Reset opacity when switching away from first screen
            if newStep != 1 {
                contentOpacity = 1
            } else if newStep == 1 && contentOpacity == 0 {
                // Fade in when returning to first screen
                withAnimation(.easeIn(duration: 0.6)) {
                    contentOpacity = 1
                }
            }
        }
    }
}

// MARK: - Main Intro View
struct IntroView: View {
    @EnvironmentObject var model: AppModel
    @State private var currentStepIndex: Int = 0
    
    private let pinkColor = Color(red: 226/255, green: 204/255, blue: 205/255)
    private let totalSteps = IntroContent.steps.count
    
    var body: some View {
        ZStack {
            // Pink background - covers entire screen including bottom
            pinkColor
                .ignoresSafeArea(.all)
            
            VStack(spacing: 0) {
                Spacer()
                
                // Content area that changes (TabView) - takes remaining space
                TabView(selection: $currentStepIndex) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        IntroStepContentView(step: IntroContent.steps[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                Spacer()
                
                       // Fixed bottom section: Progress dots, button, and skip button
                       VStack(spacing: 20) {
                           // Progress dots
                           ProgressDots(totalSteps: totalSteps, currentStep: currentStepIndex)
                           
                           // Button - styled like SetupView black buttons
                           Button(action: {
                               if currentStepIndex < totalSteps - 1 {
                                   withAnimation {
                                       currentStepIndex = currentStepIndex + 1
                                   }
                               } else {
                                   // Last step - complete intro
                                   model.completeIntro()
                               }
                           }) {
                               Text("Got it!")
                                   .font(.system(size: 18, weight: .semibold))
                                   .foregroundColor(.white)
                                   .frame(maxWidth: .infinity)
                                   .padding(.vertical, 16)
                                   .background(Color.black)
                                   .cornerRadius(12)
                           }
                           .padding(.horizontal, 40)
                           
                           // Skip button - moved to where step counter was
                           Button(action: {
                               model.completeIntro()
                           }) {
                               Text("Skip")
                                   .font(.system(size: 16, weight: .medium))
                                   .foregroundColor(.primary)
                                   .padding(.horizontal, 20)
                                   .padding(.vertical, 10)
                           }
                       }
                       .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
struct IntroView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock AppModel for preview
        let mockModel = AppModel()
        mockModel.hasSeenIntro = false
        
        return IntroView()
            .environmentObject(mockModel)
            .previewDisplayName("Intro View")
    }
}

struct SVGPathAnimation_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(red: 226/255, green: 204/255, blue: 205/255)
                .ignoresSafeArea()
            SVGPathAnimation()
        }
        .previewDisplayName("SVG Path Animation")
    }
}

struct IntroStepContentView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(red: 226/255, green: 204/255, blue: 205/255)
                .ignoresSafeArea()
            IntroStepContentView(step: IntroContent.steps[0])
        }
        .previewDisplayName("Intro Step Content 1")
    }
}
#endif
