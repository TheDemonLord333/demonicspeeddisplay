//
//  SpeedValidator.swift
//  Demonic Speed Display
//
//  Entscheidet, ob ein GPS-Wert als aktuelle Geschwindigkeit angezeigt werden darf.
//

import Foundation

nonisolated enum SpeedReading: Equatable, Sendable {
    /// Gültige, aktuelle Geschwindigkeit in km/h.
    case valid(kmh: Double)
    /// Noch kein Messwert eingetroffen.
    case waiting
    /// Letzter Messwert ist zu alt (z. B. Tunnel, Empfangsabbruch).
    case stale
    /// Messwert vorhanden, aber zu ungenau oder ohne Geschwindigkeit.
    case inaccurate
}

nonisolated struct SpeedValidator: Sendable {
    /// Maximales Alter eines Messwerts in Sekunden.
    var maxAge: TimeInterval = 3
    /// Maximale Positionsunsicherheit in Metern.
    var maxHorizontalAccuracy: Double = 50
    /// Maximale Geschwindigkeitsunsicherheit in m/s (≈ 10 km/h).
    var maxSpeedAccuracy: Double = 2.8
    /// Plausibilitätsgrenze gegen Ausreißer (m/s, ≈ 350 km/h).
    var maxPlausibleSpeed: Double = 97
    /// Unterhalb dieser Geschwindigkeit (km/h) wird 0 angezeigt, um Stillstands-Rauschen zu unterdrücken.
    var standstillThresholdKmh: Double = 2

    func evaluate(_ fix: LocationFix?, now: Date) -> SpeedReading {
        guard let fix else { return .waiting }
        let age = now.timeIntervalSince(fix.timestamp)
        // Zukunftswerte (Uhrensprung) ebenso verwerfen wie alte Werte.
        guard age <= maxAge, age >= -1 else { return .stale }
        guard fix.coordinate.isValid,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= maxHorizontalAccuracy else {
            return .inaccurate
        }
        guard fix.speed >= 0, fix.speed.isFinite, fix.speed <= maxPlausibleSpeed else { return .inaccurate }
        guard fix.speedAccuracy >= 0, fix.speedAccuracy <= maxSpeedAccuracy else { return .inaccurate }
        let kmh = fix.speed * 3.6
        return .valid(kmh: kmh < standstillThresholdKmh ? 0 : kmh)
    }
}
