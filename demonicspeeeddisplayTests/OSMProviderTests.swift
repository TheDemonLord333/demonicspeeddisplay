//
//  OSMProviderTests.swift
//  demonicspeeeddisplayTests
//

import Foundation
import Testing
@testable import demonicspeeeddisplay

struct OverpassParsingTests {
    @Test func parsesWaysWithGeometryAndTags() throws {
        let json = """
        {"version":0.6,"elements":[
          {"type":"way","id":42,"nodes":[1,2,3],
           "geometry":[{"lat":52.5,"lon":13.4},{"lat":52.5001,"lon":13.4001},{"lat":52.5002,"lon":13.4002}],
           "tags":{"highway":"primary","maxspeed":"50","name":"Allee"}},
          {"type":"node","id":7,"lat":52.5,"lon":13.4}
        ]}
        """
        let ways = try OverpassClient.parse(Data(json.utf8))
        #expect(ways.count == 1)
        #expect(ways[0].id == 42)
        #expect(ways[0].nodeIDs == [1, 2, 3])
        #expect(ways[0].points.count == 3)
        #expect(ways[0].tags["maxspeed"] == "50")
    }

    @Test func missingPointsSplitTheWay() throws {
        let json = """
        {"elements":[{"type":"way","id":1,"nodes":[1,2,3,4,5],
          "geometry":[{"lat":1,"lon":1},{"lat":1.0001,"lon":1},null,{"lat":1.0003,"lon":1},{"lat":1.0004,"lon":1}],
          "tags":{"highway":"residential"}}]}
        """
        let ways = try OverpassClient.parse(Data(json.utf8))
        #expect(ways.count == 2)
        #expect(ways[0].nodeIDs == [1, 2])
        #expect(ways[1].nodeIDs == [4, 5])
    }

    @Test func runtimeErrorRemarkIsRejected() {
        let json = """
        {"elements":[],"remark":"runtime error: Query timed out in \\"query\\" at line 3 after 21 seconds."}
        """
        #expect(throws: RoadDataError.timeout) { try OverpassClient.parse(Data(json.utf8)) }
    }

    @Test func garbageIsRejected() {
        #expect(throws: RoadDataError.invalidResponse) { try OverpassClient.parse(Data("<html>".utf8)) }
    }

    @Test func queryContainsRadiusAndPosition() {
        let client = OverpassClient(endpoint: OverpassClient.defaultEndpoint)
        let q = client.query(center: GeoCoordinate(latitude: 52.123456, longitude: 13.654321), radius: 750.4)
        #expect(q.contains("around:750,52.123456,13.654321"))
        #expect(q.contains("out geom;"))
    }
}

/// Test-Datenquelle ohne Netzwerk.
final class FakeRoadSource: RoadGeometrySource, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(GeoCoordinate, Double)] = []
    var result: Result<[RoadWay], RoadDataError>

    init(result: Result<[RoadWay], RoadDataError>) {
        self.result = result
    }

    var callCount: Int { lock.withLock { _calls.count } }

    func fetchRoads(center: GeoCoordinate, radius: Double) async throws -> [RoadWay] {
        let result = lock.withLock {
            _calls.append((center, radius))
            return self.result
        }
        return try result.get()
    }
}

@MainActor
struct OSMSpeedLimitProviderTests {
    let road = TestGeo.way(1, [(-3000, 0), (3000, 0)], tags: ["highway": "primary", "maxspeed": "70"])

