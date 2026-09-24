//
//  LocationService.swift
//  Demonic Speed Display
//
//  Kapselt CLLocationManager. Liefert rohe Messwerte als `LocationFix`;
//  ob ein Wert angezeigt werden darf, entscheidet `SpeedValidator`.
//

import CoreLocation
import Foundation
import Observation

@Observable
final class LocationService {
    enum Authorization: Equatable {
        case notDetermined
        case denied
        case restricted
        case authorized
    }

    private(set) var authorization: Authorization = .notDetermined
    /// `false`, wenn der Nutzer nur den ungefähren Standort freigegeben hat –
    /// dann ist keine brauchbare Geschwindigkeit messbar.
    private(set) var isPreciseLocation = true

    /// Wird auf dem Main Actor für jeden eintreffenden Messwert aufgerufen.
    @ObservationIgnored var onFix: ((LocationFix) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var delegate: LocationDelegate?
    @ObservationIgnored private var wantsUpdates = false

    init() {
        let delegate = LocationDelegate(
            onAuthorization: { [weak self] status, accuracy in
                Task { @MainActor [weak self] in self?.apply(status: status, accuracy: accuracy) }
            },
            onFixes: { [weak self] fixes in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for fix in fixes { self.onFix?(fix) }
                }
            }
        )
        self.delegate = delegate
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        apply(status: manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        wantsUpdates = true
        if authorization == .authorized {
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        wantsUpdates = false
        manager.stopUpdatingLocation()
    }

    private func apply(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization) {
        switch status {
        case .notDetermined: authorization = .notDetermined
        case .restricted: authorization = .restricted
        case .denied: authorization = .denied
        case .authorizedAlways, .authorizedWhenInUse: authorization = .authorized
        @unknown default: authorization = .denied
        }
        isPreciseLocation = accuracy == .fullAccuracy
        if authorization == .authorized && wantsUpdates {
            manager.startUpdatingLocation()
        }
    }
}

/// Eigenes Delegate-Objekt, damit die Core-Location-Callbacks (nicht isoliert)
/// sauber vom Main-Actor-Zustand getrennt bleiben.
nonisolated private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    private let onAuthorization: @Sendable (CLAuthorizationStatus, CLAccuracyAuthorization) -> Void
    private let onFixes: @Sendable ([LocationFix]) -> Void

    init(onAuthorization: @escaping @Sendable (CLAuthorizationStatus, CLAccuracyAuthorization) -> Void,
         onFixes: @escaping @Sendable ([LocationFix]) -> Void) {
        self.onAuthorization = onAuthorization
        self.onFixes = onFixes
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorization(manager.authorizationStatus, manager.accuracyAuthorization)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        onFixes(locations.map(LocationFix.init(location:)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown ist vorübergehend; der Manager versucht es weiter.
        // Fehlende Werte werden über das Alter des letzten Messwerts erkannt
        // (SpeedValidator), eine verweigerte Freigabe über die Autorisierung.
    }
}

nonisolated extension LocationFix {
    init(location: CLLocation) {
        self.init(
            coordinate: GeoCoordinate(latitude: location.coordinate.latitude,
                                      longitude: location.coordinate.longitude),
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            speedAccuracy: location.speedAccuracy,
            course: location.course,
            courseAccuracy: location.courseAccuracy,
            timestamp: location.timestamp,
            isSimulated: location.sourceInformation?.isSimulatedBySoftware ?? false
        )
    }
}
