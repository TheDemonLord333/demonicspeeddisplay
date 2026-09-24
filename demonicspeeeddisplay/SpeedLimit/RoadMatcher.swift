//
//  RoadMatcher.swift
//  Demonic Speed Display
//
//  Ordnet eine GPS-Position einem Straßenabschnitt zu – anhand von Entfernung,
//  Fahrtrichtung, Einbahnregelung und Fahrtkontinuität. Liegen mehrere plausible
//  Straßen mit unterschiedlichem Limit nahe beieinander, ist das Ergebnis
//  „nicht eindeutig“ statt geraten.
//

import Foundation

/// Merkt sich die zuletzt sicher zugeordnete Straße.
nonisolated struct MatchMemory: Equatable, Sendable {
    var wayID: Int64
    var nodeIDs: Set<Int64>
    var direction: TravelDirection
    var timestamp: Date
}

nonisolated struct RoadMatchResult: Equatable, Sendable {
    var status: SpeedLimitStatus
    /// Aktualisiertes Gedächtnis (nur bei eindeutiger Zuordnung gesetzt).
    var memory: MatchMemory?
}

nonisolated struct RoadMatcher: Sendable {
    /// Suchradius um die Position; wächst mit der GPS-Unsicherheit.
    var minMatchDistance = 20.0
    var maxMatchDistance = 45.0
    /// Ab dieser Positionsunsicherheit wird gar nicht zugeordnet.
    var maxUsableAccuracy = 35.0
    /// Maximal zulässige Abweichung zwischen Fahrtrichtung und Straßenverlauf.
    var maxHeadingDeviation = 40.0
    /// Strafmeter pro Grad Richtungsabweichung.
    var headingPenaltyPerDegree = 0.25
    /// Bonus für die bisher befahrene bzw. eine direkt anschließende Straße.
    var sameWayBonus = 8.0
    var connectedWayBonus = 4.0
    /// Kandidaten, deren Bewertung näher als dieser Wert am besten liegt, gelten als Konkurrenz.
    var ambiguityMargin = 10.0
    /// So lange darf ohne verwertbare Fahrtrichtung (Stillstand, Schrittgeschwindigkeit)
    /// die bisherige Straße beibehalten werden.
    var memoryHoldDuration: TimeInterval = 60

    struct Candidate {
        let way: RoadWay
        let distance: Double
        let direction: TravelDirection
        let score: Double
        /// Lotfußpunkt liegt auf dem Anfangs- oder Endknoten des Weges, d. h. die
        /// Position liegt eher „hinter“ diesem Weg.
        let atWayEnd: Bool
    }

    func match(fix: LocationFix, ways: [RoadWay], memory: MatchMemory?) -> RoadMatchResult {
        guard fix.coordinate.isValid,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= maxUsableAccuracy else {
            return RoadMatchResult(status: .unknown(.gpsInsufficient), memory: memory)
        }
        let course = fix.reliableCourse
        let validMemory = memory.flatMap {
            fix.timestamp.timeIntervalSince($0.timestamp) <= memoryHoldDuration ? $0 : nil
        }

        let found = collectCandidates(fix: fix, course: course, ways: ways, memory: validMemory)
        guard !found.isEmpty else {
            return RoadMatchResult(status: .unknown(.noRoadNearby), memory: nil)
        }

        // Liegt die Position hinter dem Ende eines Weges und gibt es einen daran
        // anschließenden Weg, auf dem sie „innen“ liegt, ist der erste bereits verlassen.
        let candidates = found.filter { c in
            !(c.atWayEnd && found.contains { other in
                !other.atWayEnd && other.way.id != c.way.id
                    && !Set(other.way.nodeIDs).isDisjoint(with: c.way.nodeIDs)
            })
        }
        .sorted { $0.score < $1.score }

        // Ohne Fahrtrichtung (Stillstand) an der bisherigen Straße festhalten,
        // solange sie weiterhin plausibel in der Nähe liegt.
        if course == nil, let validMemory,
           let kept = candidates.first(where: { $0.way.id == validMemory.wayID }) {
            let direction = kept.direction == .unknown ? validMemory.direction : kept.direction
            let status = decorate(MaxspeedParser.resolve(tags: kept.way.tags, direction: direction), way: kept.way)
            var updated = validMemory
            updated.timestamp = fix.timestamp
            return RoadMatchResult(status: status, memory: updated)
        }

        guard let best = candidates.first else {
            return RoadMatchResult(status: .unknown(.noRoadNearby), memory: nil)
        }
        let bestStatus = MaxspeedParser.resolve(tags: best.way.tags, direction: best.direction)

        // Konkurrierende Straßen mit abweichendem Ergebnis → nicht eindeutig.
        for other in candidates.dropFirst() where other.score - best.score < ambiguityMargin {
            guard other.way.id != best.way.id else { continue }
            let otherStatus = MaxspeedParser.resolve(tags: other.way.tags, direction: other.direction)
            if !sameEffectiveLimit(bestStatus, otherStatus) {
                return RoadMatchResult(status: .unknown(.ambiguousRoad), memory: nil)
            }
        }

        let newMemory = MatchMemory(wayID: best.way.id,
                                    nodeIDs: Set(best.way.nodeIDs),
                                    direction: best.direction,
                                    timestamp: fix.timestamp)
        return RoadMatchResult(status: decorate(bestStatus, way: best.way), memory: newMemory)
    }

    private func collectCandidates(fix: LocationFix, course: Double?,
                                   ways: [RoadWay], memory: MatchMemory?) -> [Candidate] {
        let threshold = min(maxMatchDistance, max(minMatchDistance, fix.horizontalAccuracy + 15))
        let projection = LocalProjection(origin: fix.coordinate)
        let origin = (x: 0.0, y: 0.0)
        var result: [Candidate] = []

        for way in ways where way.points.count >= 2 {
            let pts = way.points.map(projection.project)
            let oneway = way.onewayDirection
            var bestForWay: Candidate?

            for i in 0..<(pts.count - 1) {
                guard let seg = SegmentMath.project(point: origin, from: pts[i], to: pts[i + 1]),
                      seg.distance <= threshold else { continue }

                var direction: TravelDirection
                var deviation = 0.0
                if let course {
                    let forwardDev = GeoMath.angleDifference(course, seg.bearing)
                    let backwardDev = GeoMath.angleDifference(course, seg.bearing + 180)
                    switch oneway {
                    case 1: direction = .forward; deviation = forwardDev
                    case -1: direction = .backward; deviation = backwardDev
                    default:
                        direction = forwardDev <= backwardDev ? .forward : .backward
                        deviation = min(forwardDev, backwardDev)
                    }
                    guard deviation <= maxHeadingDeviation else { continue }
                } else {
                    direction = oneway == 1 ? .forward : (oneway == -1 ? .backward : .unknown)
                }

                var score = seg.distance + deviation * headingPenaltyPerDegree
                if let memory {
                    if way.id == memory.wayID {
                        score -= sameWayBonus
                    } else if !memory.nodeIDs.isDisjoint(with: way.nodeIDs) {
                        score -= connectedWayBonus
                    }
                }
                let atEnd = (i == 0 && seg.t <= 0) || (i == pts.count - 2 && seg.t >= 1)
                let candidate = Candidate(way: way, distance: seg.distance, direction: direction,
                                          score: score, atWayEnd: atEnd)
                if bestForWay == nil || candidate.score < bestForWay!.score {
                    bestForWay = candidate
                }
            }
            if let bestForWay { result.append(bestForWay) }
        }
        return result
    }

    private func sameEffectiveLimit(_ a: SpeedLimitStatus, _ b: SpeedLimitStatus) -> Bool {
        switch (a, b) {
        case (.known(let x), .known(let y)): return x.value == y.value
        default: return false
        }
    }

    private func decorate(_ status: SpeedLimitStatus, way: RoadWay) -> SpeedLimitStatus {
        guard case .known(var limit) = status else { return status }
        limit.roadName = way.name
        limit.wayID = way.id
        return .known(limit)
    }
}
