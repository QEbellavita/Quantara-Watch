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

    // MARK: - Send to Quantara Backend
    func syncToQuantaraBackend() {
        let biometricData: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "heartRate": heartRate,
            "hrv": hrv,
            "activeEnergy": activeEnergy,
            "steps": steps,
            "exerciseMinutes": exerciseMinutes,
            "minHeartRate": minHeartRate,
            "maxHeartRate": maxHeartRate,
            "avgHeartRate": avgHeartRate
        ]

        // TODO: Send to Quantara Neural Ecosystem API
        // POST to: https://your-quantara-api.railway.app/api/biometrics/sync
        print("Syncing to Quantara: \(biometricData)")
    }

    deinit {
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
    }
}
