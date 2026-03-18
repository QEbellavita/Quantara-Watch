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

            // Stress Insights (Neural Workflow AI Engine)
            StressInsightsView()
                .tag(1)

            // Heart Rate Live
            HeartRateLiveView()
                .tag(2)

            // HRV & Recovery
            HRVRecoveryView()
                .tag(3)

            // Activity Rings
            ActivityRingsView()
                .tag(4)

            // Breathing Exercise
            BreathingView()
                .tag(5)
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

                    // AI Stress Card (Neural Workflow Engine)
                    StressQuickCard()

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

// MARK: - Stress Quick Card (Dashboard)
struct StressQuickCard: View {
    @EnvironmentObject var healthManager: HealthKitManager

    var stressColor: Color {
        switch healthManager.stressLevel.lowercased() {
        case "low": return .green
        case "medium": return .yellow
        case "high": return .red
        default: return .gray
        }
    }

    var body: some View {
        HStack {
            // AI Brain Icon
            Image(systemName: "brain.head.profile")
                .font(.system(size: 18))
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Stress Level")
                    .font(.system(size: 8))
                    .foregroundColor(.gray)
                Text(healthManager.stressLevel == "unknown" ? "Analyzing..." : healthManager.stressLevel.capitalized)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(stressColor)
            }

            Spacer()

            // Mini stress ring
            ZStack {
                Circle()
                    .stroke(stressColor.opacity(0.2), lineWidth: 3)
                    .frame(width: 28, height: 28)

                Circle()
                    .trim(from: 0, to: healthManager.stressScore)
                    .stroke(stressColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 8))
                    .foregroundColor(stressColor)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(colors: [.purple.opacity(0.4), .cyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 0.5
                        )
                )
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

// MARK: - Stress Insights View (Neural Workflow AI Engine - Physiol_Rec)
struct StressInsightsView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @State private var pulseAnimation = false

    var stressColor: Color {
        switch healthManager.stressLevel.lowercased() {
        case "low": return .green
        case "medium": return .yellow
        case "high": return .red
        default: return .gray
        }
    }

    var emotionIcon: String {
        switch healthManager.emotionQuadrant.lowercased() {
        case "high arousal, positive valence": return "sun.max.fill"
        case "high arousal, negative valence": return "bolt.fill"
        case "low arousal, positive valence": return "leaf.fill"
        case "low arousal, negative valence": return "moon.zzz.fill"
        default: return "brain.head.profile"
        }
    }

    var emotionLabel: String {
        switch healthManager.emotionQuadrant.lowercased() {
        case "high arousal, positive valence": return "Energized"
        case "high arousal, negative valence": return "Stressed"
        case "low arousal, positive valence": return "Calm"
        case "low arousal, negative valence": return "Tired"
        default: return "Analyzing..."
        }
    }

    var body: some View {
        ZStack {
            // Neural-style gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.05, blue: 0.2),
                    Color(red: 0.05, green: 0.1, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 10) {
                    // Header
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 12))
                            .foregroundStyle(
                                LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing)
                            )
                        Text("AI Insights")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.gray)
                    }

                    // Main Stress Indicator
                    ZStack {
                        // Pulsing background
                        Circle()
                            .fill(stressColor.opacity(0.2))
                            .frame(width: 90, height: 90)
                            .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                value: pulseAnimation
                            )

                        // Stress ring
                        Circle()
                            .stroke(stressColor.opacity(0.3), lineWidth: 6)
                            .frame(width: 80, height: 80)

                        Circle()
                            .trim(from: 0, to: healthManager.stressScore)
                            .stroke(
                                LinearGradient(colors: [stressColor, stressColor.opacity(0.6)], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 2) {
                            Text(healthManager.stressLevel.capitalized)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(stressColor)
                            Text("Stress")
                                .font(.system(size: 8))
                                .foregroundColor(.gray)
                        }
                    }
                    .onAppear { pulseAnimation = true }

                    // Quick Stats Row
                    HStack(spacing: 8) {
                        // Emotion State
                        VStack(spacing: 4) {
                            Image(systemName: emotionIcon)
                                .font(.system(size: 16))
                                .foregroundStyle(
                                    LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom)
                                )
                            Text(emotionLabel)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white)
                            Text("Emotion")
                                .font(.system(size: 7))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.4))
                        )

                        // Activity State
                        VStack(spacing: 4) {
                            Image(systemName: activityIcon)
                                .font(.system(size: 16))
                                .foregroundStyle(
                                    LinearGradient(colors: [.green, .cyan], startPoint: .top, endPoint: .bottom)
                                )
                            Text(healthManager.activityState.capitalized)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white)
                            Text("Activity")
                                .font(.system(size: 7))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.4))
                        )
                    }

                    // HRV Health Card
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HRV Health")
                                .font(.system(size: 8))
                                .foregroundColor(.gray)
                            Text(healthManager.hrvHealthGrade)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(hrvHealthColor)
                        }

                        Spacer()

                        // Score indicator
                        ZStack {
                            Circle()
                                .stroke(hrvHealthColor.opacity(0.3), lineWidth: 3)
                                .frame(width: 32, height: 32)
                            Circle()
                                .trim(from: 0, to: healthManager.hrvHealthScore)
                                .stroke(hrvHealthColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 32, height: 32)
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 10))
                                .foregroundColor(hrvHealthColor)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(hrvHealthColor.opacity(0.3), lineWidth: 0.5)
                            )
                    )

                    // Neural Ecosystem ML API Card (12 Engines)
                    VStack(spacing: 6) {
                        HStack {
                            Image(systemName: "cpu.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(
                                    LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
                                )
                            Text("Neural ML API")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Circle()
                                .fill(healthManager.mlApiConnected ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                        }

                        HStack(spacing: 6) {
                            // Cognitive State (90.1% accuracy)
                            VStack(spacing: 2) {
                                Image(systemName: cognitiveIcon)
                                    .font(.system(size: 12))
                                    .foregroundColor(cognitiveColor)
                                Text(healthManager.cognitiveState.capitalized)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Focus")
                                    .font(.system(size: 6))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)

                            // Activity (97.9% accuracy)
                            VStack(spacing: 2) {
                                Image(systemName: mlActivityIcon)
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                                Text(healthManager.activityPrediction.capitalized)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Move")
                                    .font(.system(size: 6))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        LinearGradient(colors: [.cyan.opacity(0.5), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 0.5
                                    )
                            )
                    )

                    // Sync status
                    if let lastTime = healthManager.lastPredictionTime {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("Updated \(timeAgo(lastTime))")
                                .font(.system(size: 8))
                                .foregroundColor(.gray)
                        }
                    }

                    // Prediction source badge (on-device CoreML vs cloud)
                    HStack(spacing: 4) {
                        Image(systemName: healthManager.predictionSource == "on-device" ? "cpu" : "cloud")
                            .font(.system(size: 8))
                            .foregroundColor(healthManager.predictionSource == "on-device" ? .green : .cyan)
                        Text(healthManager.predictionSource == "on-device" ? "On-Device" : "Cloud")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundColor(healthManager.predictionSource == "on-device" ? .green : .cyan)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
    }

    var cognitiveIcon: String {
        switch healthManager.cognitiveState.lowercased() {
        case "focused": return "brain.fill"
        case "neutral": return "brain"
        case "relaxed": return "leaf.fill"
        default: return "brain.head.profile"
        }
    }

    var cognitiveColor: Color {
        switch healthManager.cognitiveState.lowercased() {
        case "focused": return .cyan
        case "neutral": return .gray
        case "relaxed": return .green
        default: return .purple
        }
    }

    var mlActivityIcon: String {
        switch healthManager.activityPrediction.lowercased() {
        case "walking": return "figure.walk"
        case "jogging": return "figure.run"
        case "stairs": return "figure.stairs"
        case "sitting": return "figure.seated.seatbelt"
        case "standing": return "figure.stand"
        default: return "figure.mixed.cardio"
        }
    }

    var activityIcon: String {
        switch healthManager.activityState.lowercased() {
        case "rest": return "bed.double.fill"
        case "light": return "figure.walk"
        case "moderate": return "figure.run"
        case "vigorous": return "flame.fill"
        default: return "figure.stand"
        }
    }

    var hrvHealthColor: Color {
        switch healthManager.hrvHealthGrade.lowercased() {
        case "excellent", "a": return .green
        case "good", "b": return .cyan
        case "moderate", "c": return .yellow
        case "low", "d", "f": return .orange
        default: return .gray
        }
    }

    func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
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
