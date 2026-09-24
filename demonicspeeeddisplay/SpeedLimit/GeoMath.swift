//
//  GeoMath.swift
//  Demonic Speed Display
//
//  Plattformunabhängige Geometrie-Helfer (kein CoreLocation), damit Zuordnung
//  und Tests ohne Gerät laufen.
//

import Foundation

/// Geografische Koordinate in Grad (WGS84).
nonisolated struct GeoCoordinate: Equatable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

nonisolated enum GeoMath {
    static let earthRadius = 6_371_008.8

    /// Großkreisentfernung in Metern (Haversine).
    static func distance(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Verschiebt eine Koordinate um `meters` in Richtung `bearing` (Grad, 0 = Nord).
    static func offset(_ c: GeoCoordinate, meters: Double, bearing: Double) -> GeoCoordinate {
        let d = meters / earthRadius
        let brg = bearing * .pi / 180
        let lat1 = c.latitude * .pi / 180
        let lon1 = c.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brg))
        let lon2 = lon1 + atan2(sin(brg) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
        return GeoCoordinate(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    /// Kleinster Winkel zwischen zwei Richtungen in Grad (0...180).
    static func angleDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs((a - b).truncatingRemainder(dividingBy: 360))
        return d > 180 ? 360 - d : d
    }

    static func normalizedBearing(_ b: Double) -> Double {
        let r = b.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}

/// Lokale ebene Projektion um einen Bezugspunkt. Für Entfernungen von wenigen
/// Kilometern ist der Fehler vernachlässigbar (< 0,1 %).
nonisolated struct LocalProjection: Sendable {
    let origin: GeoCoordinate
    private let metersPerDegreeLat: Double
    private let metersPerDegreeLon: Double

    init(origin: GeoCoordinate) {
        self.origin = origin
        metersPerDegreeLat = GeoMath.earthRadius * .pi / 180
        metersPerDegreeLon = metersPerDegreeLat * cos(origin.latitude * .pi / 180)
    }

    /// x = Ost, y = Nord, in Metern.
    func project(_ c: GeoCoordinate) -> (x: Double, y: Double) {
        ((c.longitude - origin.longitude) * metersPerDegreeLon,
         (c.latitude - origin.latitude) * metersPerDegreeLat)
    }
}

nonisolated enum SegmentMath {
    /// Abstand und Richtung eines Punktes zu einem Segment in projizierten Koordinaten.
    /// `t` ist die Lage des Lotfußpunkts auf dem Segment (0 = Anfang, 1 = Ende).
    static func project(point p: (x: Double, y: Double),
                        from a: (x: Double, y: Double),
                        to b: (x: Double, y: Double)) -> (distance: Double, bearing: Double, t: Double)? {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.01 else { return nil } // doppelte Knoten ignorieren
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = min(1, max(0, t))
        let cx = a.x + t * dx
        let cy = a.y + t * dy
        let distance = hypot(p.x - cx, p.y - cy)
        let bearing = GeoMath.normalizedBearing(atan2(dx, dy) * 180 / .pi)
        return (distance, bearing, t)
    }
}
