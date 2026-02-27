import SwiftUI
import HealthKit

@main
struct QuantaraWatchApp: App {
    @StateObject private var healthManager = HealthKitManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthManager)
        }
    }
}
