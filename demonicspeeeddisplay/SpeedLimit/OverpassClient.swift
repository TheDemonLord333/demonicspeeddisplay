//
//  OverpassClient.swift
//  Demonic Speed Display
//
//  Lädt Straßen samt Tags aus OpenStreetMap über die Overpass API.
//  Nutzungsbedingungen: https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated struct OverpassClient: RoadGeometrySource {
    static let defaultEndpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    /// Öffentliche Instanzen zur Auswahl in den Einstellungen.
    static let knownEndpoints: [OverpassEndpoint] = [
        OverpassEndpoint(name: "overpass-api.de (Standard)", url: "https://overpass-api.de/api/interpreter"),
        OverpassEndpoint(name: "private.coffee", url: "https://overpass.private.coffee/api/interpreter"),
        OverpassEndpoint(name: "Kumi Systems", url: "https://overpass.kumi.systems/api/interpreter"),
    ]

    /// Straßenarten, die mit dem Auto befahren werden. Parkplatzgassen und
    /// Grundstückszufahrten werden ausgeschlossen, um Fehlzuordnungen zu vermeiden.
    static let highwayPattern =
        "^(motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|"
        + "tertiary|tertiary_link|unclassified|residential|living_street|road|service)$"

    var endpoint: URL
    var session: URLSession = .shared
    var requestTimeout: TimeInterval = 25
    var userAgent = "DemonicSpeedDisplay/1.0 (iOS; speed limit display)"

    func query(center: GeoCoordinate, radius: Double) -> String {
        let lat = String(format: "%.6f", center.latitude)
        let lon = String(format: "%.6f", center.longitude)
        let r = Int(radius.rounded())
        return """
        [out:json][timeout:20];
        way(around:\(r),\(lat),\(lon))["highway"~"\(Self.highwayPattern)"]\
        ["service"!~"^(parking_aisle|driveway|drive-through|emergency_access)$"]\
        ["area"!="yes"];
        out geom;
        """
    }

    func fetchRoads(center: GeoCoordinate, radius: Double) async throws -> [RoadWay] {
        var request = URLRequest(url: endpoint, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(("data=" + Self.formEncode(query(center: center, radius: radius))).utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .internationalRoamingOff, .cannotFindHost, .dnsLookupFailed:
                throw RoadDataError.offline
            case .timedOut:
                throw RoadDataError.timeout
            case .cancelled:
                throw CancellationError()
            default:
                throw RoadDataError.transport
            }
        }

        guard let http = response as? HTTPURLResponse else { throw RoadDataError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw RoadDataError.rateLimited(retryAfter: retry)
        case 504: throw RoadDataError.timeout
        default: throw RoadDataError.server(status: http.statusCode)
        }
        return try await Self.decode(data)
    }

    /// JSON-Auswertung abseits des Main Actors.
    @concurrent
    static func decode(_ data: Data) async throws -> [RoadWay] {
        try parse(data)
    }

    static func parse(_ data: Data) throws -> [RoadWay] {
        let response: OverpassResponse
        do {
            response = try JSONDecoder().decode(OverpassResponse.self, from: data)
        } catch {
            throw RoadDataError.invalidResponse
        }
        // Overpass meldet Abbrüche (Timeout, Speicher) mit HTTP 200 und „remark“ –
        // die Daten sind dann unvollständig und dürfen nicht verwendet werden.
        if let remark = response.remark?.lowercased(), remark.contains("error") {
            throw remark.contains("timed out") ? RoadDataError.timeout : RoadDataError.invalidResponse
        }

        var ways: [RoadWay] = []
        for element in response.elements where element.type == "way" {
            guard let geometry = element.geometry, let tags = element.tags else { continue }
            let nodes = element.nodes ?? []
            // Fehlende Punkte (null) trennen den Weg in zusammenhängende Teilstücke.
            var runPoints: [GeoCoordinate] = []
            var runNodes: [Int64] = []
            func flush() {
                if runPoints.count >= 2 {
                    ways.append(RoadWay(id: element.id, nodeIDs: runNodes, points: runPoints, tags: tags))
                }
                runPoints.removeAll()
                runNodes.removeAll()
            }
            for (index, point) in geometry.enumerated() {
                if let point {
                    runPoints.append(GeoCoordinate(latitude: point.lat, longitude: point.lon))
                    if index < nodes.count { runNodes.append(nodes[index]) }
                } else {
                    flush()
                }
            }
            flush()
        }
        return ways
    }

    private static func formEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

nonisolated struct OverpassEndpoint: Identifiable, Sendable {
    let name: String
    let url: String
    var id: String { url }
}

nonisolated private struct OverpassResponse: Decodable {
    struct Point: Decodable {
        let lat: Double
        let lon: Double
    }

    struct Element: Decodable {
        let type: String
        let id: Int64
        let nodes: [Int64]?
        let geometry: [Point?]?
        let tags: [String: String]?
    }

    let elements: [Element]
    let remark: String?
}
