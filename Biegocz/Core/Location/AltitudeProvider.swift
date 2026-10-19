import CoreMotion
import Foundation

/// Relative altitude from the barometer, for elevation gain.
@MainActor
protocol AltitudeProvider: AnyObject {
    var isAvailable: Bool { get }
    /// Relative altitude in meters since the stream started.
    func relativeAltitudeUpdates() -> AsyncStream<Double>
}

@MainActor
final class BarometerAltitudeProvider: AltitudeProvider {
    private let altimeter = CMAltimeter()

    var isAvailable: Bool {
        CMAltimeter.isRelativeAltitudeAvailable() && CMAltimeter.authorizationStatus() != .denied
            && CMAltimeter.authorizationStatus() != .restricted
    }

    func relativeAltitudeUpdates() -> AsyncStream<Double> {
        AsyncStream { continuation in
            altimeter.startRelativeAltitudeUpdates(to: .main) { data, error in
                if let data {
                    continuation.yield(data.relativeAltitude.doubleValue)
                } else if error != nil {
                    // Denied or failed: no more readings; elevation keeps what it has.
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                Task { @MainActor [weak self] in
                    self?.altimeter.stopRelativeAltitudeUpdates()
                }
            }
        }
    }
}

/// Simulator and tests: no barometer, so elevation comes from GPS altitude.
@MainActor
final class NoAltitudeProvider: AltitudeProvider {
    var isAvailable: Bool { false }
    func relativeAltitudeUpdates() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
}
