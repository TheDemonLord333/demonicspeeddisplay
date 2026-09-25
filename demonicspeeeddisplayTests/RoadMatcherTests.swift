//
//  RoadMatcherTests.swift
//  demonicspeeeddisplayTests
//

import Foundation
import Testing
@testable import demonicspeeeddisplay

/// Baut Testgeometrie in Metern um einen Bezugspunkt (x = Ost, y = Nord).
enum TestGeo {
    static let origin = GeoCoordinate(latitude: 52.5, longitude: 13.4)
    static let metersPerDegree = GeoMath.earthRadius * .pi / 180

    static func point(_ x: Double, _ y: Double) -> GeoCoordinate {
        GeoCoordinate(latitude: origin.latitude + y / metersPerDegree,
                      longitude: origin.longitude + x / (metersPerDegree * cos(origin.latitude * .pi / 180)))
    }

    static func way(_ id: Int64, _ coords: [(Double, Double)], nodes: [Int64]? = nil,
                    tags: [String: String]) -> RoadWay {
        RoadWay(id: id,
                nodeIDs: nodes ?? coords.indices.map { id * 100 + Int64($0) },
                points: coords.map { point($0.0, $0.1) },
                tags: tags)
    }

    static func fix(_ x: Double, _ y: Double, speed: Double = 14, course: Double = -1,
                    accuracy: Double = 5, time: Date = Date(timeIntervalSince1970: 1_000_000)) -> LocationFix {
        LocationFix(coordinate: point(x, y), horizontalAccuracy: accuracy, speed: speed, speedAccuracy: 0.5,
                    course: course, courseAccuracy: course >= 0 ? 5 : -1, timestamp: time)
    }
}

struct RoadMatcherTests {
    let matcher = RoadMatcher()

    @Test func matchesSingleNearbyRoad() {
        let road = TestGeo.way(1, [(-500, 0), (500, 0)], tags: ["highway": "primary", "maxspeed": "50", "name": "Hauptstraße"])
        let result = matcher.match(fix: TestGeo.fix(0, 6, course: 90), ways: [road], memory: nil)
        #expect(result.status.limit?.value == .kmh(50))
        #expect(result.status.limit?.roadName == "Hauptstraße")
        #expect(result.memory?.wayID == 1)
    }

    @Test func farAwayRoadIsNotMatched() {
        let road = TestGeo.way(1, [(-500, 0), (500, 0)], tags: ["highway": "primary", "maxspeed": "50"])
        let result = matcher.match(fix: TestGeo.fix(0, 80, course: 90), ways: [road], memory: nil)
        #expect(result.status == .unknown(.noRoadNearby))
    }

    @Test func impreciseGPSIsNotMatched() {
        let road = TestGeo.way(1, [(-500, 0), (500, 0)], tags: ["highway": "primary", "maxspeed": "50"])
        let result = matcher.match(fix: TestGeo.fix(0, 2, accuracy: 60), ways: [road], memory: nil)
        #expect(result.status == .unknown(.gpsInsufficient))
    }

    @Test func parallelRoadsWithDifferentLimitsAreAmbiguous() {
        let a = TestGeo.way(1, [(-500, 0), (500, 0)], tags: ["highway": "primary", "maxspeed": "70"])
        let b = TestGeo.way(2, [(-500, 12), (500, 12)], tags: ["highway": "service"])
        let result = matcher.match(fix: TestGeo.fix(0, 6, course: 90), ways: [a, b], memory: nil)
        #expect(result.status == .unknown(.ambiguousRoad))
    }

    @Test func parallelRoadsWithSameLimitAreFine() {
        let a = TestGeo.way(1, [(-500, 0), (500, 0)], tags: ["highway": "primary", "maxspeed": "50"])
        let b = TestGeo.way(2, [(-500, 12), (500, 12)], tags: ["highway": "residential", "maxspeed": "50"])
        let result = matcher.match(fix: TestGeo.fix(0, 6, course: 90), ways: [a, b], memory: nil)
        #expect(result.status.limit?.value == .kmh(50))
    }

    @Test func headingSelectsRoadAtIntersection() {
        let eastWest = TestGeo.way(1, [(-500, 0), (500, 0)], tags: ["highway": "primary", "maxspeed": "70"])
        let northSouth = TestGeo.way(2, [(3, -500), (3, 500)], tags: ["highway": "residential", "maxspeed": "30"])
        let east = matcher.match(fix: TestGeo.fix(0, 1, course: 90), ways: [eastWest, northSouth], memory: nil)
        #expect(east.status.limit?.value == .kmh(70))
        let north = matcher.match(fix: TestGeo.fix(2, 1, course: 2), ways: [eastWest, northSouth], memory: nil)
        #expect(north.status.limit?.value == .kmh(30))
    }

