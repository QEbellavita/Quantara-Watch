import SwiftUI
import HealthKit

struct ContentView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Main Dashboard
            DashboardView()
                .tag(0)

            // Heart Rate Live
            HeartRateLiveView()
                .tag(1)

            // HRV & Recovery
            HRVRecoveryView()
                .tag(2)

            // Activity Rings
            ActivityRingsView()
                .tag(3)

            // Breathing Exercise
            BreathingView()
                .tag(4)
        }
        .tabViewStyle(.verticalPage)
        .onAppear {
            healthManager.requestAuthorization()
        }
    }
}

// MARK: - Main Dashboard
struct DashboardView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @State private var animateGradient = false

    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.05, green: 0.15, blue: 0.25)
                ],
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    animateGradient.toggle()
                }
            }

            ScrollView {
                VStack(spacing: 8) {
                    // Quantara Logo Header
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16))
                            .foregroundStyle(
                                LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing)
                            )
                        Text("QUANTARA")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
                            )
                    }
                    .padding(.top, 4)

                    // Heart Rate - Primary Metric
                    PrimaryMetricCard(
                        icon: "heart.fill",
                        value: "\(healthManager.heartRate)",
                        unit: "BPM",
                        label: "Heart Rate",
                        color: .red,
                        isAnimating: true
                    )

                    // Secondary Metrics Grid
                    HStack(spacing: 6) {
                        SmallMetricCard(
                            icon: "waveform.path.ecg",
                            value: String(format: "%.0f", healthManager.hrv),
                            label: "HRV",
                            color: .purple
                        )
                        SmallMetricCard(
                            icon: "flame.fill",
                            value: String(format: "%.0f", healthManager.activeEnergy),
                            label: "kcal",
                            color: .orange
                        )
                    }

                    HStack(spacing: 6) {
                        SmallMetricCard(
                            icon: "figure.walk",
                            value: formatNumber(healthManager.steps),
                            label: "Steps",
                            color: .green
                        )
                        SmallMetricCard(
                            icon: "bed.double.fill",
                            value: "\(healthManager.exerciseMinutes)",
                            label: "Active",
                            color: .cyan
                        )
                    }

                    // Wellness Score
                    WellnessScoreCard(score: calculateWellnessScore())
                }
                .padding(.horizontal, 4)
            }
        }
    }

    func formatNumber(_ num: Int) -> String {
        if num >= 1000 {
            return String(format: "%.1fk", Double(num) / 1000.0)
        }
        return "\(num)"
    }

    func calculateWellnessScore() -> Int {
        var score = 50
        if healthManager.hrv > 40 { score += 15 }
        if healthManager.hrv > 60 { score += 10 }
        if healthManager.steps > 5000 { score += 10 }
        if healthManager.steps > 10000 { score += 10 }
        if healthManager.heartRate > 50 && healthManager.heartRate < 100 { score += 5 }
        return min(score, 100)
    }
}

// MARK: - Primary Metric Card
struct PrimaryMetricCard: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    let color: Color
    let isAnimating: Bool

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                    .scaleEffect(pulse ? 1.2 : 1.0)
                    .animation(
                        isAnimating ?
                            Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) :
                            .default,
                        value: pulse
                    )
                    .onAppear { if isAnimating { pulse = true } }

                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(value)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text(unit)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(colors: [color.opacity(0.6), color.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Small Metric Card
struct SmallMetricCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Wellness Score Card
struct WellnessScoreCard: View {
    let score: Int

    var scoreColor: Color {
        if score >= 80 { return .green }
        if score >= 60 { return .yellow }
        return .orange
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wellness Score")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                Text("\(score)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor)
            }

            Spacer()

            // Mini progress ring
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 36, height: 36)

                Circle()
                    .trim(from: 0, to: Double(score) / 100.0)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundColor(scoreColor)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.3))
        )
    }
}

