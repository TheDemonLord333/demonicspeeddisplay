//
//  DemoDrive.swift
//  Demonic Speed Display
//
//  Künstliche Testwerte für den Simulator. Diese Werte laufen bewusst NICHT
//  durch LocationService oder die Tempolimit-Datenquelle und werden in der
//  Oberfläche immer als „DEMO“ gekennzeichnet.
//

import Foundation

nonisolated enum DemoLimitOption: Int, CaseIterable, Identifiable, Sendable {
    case kmh30 = 30
    case kmh50 = 50
    case kmh70 = 70
    case kmh100 = 100
    case kmh120 = 120
    case unlimited = -1
    case unknown = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .unlimited: return "Unbegrenzt"
        case .unknown: return "Unbekannt"
        default: return "\(rawValue) km/h"
        }
    }

    var status: SpeedLimitStatus {
        switch self {
        case .unlimited: return .known(SpeedLimit(value: .unlimited, roadName: "Demo-Autobahn"))
        case .unknown: return .unknown(.ambiguousRoad)
        default: return .known(SpeedLimit(value: .kmh(rawValue), roadName: "Demo-Straße"))
        }
    }
}

nonisolated struct DemoSample: Equatable, Sendable {
    var speedKmh: Double
    var limit: SpeedLimitStatus
}

nonisolated enum DemoDrive {
    /// Automatischer Ablauf: alle 15 s ein anderer Abschnitt, teils mit Überschreitung.
    static let phaseDuration: TimeInterval = 15
    static let phases: [(limit: DemoLimitOption, baseSpeed: Double)] = [
        (.kmh50, 47),
        (.kmh70, 74),
        (.kmh100, 108),
        (.kmh120, 116),
        (.unlimited, 152),
        (.unknown, 63),
        (.kmh30, 36),
    ]

    static func sample(elapsed: TimeInterval, auto: Bool,
                       manualSpeed: Double, manualLimit: DemoLimitOption) -> DemoSample {
        guard auto else {
            return DemoSample(speedKmh: max(0, manualSpeed), limit: manualLimit.status)
        }
        let t = max(0, elapsed)
        let index = Int(t / phaseDuration) % phases.count
        let phase = phases[index]
        let wobble = 4 * sin(t * 2 * .pi / 9)
        return DemoSample(speedKmh: max(0, phase.baseSpeed + wobble), limit: phase.limit.status)
    }
}
