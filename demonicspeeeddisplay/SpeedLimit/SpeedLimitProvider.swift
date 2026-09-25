//
//  SpeedLimitProvider.swift
//  Demonic Speed Display
//
//  Austauschbare Datenquellen. Zwei Ebenen:
//
//  1. `SpeedLimitProvider` – liefert zu einer Position direkt ein Tempolimit.
//     Ein kommerzieller Anbieter, der Limits selbst zuordnet (z. B. per
//     „Snap to Road“-API), implementiert nur dieses Protokoll.
//  2. `RoadGeometrySource` – liefert Straßengeometrie mit OSM-kompatiblen Tags.
//     Wer nur die Rohdaten austauschen will (eigener Overpass-Server, lokale
//     Datei, anderer OSM-Dienst), implementiert nur dieses Protokoll und
//     verwendet weiterhin `OSMSpeedLimitProvider` samt Zuordnungslogik.
//

import Foundation

nonisolated struct SpeedLimitContext: Sendable {
    var now: Date
    var isOnline: Bool
}

@MainActor
protocol SpeedLimitProvider: AnyObject {
    /// Name für die Anzeige in den Einstellungen.
    var sourceName: String { get }
    /// Pflicht-Quellenangabe der Daten (Lizenz).
    var attribution: String { get }
    /// Wird aufgerufen, wenn neue Daten eingetroffen sind oder ein Abruf fehlschlug.
    var onDataChanged: (() -> Void)? { get set }
    /// Muss günstig sein: wird für jeden gültigen GPS-Wert aufgerufen. Der Anbieter
    /// entscheidet selbst, wann eine Netzwerkanfrage nötig ist.
    func resolve(fix: LocationFix, context: SpeedLimitContext) -> SpeedLimitStatus
    /// Verwirft Cache und laufende Anfragen.
    func reset()
}

nonisolated enum RoadDataError: Error, Equatable, Sendable {
    case offline
    case timeout
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case invalidResponse
    case transport
}

nonisolated protocol RoadGeometrySource: Sendable {
    /// Alle für Kraftfahrzeuge relevanten Straßen im Umkreis (Meter) um `center`.
    func fetchRoads(center: GeoCoordinate, radius: Double) async throws -> [RoadWay]
}
