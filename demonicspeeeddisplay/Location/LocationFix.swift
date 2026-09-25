//
//  LocationFix.swift
//  Demonic Speed Display
//
//  Eigener, plattformunabhängiger Messwert. Die Umwandlung aus CLLocation
//  passiert in LocationService, damit Validierung und Zuordnung testbar bleiben.
//

import Foundation

nonisolated struct LocationFix: Equatable, Sendable {
    var coordinate: GeoCoordinate
    /// Radius der Positionsunsicherheit in Metern; negativ = ungültig.
    var horizontalAccuracy: Double
    /// Geschwindigkeit in m/s; negativ = ungültig.
    var speed: Double
    /// Genauigkeit der Geschwindigkeit in m/s; negativ = ungültig.
    var speedAccuracy: Double
    /// Fahrtrichtung in Grad (0 = Nord); negativ = ungültig.
    var course: Double
    /// Genauigkeit der Fahrtrichtung in Grad; negativ = ungültig.
    var courseAccuracy: Double
    /// Zeitpunkt der Messung (nicht der Zustellung).
    var timestamp: Date
    /// Position stammt aus einer Software-Simulation (z. B. Xcode-Standortsimulation).
    var isSimulated: Bool = false

    /// Fahrtrichtung nur, wenn sie für die Straßenzuordnung belastbar ist.
    /// Unterhalb von ca. 10 km/h ist der GPS-Kurs zu unruhig.
    var reliableCourse: Double? {
        guard course >= 0, speed >= 2.8 else { return nil }
        guard courseAccuracy >= 0, courseAccuracy <= 35 else { return nil }
        return course
    }
}