    @Test func intersectionWithoutHeadingIsAmbiguous() {
        let eastWest = TestGeo.way(1, [(-500, 0), (500, 0)], tags: ["highway": "primary", "maxspeed": "70"])
        let northSouth = TestGeo.way(2, [(3, -500), (3, 500)], tags: ["highway": "residential", "maxspeed": "30"])
        let result = matcher.match(fix: TestGeo.fix(0, 1, speed: 0), ways: [eastWest, northSouth], memory: nil)
        #expect(result.status == .unknown(.ambiguousRoad))
    }

    @Test func dualCarriagewayUsesTravelDirection() {
        // Zwei Richtungsfahrbahnen, 20 m auseinander, Einbahn in Knotenreihenfolge.
        let eastbound = TestGeo.way(1, [(-500, 0), (500, 0)], tags: ["highway": "trunk", "oneway": "yes", "maxspeed": "100"])
        let westbound = TestGeo.way(2, [(500, 20), (-500, 20)], tags: ["highway": "trunk", "oneway": "yes", "maxspeed": "80"])
        let east = matcher.match(fix: TestGeo.fix(0, 10, speed: 27, course: 90), ways: [eastbound, westbound], memory: nil)
        #expect(east.status.limit?.value == .kmh(100))
        let west = matcher.match(fix: TestGeo.fix(0, 10, speed: 27, course: 270), ways: [eastbound, westbound], memory: nil)
        #expect(west.status.limit?.value == .kmh(80))
    }

    @Test func wrongWayOnOnewayIsNotMatched() {
        let oneway = TestGeo.way(1, [(-500, 0), (500, 0)], tags: ["highway": "primary", "oneway": "yes", "maxspeed": "50"])
        let result = matcher.match(fix: TestGeo.fix(0, 3, course: 270), ways: [oneway], memory: nil)
        #expect(result.status == .unknown(.noRoadNearby))
    }

    @Test func directionalTagsFollowTravelDirection() {
        let road = TestGeo.way(1, [(-500, 0), (500, 0)],
                               tags: ["highway": "secondary", "maxspeed:forward": "70", "maxspeed:backward": "50"])
        #expect(matcher.match(fix: TestGeo.fix(0, 3, course: 88), ways: [road], memory: nil).status.limit?.value == .kmh(70))
        #expect(matcher.match(fix: TestGeo.fix(0, 3, course: 268), ways: [road], memory: nil).status.limit?.value == .kmh(50))
        #expect(matcher.match(fix: TestGeo.fix(0, 3, speed: 0), ways: [road], memory: nil).status == .unknown(.directionUnclear))
    }

    @Test func limitChangeAtSharedNodeIsNotAmbiguous() {
        // Ortsausgang: Weg 1 (50) endet an Knoten 7, Weg 2 (100) beginnt dort.
        let town = TestGeo.way(1, [(-500, 0), (0, 0)], nodes: [6, 7], tags: ["highway": "primary", "maxspeed": "50"])
        let rural = TestGeo.way(2, [(0, 0), (500, 0)], nodes: [7, 8], tags: ["highway": "primary", "maxspeed": "100"])
        let before = matcher.match(fix: TestGeo.fix(-6, 2, course: 90), ways: [town, rural], memory: nil)
        #expect(before.status.limit?.value == .kmh(50))
        let after = matcher.match(fix: TestGeo.fix(6, 2, course: 90), ways: [town, rural], memory: before.memory)
        #expect(after.status.limit?.value == .kmh(100))
    }

    @Test func keepsRoadWhileStoppedAtIntersection() {
        let eastWest = TestGeo.way(1, [(-500, 0), (500, 0)], tags: ["highway": "primary", "maxspeed": "70"])
        let northSouth = TestGeo.way(2, [(3, -500), (3, 500)], tags: ["highway": "residential", "maxspeed": "30"])
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let driving = matcher.match(fix: TestGeo.fix(-30, 1, course: 90, time: t0), ways: [eastWest, northSouth], memory: nil)
        #expect(driving.status.limit?.value == .kmh(70))
        let stopped = matcher.match(fix: TestGeo.fix(0, 1, speed: 0, time: t0.addingTimeInterval(20)),
                                    ways: [eastWest, northSouth], memory: driving.memory)
        #expect(stopped.status.limit?.value == .kmh(70))
        // Nach zu langer Zeit ohne Richtung wird nicht mehr festgehalten.
        let later = matcher.match(fix: TestGeo.fix(0, 1, speed: 0, time: t0.addingTimeInterval(200)),
                                  ways: [eastWest, northSouth], memory: stopped.memory)
        #expect(later.status == .unknown(.ambiguousRoad))
    }

    @Test func conditionalRoadStaysUnknown() {
        let road = TestGeo.way(1, [(-500, 0), (500, 0)],
                               tags: ["highway": "motorway", "maxspeed": "120", "maxspeed:conditional": "100 @ (22:00-06:00)"])
        let result = matcher.match(fix: TestGeo.fix(0, 3, speed: 30, course: 90), ways: [road], memory: nil)
        #expect(result.status == .unknown(.conditional))
    }
}
