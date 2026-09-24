//
//  MaxspeedParser.swift
//  Demonic Speed Display
//
//  Wertet OSM-`maxspeed`-Tags streng aus. Alles, was nicht eindeutig und
//  bedingungslos für Pkw gilt, wird als „unbekannt“ gemeldet. Es wird nie ein
//  Wert aus der Straßenart (`highway=*`) abgeleitet.
//

import Foundation

nonisolated enum MaxspeedParser {
    /// Gesetzliche Zonenangaben, die in OSM als Wert von `maxspeed` stehen dürfen
    /// (https://wiki.openstreetmap.org/wiki/Key:maxspeed). Nur Kategorien, die
    /// für Pkw ohne weitere Bedingungen gelten. Kategorien mit Wetter- oder
    /// Tageszeitabhängigkeit (z. B. FR:motorway, NL:motorway) fehlen bewusst.
    static let implicitZones: [String: SpeedLimitValue] = [
        "DE:URBAN": .kmh(50),
        "DE:RURAL": .kmh(100),
        "DE:ZONE20": .kmh(20), "DE:ZONE:20": .kmh(20),
        "DE:ZONE30": .kmh(30), "DE:ZONE:30": .kmh(30),
        "DE:BICYCLE_ROAD": .kmh(30),
        "DE:MOTORWAY": .unlimited,
        "AT:URBAN": .kmh(50),
        "AT:RURAL": .kmh(100),
        "AT:TRUNK": .kmh(100),
        "AT:MOTORWAY": .kmh(130),
        "AT:ZONE30": .kmh(30), "AT:ZONE:30": .kmh(30),
        "CH:URBAN": .kmh(50),
        "CH:RURAL": .kmh(80),
        "CH:TRUNK": .kmh(100),
        "CH:MOTORWAY": .kmh(120),
        "CH:ZONE20": .kmh(20), "CH:ZONE:20": .kmh(20),
        "CH:ZONE30": .kmh(30), "CH:ZONE:30": .kmh(30),
    ]

    enum ParsedValue: Equatable {
        case limit(SpeedLimitValue, implicit: Bool)
        case variable
        case unsupported(String)
    }

    /// Wertet einen einzelnen `maxspeed`-Wert aus.
    static func parseValue(_ raw: String) -> ParsedValue {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .unsupported(raw) }
        let lower = value.lowercased()

        // Mehrere Werte (z. B. „50;30“) sind nicht eindeutig.
        if value.contains(";") || value.contains("|") { return .unsupported(value) }
        switch lower {
        case "none", "unlimited": return .limit(.unlimited, implicit: false)
        case "signals", "variable": return .variable
        default: break
        }
        if let zone = implicitZones[value.uppercased()] {
            return .limit(zone, implicit: true)
        }

        // Zahl mit optionaler Einheit: „50“, „50 km/h“, „30 mph“.
        let digits = lower.prefix { $0.isNumber || $0 == "." }
        let unit = lower.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        guard !digits.isEmpty, let number = Double(digits), number == number.rounded() else {
            return .unsupported(value)
        }
        let intValue = Int(number)
        switch unit {
        case "", "km/h", "kmh", "kph":
            guard (5...300).contains(intValue) else { return .unsupported(value) }
            return .limit(.kmh(intValue), implicit: false)
        case "mph":
            guard (5...100).contains(intValue) else { return .unsupported(value) }
            return .limit(.mph(intValue), implicit: false)
        default:
            return .unsupported(value)
        }
    }

    /// Ermittelt das für Pkw geltende Limit eines Weges in der gegebenen Fahrtrichtung.
    static func resolve(tags: [String: String], direction: TravelDirection) -> SpeedLimitStatus {
        let directionKeys: [String]
        switch direction {
        case .forward: directionKeys = [":forward"]
        case .backward: directionKeys = [":backward"]
        case .unknown: directionKeys = [":forward", ":backward"]
        }

        // 1. Bedingte Limits (Uhrzeit, Nässe, Fahrzeugart …) → unbekannt.
        let conditionalKeys = ["maxspeed:conditional"] + directionKeys.map { "maxspeed\($0):conditional" }
        if conditionalKeys.contains(where: { tags[$0] != nil }) {
            return .unknown(.conditional)
        }

        // 2. Streckenbeeinflussungsanlagen.
        let variableKeys = ["maxspeed:variable"] + directionKeys.map { "maxspeed:variable\($0)" }
        if variableKeys.contains(where: { key in tags[key].map { $0.lowercased() != "no" } ?? false }) {
            return .unknown(.variable)
        }

        // 3. Fahrstreifenabhängige Limits.
        let laneKeys = ["maxspeed:lanes"] + directionKeys.map { "maxspeed:lanes\($0)" }
        var singleLaneValue: String?
        for key in laneKeys {
            guard let lanes = tags[key] else { continue }
            let distinct = Set(lanes.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) })
            if distinct.count > 1 { return .unknown(.laneDependent) }
            singleLaneValue = singleLaneValue ?? distinct.first
        }

        // 4. Richtungsabhängige Werte.
        let base = tags["maxspeed"]
        let forward = tags["maxspeed:forward"] ?? base
        let backward = tags["maxspeed:backward"] ?? base
        let raw: String?
        switch direction {
        case .forward: raw = forward
        case .backward: raw = backward
        case .unknown:
            if forward != backward { return .unknown(.directionUnclear) }
            raw = forward
        }

        guard let raw = raw ?? singleLaneValue else { return .unknown(.noLimitTagged) }
        switch parseValue(raw) {
        case .limit(let value, let implicit):
            return .known(SpeedLimit(value: value, isImplicit: implicit))
        case .variable:
            return .unknown(.variable)
        case .unsupported(let text):
            return .unknown(.unsupportedValue(text))
        }
    }
}
