//
//  SpeedLimitModels.swift
//  Demonic Speed Display
//

import Foundation

/// Ein erkanntes, eindeutig gültiges Tempolimit.
nonisolated enum SpeedLimitValue: Equatable, Hashable, Sendable {
    case kmh(Int)
    case mph(Int)
    /// Ausdrücklich keine Beschränkung (z. B. `maxspeed=none` auf deutschen Autobahnen).
    case unlimited

    /// Grenze in km/h für den Vergleich mit der Geschwindigkeit; `nil` bei unbegrenzt.
    var kmhValue: Double? {
        switch self {
        case .kmh(let v): return Double(v)
        case .mph(let v): return Double(v) * 1.609344
        case .unlimited: return nil
        }
    }
}

nonisolated struct SpeedLimit: Equatable, Sendable {
    var value: SpeedLimitValue
    /// Wert stammt aus einer gesetzlichen Zonenangabe (z. B. `DE:urban`),
    /// nicht aus einer ausdrücklichen Zahl.
    var isImplicit: Bool = false
    var roadName: String?
    var wayID: Int64?
}

/// Warum kein Tempolimit angezeigt wird.
nonisolated enum UnknownLimitReason: Equatable, Sendable {
    case noPosition
    case gpsInsufficient
    case loading
    case offline
    case networkError
    case rateLimited
    case staleData
    case noRoadNearby
    case ambiguousRoad
    case noLimitTagged
    case conditional
    case variable
    case laneDependent
    case directionUnclear
    case unsupportedValue(String)

    var explanation: String {
        switch self {
        case .noPosition: return "Warte auf gültige Position"
        case .gpsInsufficient: return "GPS zu ungenau für die Straßenzuordnung"
        case .loading: return "Straßendaten werden geladen"
        case .offline: return "Kein Internet – keine Straßendaten"
        case .networkError: return "Datenquelle nicht erreichbar"
        case .rateLimited: return "Datenquelle ausgelastet – neuer Versuch folgt"
        case .staleData: return "Straßendaten veraltet"
        case .noRoadNearby: return "Keine Straße in der Nähe erkannt"
        case .ambiguousRoad: return "Straße nicht eindeutig zuzuordnen"
        case .noLimitTagged: return "Für diese Straße ist kein Limit erfasst"
        case .conditional: return "Limit gilt nur bedingt (Zeit, Nässe, Fahrzeug …)"
        case .variable: return "Variables Limit (Verkehrsbeeinflussung)"
        case .laneDependent: return "Limit je Fahrstreifen verschieden"
        case .directionUnclear: return "Limit richtungsabhängig – Fahrtrichtung unklar"
        case .unsupportedValue(let raw): return "Nicht eindeutiger Wert „\(raw)“"
        }
    }
}

nonisolated enum SpeedLimitStatus: Equatable, Sendable {
    case known(SpeedLimit)
    case unknown(UnknownLimitReason)

    var limit: SpeedLimit? {
        if case .known(let l) = self { return l }
        return nil
    }
}

/// Richtung, in der ein Weg befahren wird, relativ zur Knotenreihenfolge in OSM.
nonisolated enum TravelDirection: Equatable, Sendable {
    case forward
    case backward
    case unknown
}

/// Straßenabschnitt mit Geometrie und Rohattributen (OSM-Tags).
nonisolated struct RoadWay: Equatable, Sendable {
    let id: Int64
    let nodeIDs: [Int64]
    let points: [GeoCoordinate]
    let tags: [String: String]

    var highway: String? { tags["highway"] }
    var name: String? { tags["name"] ?? tags["ref"] }

    /// Einbahnrichtung: +1 nur in Knotenreihenfolge, -1 nur entgegen, 0 beide.
    var onewayDirection: Int {
        switch tags["oneway"]?.lowercased() {
        case "yes", "true", "1": return 1
        case "-1", "reverse": return -1
        case "no", "false", "0", "reversible", "alternating": return 0
        default:
            // Laut OSM-Konvention implizit Einbahn.
            if highway == "motorway" { return 1 }
            if let junction = tags["junction"], junction == "roundabout" || junction == "circular" { return 1 }
            return 0
        }
    }
}
