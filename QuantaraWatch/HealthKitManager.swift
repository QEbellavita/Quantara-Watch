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
    @Published var lastSyncTime: Date?
    @Published var syncStatus: SyncStatus = .idle

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
        // Initial prediction
        getStressPrediction()

        // Periodic predictions every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.getStressPrediction()
        }
    }

    deinit {
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
    }
}