    private func settle(_ provider: OSMSpeedLimitProvider) async {
        for _ in 0..<100 where provider.isFetching {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    @Test func loadsOnceAndMatchesLocally() async {
        let source = FakeRoadSource(result: .success([road]))
        var now = Date(timeIntervalSince1970: 1_000_000)
        let provider = OSMSpeedLimitProvider(source: source, clock: { now })
        let context = { SpeedLimitContext(now: now, isOnline: true) }

        #expect(provider.resolve(fix: TestGeo.fix(0, 3, course: 90, time: now), context: context()) == .unknown(.loading))
        await settle(provider)
        #expect(source.callCount == 1)

        // 20 GPS-Ereignisse auf 200 m: keine weitere Anfrage.
        for step in 1...20 {
            now = now.addingTimeInterval(1)
            let status = provider.resolve(fix: TestGeo.fix(Double(step) * 10, 3, course: 90, time: now), context: context())
            #expect(status.limit?.value == .kmh(70))
        }
        await settle(provider)
        #expect(source.callCount == 1)
    }

    @Test func refetchesNearCoverageEdge() async {
        let source = FakeRoadSource(result: .success([road]))
        var now = Date(timeIntervalSince1970: 1_000_000)
        let provider = OSMSpeedLimitProvider(source: source, clock: { now })
        _ = provider.resolve(fix: TestGeo.fix(0, 3, course: 90, time: now), context: SpeedLimitContext(now: now, isOnline: true))
        await settle(provider)
        #expect(source.callCount == 1)

        now = now.addingTimeInterval(60)
        _ = provider.resolve(fix: TestGeo.fix(1400, 3, course: 90, time: now), context: SpeedLimitContext(now: now, isOnline: true))
        await settle(provider)
        #expect(source.callCount == 2)
    }

    @Test func offlineWithoutCacheReportsOffline() {
        let source = FakeRoadSource(result: .success([road]))
        let now = Date(timeIntervalSince1970: 1_000_000)
        let provider = OSMSpeedLimitProvider(source: source, clock: { now })
        let status = provider.resolve(fix: TestGeo.fix(0, 3, course: 90, time: now),
                                      context: SpeedLimitContext(now: now, isOnline: false))
        #expect(status == .unknown(.offline))
        #expect(provider.requestCount == 0)
    }

    @Test func networkErrorBacksOffInsteadOfHammering() async {
        let source = FakeRoadSource(result: .failure(.server(status: 503)))
        var now = Date(timeIntervalSince1970: 1_000_000)
        let provider = OSMSpeedLimitProvider(source: source, clock: { now })
        let context = { SpeedLimitContext(now: now, isOnline: true) }

        _ = provider.resolve(fix: TestGeo.fix(0, 3, course: 90, time: now), context: context())
        await settle(provider)
        #expect(provider.resolve(fix: TestGeo.fix(0, 3, course: 90, time: now), context: context()) == .unknown(.networkError))
        now = now.addingTimeInterval(2)
        _ = provider.resolve(fix: TestGeo.fix(5, 3, course: 90, time: now), context: context())
        await settle(provider)
        #expect(source.callCount == 1)

        now = now.addingTimeInterval(10)
        _ = provider.resolve(fix: TestGeo.fix(10, 3, course: 90, time: now), context: context())
        await settle(provider)
        #expect(source.callCount == 2)
    }

    @Test func staleDataIsNotShown() async {
        let source = FakeRoadSource(result: .success([road]))
        var now = Date(timeIntervalSince1970: 1_000_000)
        let provider = OSMSpeedLimitProvider(source: source, clock: { now })
        _ = provider.resolve(fix: TestGeo.fix(0, 3, course: 90, time: now), context: SpeedLimitContext(now: now, isOnline: true))
        await settle(provider)

        now = now.addingTimeInterval(60 * 60)
        let status = provider.resolve(fix: TestGeo.fix(0, 3, course: 90, time: now),
                                      context: SpeedLimitContext(now: now, isOnline: false))
        #expect(status == .unknown(.staleData))
    }
}

@Test func freshCoverageNeverTriggersImmediateRefetch() {
    // Nach dem Laden muss der Vorlauf größer sein als die Nachlade-Schwelle – bei jedem Tempo.
    let c = OSMSpeedLimitProvider.Configuration()
    for speed in stride(from: 0.0, through: 70.0, by: 1.0) {
        let radius = min(c.maxRadius, max(c.minRadius, speed * c.coverageSeconds))
        let aheadAfterFetch = radius * (1 - c.lookAheadFraction)
        let lead = max(c.minRefetchLead, speed * c.refetchLeadSeconds)
        #expect(aheadAfterFetch > lead + 100, "speed \(speed)")
    }
}

struct DemoDriveTests {
    @Test func manualValuesArePassedThrough() {
        let sample = DemoDrive.sample(elapsed: 0, auto: false, manualSpeed: 88, manualLimit: .kmh70)
        #expect(sample.speedKmh == 88)
        #expect(sample.limit.limit?.value == .kmh(70))
    }

    @Test func autoCycleChangesLimit() {
        let first = DemoDrive.sample(elapsed: 1, auto: true, manualSpeed: 0, manualLimit: .kmh50)
        let second = DemoDrive.sample(elapsed: DemoDrive.phaseDuration + 1, auto: true, manualSpeed: 0, manualLimit: .kmh50)
        #expect(first.limit != second.limit)
    }
}