// MARK: - Heart Rate Live View
struct HeartRateLiveView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @State private var heartScale: CGFloat = 1.0

    var heartRateZone: (String, Color) {
        let hr = healthManager.heartRate
        if hr < 60 { return ("Resting", .blue) }
        if hr < 100 { return ("Normal", .green) }
        if hr < 140 { return ("Elevated", .yellow) }
        if hr < 170 { return ("High", .orange) }
        return ("Max", .red)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                // Animated Heart
                ZStack {
                    // Pulse rings
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(Color.red.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                            .frame(width: 60 + CGFloat(i * 20), height: 60 + CGFloat(i * 20))
                            .scaleEffect(heartScale)
                            .animation(
                                Animation.easeOut(duration: 1)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.2),
                                value: heartScale
                            )
                    }

                    Image(systemName: "heart.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.red)
                        .scaleEffect(heartScale)
                        .animation(
                            Animation.easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true),
                            value: heartScale
                        )
                }
                .onAppear { heartScale = 1.15 }

                // BPM Display
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(healthManager.heartRate)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("BPM")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }

                // Zone indicator
                Text(heartRateZone.0)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(heartRateZone.1)
                    )

                // Today's stats
                HStack(spacing: 20) {
                    VStack {
                        Text("\(healthManager.minHeartRate)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Min")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }

                    VStack {
                        Text("\(healthManager.avgHeartRate)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.green)
                        Text("Avg")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }

                    VStack {
                        Text("\(healthManager.maxHeartRate)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.red)
                        Text("Max")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - HRV Recovery View
struct HRVRecoveryView: View {
    @EnvironmentObject var healthManager: HealthKitManager

    var recoveryStatus: (String, String, Color) {
        let hrv = healthManager.hrv
        if hrv > 65 { return ("Excellent", "You're well recovered", .green) }
        if hrv > 50 { return ("Good", "Ready for activity", .cyan) }
        if hrv > 35 { return ("Moderate", "Consider light activity", .yellow) }
        return ("Low", "Rest recommended", .orange)
    }

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.purple.opacity(0.3), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Recovery Status")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)

                // HRV Ring
                ZStack {
                    Circle()
                        .stroke(Color.purple.opacity(0.2), lineWidth: 8)
                        .frame(width: 90, height: 90)

                    Circle()
                        .trim(from: 0, to: min(healthManager.hrv / 100.0, 1.0))
                        .stroke(
                            LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", healthManager.hrv))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("ms")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }

                // Status
                VStack(spacing: 4) {
                    Text(recoveryStatus.0)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(recoveryStatus.2)

                    Text(recoveryStatus.1)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }

                // Info
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text("Higher HRV = Better Recovery")
                        .font(.system(size: 9))
                }
                .foregroundColor(.gray.opacity(0.7))
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Activity Rings View
struct ActivityRingsView: View {
    @EnvironmentObject var healthManager: HealthKitManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                Text("Today's Activity")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)

                // Activity Rings
                ZStack {
                    // Move (Calories)
                    ActivityRing(
                        progress: min(healthManager.activeEnergy / 500.0, 1.0),
                        color: .red,
                        size: 100
                    )

                    // Exercise
                    ActivityRing(
                        progress: min(Double(healthManager.exerciseMinutes) / 30.0, 1.0),
                        color: .green,
                        size: 75
                    )

                    // Steps (as stand ring)
                    ActivityRing(
                        progress: min(Double(healthManager.steps) / 10000.0, 1.0),
                        color: .cyan,
                        size: 50
                    )
                }
                .frame(height: 110)

                // Legend
                VStack(spacing: 6) {
                    ActivityLegendRow(
                        color: .red,
                        icon: "flame.fill",
                        label: "Move",
                        value: "\(Int(healthManager.activeEnergy))/500 kcal"
                    )
                    ActivityLegendRow(
                        color: .green,
                        icon: "figure.run",
                        label: "Exercise",
                        value: "\(healthManager.exerciseMinutes)/30 min"
                    )
                    ActivityLegendRow(
                        color: .cyan,
                        icon: "figure.walk",
                        label: "Steps",
                        value: "\(healthManager.steps)/10k"
                    )
                }
            }
        }
    }
}

struct ActivityRing: View {
    let progress: Double
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 10)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

struct ActivityLegendRow: View {
    let color: Color
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)

            Spacer()

            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Breathing Exercise View
struct BreathingView: View {
    @State private var isBreathing = false
    @State private var breathPhase = "Tap to Start"
    @State private var circleScale: CGFloat = 0.6
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // Calm gradient
            RadialGradient(
                colors: [Color.cyan.opacity(0.3), Color.black],
                center: .center,
                startRadius: 0,
                endRadius: 150
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Breathe")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)

                // Breathing circle
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.cyan.opacity(0.6), .cyan.opacity(0.1)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 60
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(circleScale)

                    Circle()
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .scaleEffect(circleScale)

                    Text(breathPhase)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                }
                .onTapGesture {
                    toggleBreathing()
                }

                if isBreathing {
                    Text("Follow the circle")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                } else {
                    Text("1 min session")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    func toggleBreathing() {
        isBreathing.toggle()

        if isBreathing {
            startBreathingCycle()
        } else {
            timer?.invalidate()
            breathPhase = "Tap to Start"
            withAnimation(.easeInOut(duration: 0.5)) {
                circleScale = 0.6
            }
        }
    }

    func startBreathingCycle() {
        breathIn()
    }

    func breathIn() {
        guard isBreathing else { return }
        breathPhase = "Breathe In"
        withAnimation(.easeInOut(duration: 4)) {
            circleScale = 1.0
        }
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            breathOut()
        }
    }

    func breathOut() {
        guard isBreathing else { return }
        breathPhase = "Breathe Out"
        withAnimation(.easeInOut(duration: 4)) {
            circleScale = 0.6
        }
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            breathIn()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(HealthKitManager())
}
