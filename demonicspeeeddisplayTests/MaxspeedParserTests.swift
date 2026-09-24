//
//  MaxspeedParserTests.swift
//  demonicspeeeddisplayTests
//

import Testing
@testable import demonicspeeeddisplay

struct MaxspeedParserTests {
    private func resolve(_ tags: [String: String], _ direction: TravelDirection = .forward) -> SpeedLimitStatus {
        MaxspeedParser.resolve(tags: tags, direction: direction)
    }

    @Test func plainNumberIsKmh() {
        #expect(resolve(["maxspeed": "50"]).limit?.value == .kmh(50))
        #expect(resolve(["maxspeed": " 120 "]).limit?.value == .kmh(120))
        #expect(resolve(["maxspeed": "30 km/h"]).limit?.value == .kmh(30))
    }

    @Test func mphIsKeptAsMph() {
        #expect(resolve(["maxspeed": "30 mph"]).limit?.value == .mph(30))
        #expect(resolve(["maxspeed": "30mph"]).limit?.value == .mph(30))
    }

    @Test func noneMeansUnlimited() {
        #expect(resolve(["maxspeed": "none"]).limit?.value == .unlimited)
    }

    @Test func implicitZonesAreMarked() {
        let status = resolve(["maxspeed": "DE:urban"])
        #expect(status.limit?.value == .kmh(50))
        #expect(status.limit?.isImplicit == true)
        #expect(resolve(["maxspeed": "DE:zone30"]).limit?.value == .kmh(30))
        #expect(resolve(["maxspeed": "DE:motorway"]).limit?.value == .unlimited)
    }

    @Test func missingTagIsUnknownEvenOnMotorway() {
        // Kein Raten anhand der Straßenart.
        #expect(resolve(["highway": "motorway"]) == .unknown(.noLimitTagged))
        #expect(resolve(["highway": "residential"]) == .unknown(.noLimitTagged))
    }

    @Test func conditionalLimitsAreUnknown() {
        #expect(resolve(["maxspeed": "100", "maxspeed:conditional": "80 @ wet"]) == .unknown(.conditional))
        #expect(resolve(["maxspeed": "50", "maxspeed:forward:conditional": "30 @ (Mo-Fr 07:00-17:00)"], .forward)
                == .unknown(.conditional))
        // Bedingung der Gegenrichtung betrifft die eigene Richtung nicht.
        #expect(resolve(["maxspeed": "50", "maxspeed:backward:conditional": "30 @ (22:00-06:00)"], .forward)
                .limit?.value == .kmh(50))
    }

    @Test func variableLimitsAreUnknown() {
        #expect(resolve(["maxspeed": "signals"]) == .unknown(.variable))
        #expect(resolve(["maxspeed": "120", "maxspeed:variable": "obstruction"]) == .unknown(.variable))
        #expect(resolve(["maxspeed": "120", "maxspeed:variable": "no"]).limit?.value == .kmh(120))
    }

    @Test func directionalLimits() {
        let tags = ["maxspeed:forward": "70", "maxspeed:backward": "50"]
        #expect(resolve(tags, .forward).limit?.value == .kmh(70))
        #expect(resolve(tags, .backward).limit?.value == .kmh(50))
        #expect(resolve(tags, .unknown) == .unknown(.directionUnclear))
        // Gleiche Werte in beide Richtungen sind auch ohne Richtung eindeutig.
        #expect(resolve(["maxspeed": "60", "maxspeed:forward": "60"], .unknown).limit?.value == .kmh(60))
    }

    @Test func laneDependentLimits() {
        #expect(resolve(["maxspeed:lanes": "120|120|80"]) == .unknown(.laneDependent))
        #expect(resolve(["maxspeed:lanes": "100|100"]).limit?.value == .kmh(100))
    }

    @Test func unclearValuesAreUnknown() {
        #expect(resolve(["maxspeed": "50;30"]) == .unknown(.unsupportedValue("50;30")))
        #expect(resolve(["maxspeed": "walk"]) == .unknown(.unsupportedValue("walk")))
        #expect(resolve(["maxspeed": "FR:motorway"]) == .unknown(.unsupportedValue("FR:motorway")))
        #expect(resolve(["maxspeed": "999"]) == .unknown(.unsupportedValue("999")))
        #expect(resolve(["maxspeed": "7.5"]) == .unknown(.unsupportedValue("7.5")))
        #expect(resolve(["maxspeed": "20 knots"]) == .unknown(.unsupportedValue("20 knots")))
    }
}
