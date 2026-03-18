import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKObserverQuery?
    private var anchorQuery: HKAnchoredObjectQuery?

    // Published biometric data
    @Published var heartRate: Int = 0
    @Published var minHeartRate: Int = 0
    @Published var avgHeartRate: Int = 0
    @Published var maxHeartRate: Int = 0
    @Published var hrv: Double = 0.0
    @Published var activeEnergy: Double = 0.0
    @Published var steps: Int = 0
    @Published var exerciseMinutes: Int = 0
    @Published var isAuthorized: Bool = false

    // On-device CoreML inference (Neural Workflow AI Engine)
    private let modelRunner = WatchModelRunner()
    @Published var predictionSource: String = "cloud"

    // Physiol_Rec stress prediction (Neural Workflow AI Engine)
    @Published var stressLevel: String = "unknown"
    @Published var stressScore: Double = 0.0
    @Published var arousalLevel: String = "unknown"
    @Published var arousalScore: Double = 0.0
    @Published var activityState: String = "unknown"
    @Published var hrvHealthGrade: String = "unknown"
    @Published var hrvHealthScore: Double = 0.0
    @Published var emotionQuadrant: String = "unknown"
    @Published var lastPredictionTime: Date?

    // HR data buffer for Physiol_Rec prediction (10-second window)
    private var heartRateBuffer: [Double] = []
    private let hrBufferSize = 10  // 10 samples at ~1Hz

    // Data types we want to read
    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)!,
        HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
        HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    ]

    init() {
        checkAuthorizationStatus()
    }

    // MARK: - Authorization
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit not available on this device")
            return
        }

        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isAuthorized = true
                    self?.startMonitoring()
                    self?.fetchAllData()
                } else if let error = error {
                    print("HealthKit authorization failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func checkAuthorizationStatus() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let status = healthStore.authorizationStatus(for: heartRateType)

        DispatchQueue.main.async {
            self.isAuthorized = (status == .sharingAuthorized)
        }
    }

    // MARK: - Start Monitoring
    func startMonitoring() {
        startHeartRateMonitoring()
        startHRVMonitoring()

        // Start Physiol_Rec stress predictions after initial data fetch
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.startStressPredictions()
        }
    }

    private func startHeartRateMonitoring() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }

        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil {
                self?.fetchLatestHeartRate()
            }
            completionHandler()
        }

        healthStore.execute(query)
        heartRateQuery = query

        // Enable background delivery
        healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { success, error in
            if let error = error {
                print("Background delivery error: \(error.localizedDescription)")
            }
        }
    }

    private func startHRVMonitoring() {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }

        let query = HKObserverQuery(sampleType: hrvType, predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil {
                self?.fetchLatestHRV()
            }
            completionHandler()
        }

        healthStore.execute(query)
    }

    // MARK: - Fetch All Data
    func fetchAllData() {
        fetchLatestHeartRate()
        fetchHeartRateStats()
        fetchLatestHRV()
        fetchActiveEnergy()
        fetchSteps()
        fetchExerciseMinutes()
    }

    // MARK: - Heart Rate
    private func fetchLatestHeartRate() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            guard let sample = samples?.first as? HKQuantitySample else { return }

            let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
            let value = Int(sample.quantity.doubleValue(for: heartRateUnit))

            DispatchQueue.main.async {
                self?.heartRate = value
            }
        }

        healthStore.execute(query)
    }

    private func fetchHeartRateStats() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: [.discreteMin, .discreteMax, .discreteAverage]) { [weak self] _, statistics, error in
            guard let statistics = statistics else { return }

            let heartRateUnit = HKUnit.count().unitDivided(by: .minute())

            DispatchQueue.main.async {
                if let min = statistics.minimumQuantity() {
                    self?.minHeartRate = Int(min.doubleValue(for: heartRateUnit))
                }
                if let max = statistics.maximumQuantity() {
                    self?.maxHeartRate = Int(max.doubleValue(for: heartRateUnit))
                }
                if let avg = statistics.averageQuantity() {
                    self?.avgHeartRate = Int(avg.doubleValue(for: heartRateUnit))
                }
            }
        }

        healthStore.execute(query)
    }

    // MARK: - HRV
    private func fetchLatestHRV() {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrvType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            guard let sample = samples?.first as? HKQuantitySample else { return }

            let value = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))

            DispatchQueue.main.async {
                self?.hrv = value
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Active Energy
    private func fetchActiveEnergy() {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, statistics, error in
            guard let sum = statistics?.sumQuantity() else { return }

            let value = sum.doubleValue(for: HKUnit.kilocalorie())

            DispatchQueue.main.async {
                self?.activeEnergy = value
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Steps
    private func fetchSteps() {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, statistics, error in
            guard let sum = statistics?.sumQuantity() else { return }

            let value = Int(sum.doubleValue(for: HKUnit.count()))

            DispatchQueue.main.async {
                self?.steps = value
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Exercise Minutes
    private func fetchExerciseMinutes() {
        guard let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: exerciseType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, statistics, error in
            guard let sum = statistics?.sumQuantity() else { return }

            let value = Int(sum.doubleValue(for: HKUnit.minute()))

            DispatchQueue.main.async {
                self?.exerciseMinutes = value
            }
        }

        healthStore.execute(query)
    }

    // MARK: - API Configuration
    // Connect to Quantara Backend API (same as main app)
    private let apiBaseURL = "https://quantara-backend-production.up.railway.app"
    private let watchApiKey = "quantara-watch-device-key"

    // Neural Ecosystem ML API (12-engine predictions)
    private let mlApiURL = "https://quantara-ml-api-production.up.railway.app"

    @Published var lastSyncTime: Date?
    @Published var syncStatus: SyncStatus = .idle

    // Neural Ecosystem ML API predictions
    @Published var cognitiveState: String = "unknown"  // Relaxed/Neutral/Focused (90.1% accuracy)
    @Published var cognitiveConfidence: Double = 0.0
    @Published var sleepStage: String = "unknown"  // Wake/N1/N2/N3/REM (94.6% accuracy)
    @Published var sleepConfidence: Double = 0.0
    @Published var activityPrediction: String = "unknown"  // Walking/Jogging/Sitting/etc (97.9% accuracy)
    @Published var activityConfidence: Double = 0.0
    @Published var mlApiConnected: Bool = false
    @Published var lastMLPredictionTime: Date?

    enum SyncStatus {
        case idle, syncing, success, failed
    }

    // Device ID for user identification
    private var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: "quantara_device_id") {
            return id
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "quantara_device_id")
        return newId
    }

    // MARK: - Send to Quantara Backend
    func syncToQuantaraBackend() {
        guard syncStatus != .syncing else { return }

        DispatchQueue.main.async {
            self.syncStatus = .syncing
        }

        let biometricData: [String: Any] = [
            "device_id": deviceId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "heart_rate": heartRate,
            "hrv": hrv,
            "active_energy": activeEnergy,
            "steps": steps,
            "exercise_minutes": exerciseMinutes,
            "min_heart_rate": minHeartRate,
            "max_heart_rate": maxHeartRate,
            "avg_heart_rate": avgHeartRate,
            "wellness_score": calculateWellnessScore(),
            // Physiol_Rec stress predictions (Neural Workflow AI Engine)
            "stress_level": stressLevel,
            "stress_score": stressScore,
            "arousal_level": arousalLevel,
            "arousal_score": arousalScore,
            "activity_state": activityState,
            "hrv_health_grade": hrvHealthGrade,
            "hrv_health_score": hrvHealthScore,
            "emotion_quadrant": emotionQuadrant
        ]

        guard let url = URL(string: "\(apiBaseURL)/api/watch/sync") else {
            DispatchQueue.main.async { self.syncStatus = .failed }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(watchApiKey, forHTTPHeaderField: "X-Watch-API-Key")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: biometricData)
        } catch {
            print("Failed to serialize data: \(error)")
            DispatchQueue.main.async { self.syncStatus = .failed }
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Sync failed: \(error.localizedDescription)")
                    self?.syncStatus = .failed
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self?.syncStatus = .success
                    self?.lastSyncTime = Date()
                    print("Successfully synced to Quantara backend")
                } else {
                    self?.syncStatus = .failed
                }
            }
        }.resume()
    }

    // Auto-sync every 5 minutes
    func startAutoSync() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetchAllData()
            self?.syncToQuantaraBackend()
        }
    }

    // Calculate wellness score
    private func calculateWellnessScore() -> Int {
        var score = 50
        if hrv > 40 { score += 15 }
        if hrv > 60 { score += 10 }
        if steps > 5000 { score += 10 }
        if steps > 10000 { score += 10 }
        if heartRate > 50 && heartRate < 100 { score += 5 }
        return min(score, 100)
    }

    // Sync breathing session
    func syncBreathingSession(duration: Int, preHeartRate: Int, postHeartRate: Int) {
        let sessionData: [String: Any] = [
            "device_id": deviceId,
            "duration_seconds": duration,
            "pre_heart_rate": preHeartRate,
            "post_heart_rate": postHeartRate
        ]

        guard let url = URL(string: "\(apiBaseURL)/api/watch/breathing") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(watchApiKey, forHTTPHeaderField: "X-Watch-API-Key")
        request.httpBody = try? JSONSerialization.data(withJSONObject: sessionData)

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    // MARK: - Physiol_Rec Stress Prediction (Neural Workflow AI Engine)

    // Fetch recent HR samples for prediction buffer
    func fetchHeartRateArray(completion: @escaping ([Double]) -> Void) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion([])
            return
        }

        let now = Date()
        let tenSecondsAgo = Calendar.current.date(byAdding: .second, value: -60, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: tenSecondsAgo, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: hrBufferSize,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                completion([])
                return
            }

            let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
            let hrValues = samples.map { $0.quantity.doubleValue(for: heartRateUnit) }
            completion(hrValues)
        }

        healthStore.execute(query)
    }

    // Get stress prediction from Physiol_Rec ML pipeline
    func getStressPrediction() {
        fetchHeartRateArray { [weak self] hrArray in
            guard let self = self, hrArray.count >= 5 else {
                print("[Physiol] Not enough HR data for prediction (need 5+, got \(hrArray.count))")
                return
            }

            // Prepare biometric payload for Physiol_Rec API
            // Apple Watch provides HR - we'll use synthetic values for other sensors
            let biometricData: [String: Any] = [
                "hr_data": hrArray,
                "gsr_data": self.generateBaselineGSR(count: 250),  // Synthetic baseline
                "acc_x": self.generateAccelerometerData(axis: "x", count: 250),
                "acc_y": self.generateAccelerometerData(axis: "y", count: 250),
                "acc_z": self.generateAccelerometerData(axis: "z", count: 250),
                "ppg_data": hrArray.map { $0 + Double.random(in: -5...5) },  // Derived from HR
                "userId": self.deviceId,
                "source": "apple_watch",
                "hrv_sdnn": self.hrv
            ]

            self.callPhysiolPredictAPI(data: biometricData)
        }
    }

    /// On-device CoreML stress prediction with cloud fallback
    /// Uses WatchModelRunner actor for local inference (Neural Workflow AI Engine)
    func getLocalStressPrediction() {
        Task {
            let prediction = await modelRunner.predictStress(
                heartRate: Double(heartRate),
                hrv: hrv,
                skinTemp: 33.5,
                respirationRate: 16.0,
                steps: Double(steps),
                sleepMinutes: 0,
                activityLevel: exerciseMinutes > 0 ? 0.7 : 0.3
            )

            await MainActor.run {
                if let prediction = prediction {
                    self.stressLevel = prediction.level
                    self.stressScore = prediction.score
                    self.predictionSource = prediction.source
                    self.lastPredictionTime = Date()
                    print("[Watch] Local prediction: \(prediction.level) (conf: \(prediction.confidence))")
                    // Update Watch complication with stress data
                    let stressInt = prediction.level == "high" ? 3 : (prediction.level == "medium" ? 2 : 1)
                    ComplicationController.updateComplicationData(
                        stress: stressInt,
                        mood: self.emotionQuadrant,
                        hrv: Int(self.hrv)
                    )
                } else {
                    self.getStressPrediction()
                    self.predictionSource = "cloud"
                }
            }
        }
    }

    private func callPhysiolPredictAPI(data: [String: Any]) {
        guard let url = URL(string: "\(apiBaseURL)/api/physiol/predict") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: data)
        } catch {
            print("[Physiol] Failed to serialize data: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[Physiol] Prediction failed: \(error.localizedDescription)")
                    return
                }

                guard let data = data else { return }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let prediction = json["prediction"] as? [String: Any] {

                        // Parse stress
                        if let stress = prediction["stress"] as? [String: Any] {
                            self?.stressLevel = stress["level"] as? String ?? "unknown"
                            self?.stressScore = stress["score"] as? Double ?? 0.0
                        }

                        // Parse arousal
                        if let arousal = prediction["arousal"] as? [String: Any] {
                            self?.arousalLevel = arousal["level"] as? String ?? "unknown"
                            self?.arousalScore = arousal["score"] as? Double ?? 0.0
                        }

                        // Parse activity
                        if let activity = prediction["activity"] as? [String: Any] {
                            self?.activityState = activity["state"] as? String ?? "unknown"
                        }

                        // Parse HRV health
                        if let hrvHealth = prediction["hrvHealth"] as? [String: Any] {
                            self?.hrvHealthGrade = hrvHealth["grade"] as? String ?? "unknown"
                            self?.hrvHealthScore = hrvHealth["score"] as? Double ?? 0.0
                        }

                        // Parse emotion
                        if let emotion = prediction["emotion"] as? [String: Any] {
                            self?.emotionQuadrant = emotion["quadrant"] as? String ?? "unknown"
                        }

                        self?.lastPredictionTime = Date()
                        print("[Physiol] Prediction: \(self?.stressLevel ?? "?") stress, \(self?.activityState ?? "?") activity")
                    }
                } catch {
                    print("[Physiol] Failed to parse response: \(error)")
                }
            }
        }.resume()
    }

    // Generate baseline GSR data (synthetic when not available)
    private func generateBaselineGSR(count: Int) -> [Double] {
        // Use HRV to estimate baseline arousal
        let baselineGSR = hrv > 50 ? 2.0 : 3.5  // Lower HRV = higher stress = higher GSR
        return (0..<count).map { _ in baselineGSR + Double.random(in: -0.3...0.3) }
    }

    // Generate accelerometer data based on activity level
    private func generateAccelerometerData(axis: String, count: Int) -> [Double] {
        let isActive = exerciseMinutes > 0 || steps > 1000
        switch axis {
        case "x": return (0..<count).map { _ in (isActive ? 0.5 : 0.1) + Double.random(in: -0.2...0.2) }
        case "y": return (0..<count).map { _ in (isActive ? 0.3 : 0.0) + Double.random(in: -0.15...0.15) }
        case "z": return (0..<count).map { _ in 9.8 + Double.random(in: -0.1...0.1) }  // Gravity
        default: return (0..<count).map { _ in Double.random(in: -0.1...0.1) }
        }
    }

    // Start periodic stress predictions (every 30 seconds)
    func startStressPredictions() {
        // Initial prediction — use on-device CoreML with cloud fallback
        getLocalStressPrediction()

        // Start Neural Ecosystem ML API predictions
        getMLAPIPredictions()

        // Periodic predictions every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.getLocalStressPrediction()
            self?.getMLAPIPredictions()
        }
    }

    // MARK: - Neural Ecosystem ML API (12 Engines)
    // https://quantara-ml-api-production.up.railway.app

    /// Get all ML predictions from Neural Ecosystem API
    func getMLAPIPredictions() {
        // Run predictions in parallel
        getCognitivePrediction()
        getBiometricStressPrediction()
        getActivityPrediction()
    }

    /// Check ML API connection status
    func checkMLAPIConnection() {
        guard let url = URL(string: "\(mlApiURL)/health") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self?.mlApiConnected = true
                    print("[ML API] Connected to Neural Ecosystem")
                } else {
                    self?.mlApiConnected = false
                }
            }
        }.resume()
    }

    /// Cognitive State Prediction (BCI Mental State Classifier - 90.1% accuracy)
    /// Classes: Relaxed, Neutral, Focused
    func getCognitivePrediction() {
        // Generate EEG-like features from available biometrics
        let features = generateCognitiveFeatures()

        let payload: [String: Any] = ["features": features]

        callMLAPI(endpoint: "/predict/cognitive", payload: payload) { [weak self] result in
            if let prediction = result["prediction"] as? String {
                self?.cognitiveState = prediction
            }
            if let confidence = result["confidence"] as? Double {
                self?.cognitiveConfidence = confidence
            }
            if let cogState = result["cognitive_state"] as? [String: Any] {
                if let state = cogState["state"] as? String {
                    self?.cognitiveState = state
                }
            }
            self?.lastMLPredictionTime = Date()
            print("[ML API] Cognitive: \(self?.cognitiveState ?? "?") (\(String(format: "%.1f", (self?.cognitiveConfidence ?? 0) * 100))%)")
        }
    }

    /// Biometric Stress Prediction (Multi-model ensemble)
    func getBiometricStressPrediction() {
        let payload: [String: Any] = [
            "heart_rate": heartRate,
            "hrv": hrv,
            "steps": steps,
            "active_energy": activeEnergy
        ]

        callMLAPI(endpoint: "/predict/biometrics", payload: payload) { [weak self] result in
            if let prediction = result["prediction"] as? String {
                // Update stress level from ML API
                self?.stressLevel = prediction.lowercased()
            }
            if let confidence = result["confidence"] as? Double {
                self?.stressScore = confidence
            }
            if let stress = result["stress"] as? [String: Any],
               let level = stress["level"] as? String {
                self?.stressLevel = level
            }
        }
    }

    /// Activity Recognition (WISDM - 97.9% accuracy)
    /// Classes: Walking, Jogging, Stairs, Sitting, Standing
    func getActivityPrediction() {
        // Generate accelerometer-like features
        let features = generateActivityFeatures()

        let payload: [String: Any] = ["features": features]

        callMLAPI(endpoint: "/predict/activity", payload: payload) { [weak self] result in
            if let prediction = result["prediction"] as? String {
                self?.activityPrediction = prediction
            }
            if let confidence = result["confidence"] as? Double {
                self?.activityConfidence = confidence
            }
            if let activity = result["activity"] as? [String: Any],
               let name = activity["name"] as? String {
                self?.activityPrediction = name
            }
        }
    }

    /// Sleep Stage Prediction (94.6% accuracy) - for sleep tracking mode
    /// Classes: Wake, N1, N2, N3, REM
    func getSleepPrediction() {
        let features = generateSleepFeatures()

        let payload: [String: Any] = ["features": features]

        callMLAPI(endpoint: "/predict/sleep", payload: payload) { [weak self] result in
            if let prediction = result["prediction"] as? String {
                self?.sleepStage = prediction
            }
            if let confidence = result["confidence"] as? Double {
                self?.sleepConfidence = confidence
            }
            if let stage = result["sleep_stage"] as? [String: Any],
               let name = stage["name"] as? String {
                self?.sleepStage = name
            }
        }
    }

    /// Generic ML API call method
    private func callMLAPI(endpoint: String, payload: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        guard let url = URL(string: "\(mlApiURL)\(endpoint)") else {
            print("[ML API] Invalid URL: \(endpoint)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10  // 10 second timeout

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            print("[ML API] Failed to serialize payload: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[ML API] Request failed: \(error.localizedDescription)")
                    self?.mlApiConnected = false
                    return
                }

                guard let data = data else { return }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self?.mlApiConnected = true
                        completion(json)
                    }
                } catch {
                    print("[ML API] Failed to parse response: \(error)")
                }
            }
        }.resume()
    }

    // MARK: - Feature Generation for ML API

    /// Generate cognitive features from biometrics (estimates EEG-like patterns)
    private func generateCognitiveFeatures() -> [Double] {
        // Use HRV and HR to estimate cognitive state
        // Low HRV + High HR = likely stressed/focused
        // High HRV + Normal HR = likely relaxed
        let baseFeatures = [
            Double(heartRate),
            hrv,
            Double(steps) / 1000.0,
            activeEnergy / 100.0,
            Double(exerciseMinutes),
            // HRV-derived features
            hrv > 50 ? 1.0 : 0.0,  // Good HRV indicator
            Double(heartRate - avgHeartRate),  // HR deviation
            hrv / 100.0,  // Normalized HRV
        ]

        // Pad to expected feature count (model expects variable input)
        var features = baseFeatures
        while features.count < 100 {
            features.append(Double.random(in: -0.1...0.1))
        }
        return features
    }

    /// Generate activity features from step/energy data
    private func generateActivityFeatures() -> [Double] {
        let isActive = exerciseMinutes > 0 || steps > 1000
        let intensity = isActive ? 1.0 : 0.0

        // Simulate accelerometer patterns based on activity
        var features: [Double] = []

        // Basic motion features
        features.append(Double(steps) / 10000.0)  // Normalized steps
        features.append(activeEnergy / 500.0)  // Normalized energy
        features.append(Double(exerciseMinutes) / 60.0)  // Normalized exercise
        features.append(intensity)

        // Simulated accelerometer statistics
        for _ in 0..<24 {
            let magnitude = isActive ? 0.5 + Double.random(in: 0...0.5) : 0.1 + Double.random(in: 0...0.1)
            features.append(magnitude)
        }

        // Pad to expected 100 features
        while features.count < 100 {
            features.append(Double.random(in: -0.1...0.1))
        }

        return features
    }

    /// Generate sleep features from overnight biometrics
    private func generateSleepFeatures() -> [Double] {
        // Sleep stage estimation based on HR patterns
        // Deep sleep: Low HR, high HRV
        // REM: Variable HR, moderate HRV
        // Light sleep: Moderate HR
        // Wake: Higher HR

        var features: [Double] = []

        // HR-based features
        features.append(Double(heartRate))
        features.append(Double(minHeartRate))
        features.append(Double(avgHeartRate))
        features.append(hrv)

        // Sleep indicators
        let isLowHR = heartRate < 60
        let isHighHRV = hrv > 50
        features.append(isLowHR ? 1.0 : 0.0)
        features.append(isHighHRV ? 1.0 : 0.0)

        // Pad to 32 features (sleep model expectation)
        while features.count < 32 {
            features.append(Double.random(in: -0.1...0.1))
        }

        return features
    }

    deinit {
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
    }
}
