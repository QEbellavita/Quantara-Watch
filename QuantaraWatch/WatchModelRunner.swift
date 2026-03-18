import Foundation
import CoreML

/// On-device CoreML inference actor for Apple Watch stress predictions
/// Part of the Neural Workflow AI Engine — provides local ML with cloud fallback
actor WatchModelRunner {

    // MARK: - Types

    struct StressPrediction {
        let level: String
        let score: Double
        let confidence: Double
        let source: String
    }

    struct ScalerConfig: Codable {
        let featureNames: [String]
        let mean: [Double]
        let std: [Double]
        let classNames: [String]

        enum CodingKeys: String, CodingKey {
            case featureNames = "feature_names"
            case mean
            case std
            case classNames = "class_names"
        }
    }

    // MARK: - Properties

    private var stressModel: MLModel?
    private var scaler: ScalerConfig?
    private var lastLoadTime: Date?
    private let idleTimeout: TimeInterval = 60
    private let modelConfig: MLModelConfiguration

    // MARK: - Feature names (must match trained sklearn model inputs)

    private let featureNames: [String] = [
        "heart_rate", "hrv_rmssd", "hrv_sdnn", "hrv_ratio",
        "eda_mean", "eda_peaks", "skin_temp", "respiration_rate",
        "steps", "sleep_minutes", "activity_level", "hour_of_day"
    ]

    // MARK: - Init

    init() {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        self.modelConfig = config
    }

    // MARK: - Model Loading

    /// Load the CoreML model and scaler config from the app bundle
    func ensureModelLoaded() -> Bool {
        if stressModel != nil && scaler != nil {
            lastLoadTime = Date()
            return true
        }

        // Load scaler JSON
        guard let scalerURL = Bundle.main.url(forResource: "biometric_stress_scaler", withExtension: "json"),
              let scalerData = try? Data(contentsOf: scalerURL),
              let loadedScaler = try? JSONDecoder().decode(ScalerConfig.self, from: scalerData) else {
            print("[WatchModelRunner] Failed to load scaler config")
            return false
        }
        self.scaler = loadedScaler

        // Scan for compiled CoreML model (biometric_stress_v*.mlmodelc)
        guard let resourcePath = Bundle.main.resourcePath else {
            print("[WatchModelRunner] No resource path found")
            return false
        }

        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: resourcePath) else {
            print("[WatchModelRunner] Failed to list resource directory")
            return false
        }

        let modelDir = contents.first { $0.hasPrefix("biometric_stress_v") && $0.hasSuffix(".mlmodelc") }
        guard let modelName = modelDir else {
            print("[WatchModelRunner] No biometric_stress model found in bundle")
            return false
        }

        let modelURL = URL(fileURLWithPath: resourcePath).appendingPathComponent(modelName)

        do {
            let compiledModel = try MLModel(contentsOf: modelURL, configuration: modelConfig)
            self.stressModel = compiledModel
            self.lastLoadTime = Date()
            print("[WatchModelRunner] Model loaded: \(modelName)")
            return true
        } catch {
            print("[WatchModelRunner] Failed to load model: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Prediction

    /// Run on-device stress prediction using CoreML
    /// - Returns: StressPrediction with level, score, confidence, and source "on-device"
    func predictStress(
        heartRate: Double,
        hrv: Double,
        skinTemp: Double,
        respirationRate: Double,
        steps: Double,
        sleepMinutes: Double,
        activityLevel: Double,
        hour: Double? = nil
    ) -> StressPrediction? {
        guard ensureModelLoaded(), let model = stressModel, let scaler = scaler else {
            print("[WatchModelRunner] Model not available for prediction")
            return nil
        }

        // Build 12-feature raw vector
        let currentHour = hour ?? Double(Calendar.current.component(.hour, from: Date()))
        let hrvRatio = hrv > 0 ? heartRate / hrv : 0.0

        let rawFeatures: [Double] = [
            heartRate,          // heart_rate
            hrv * 1.2,          // hrv_rmssd (estimated from SDNN)
            hrv,                // hrv_sdnn
            hrvRatio,           // hrv_ratio (HR / HRV)
            0.0,                // eda_mean (imputed — no EDA sensor on Watch)
            0.0,                // eda_peaks (imputed)
            skinTemp,           // skin_temp
            respirationRate,    // respiration_rate
            steps,              // steps
            sleepMinutes,       // sleep_minutes
            activityLevel,      // activity_level
            currentHour         // hour_of_day
        ]

        // Apply scaler normalization: (x - mean) / std
        var scaledFeatures: [Double] = []
        for i in 0..<rawFeatures.count {
            let mean = i < scaler.mean.count ? scaler.mean[i] : 0.0
            let std = i < scaler.std.count ? scaler.std[i] : 1.0
            let normalized = std != 0 ? (rawFeatures[i] - mean) / std : 0.0
            scaledFeatures.append(normalized)
        }

        // Build MLDictionaryFeatureProvider with named Double inputs
        // sklearn CoreML models expect individual named features, NOT MLMultiArray
        var featureDict: [String: MLFeatureValue] = [:]
        for i in 0..<featureNames.count {
            let value = i < scaledFeatures.count ? scaledFeatures[i] : 0.0
            featureDict[featureNames[i]] = MLFeatureValue(double: value)
        }

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let result = try model.prediction(from: provider)

            // Parse classLabel (String) output
            guard let classLabel = result.featureValue(for: "classLabel")?.stringValue else {
                print("[WatchModelRunner] No classLabel in model output")
                return nil
            }

            // Parse classProbability (Dictionary) output
            let probabilities = result.featureValue(for: "classProbability")?.dictionaryValue as? [String: Double] ?? [:]

            // Map class label to normalized stress level
            let level = classLabel.lowercased()
            let confidence = probabilities[classLabel] ?? 0.5

            // Map stress level to score (0.0 - 1.0)
            let score: Double
            switch level {
            case "high":
                score = 0.8 + (confidence * 0.2)
            case "medium":
                score = 0.4 + (confidence * 0.2)
            case "low":
                score = 0.1 + (confidence * 0.15)
            default:
                score = 0.5
            }

            lastLoadTime = Date()

            return StressPrediction(
                level: level,
                score: min(score, 1.0),
                confidence: confidence,
                source: "on-device"
            )

        } catch {
            print("[WatchModelRunner] Prediction failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Memory Management

    /// Unload model from memory if idle longer than timeout (battery optimization)
    func unloadIfIdle() {
        guard let lastLoad = lastLoadTime else { return }

        if Date().timeIntervalSince(lastLoad) > idleTimeout {
            stressModel = nil
            scaler = nil
            lastLoadTime = nil
            print("[WatchModelRunner] Model unloaded (idle timeout)")
        }
    }
}
