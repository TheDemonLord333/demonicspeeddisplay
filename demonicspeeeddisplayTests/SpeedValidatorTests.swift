//
//  SpeedValidatorTests.swift
//  demonicspeeeddisplayTests
//

import Foundation
import Testing
@testable import demonicspeeeddisplay

struct SpeedValidatorTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let validator = SpeedValidator()

    private func fix(speed: Double = 20, speedAccuracy: Double = 0.5,
                     horizontalAccuracy: Double = 5, age: TimeInterval = 0.5) -> LocationFix {
        LocationFix(coordinate: GeoCoordinate(latitude: 52.5, longitude: 13.4),
                    horizontalAccuracy: horizontalAccuracy, speed: speed, speedAccuracy: speedAccuracy,
                    course: 90, courseAccuracy: 5, timestamp: now.addingTimeInterval(-age))
    }

    @Test func validReadingIsConvertedToKmh() {
        #expect(validator.evaluate(fix(speed: 25), now: now) == .valid(kmh: 90))
    }

    @Test func noFixMeansWaiting() {
        #expect(validator.evaluate(nil, now: now) == .waiting)
    }

    @Test func oldReadingIsStale() {
        #expect(validator.evaluate(fix(age: 3.5), now: now) == .stale)
        #expect(validator.evaluate(fix(age: -30), now: now) == .stale)
    }

    @Test func invalidOrImpreciseSpeedIsRejected() {
        #expect(validator.evaluate(fix(speed: -1), now: now) == .inaccurate)
        #expect(validator.evaluate(fix(speedAccuracy: -1), now: now) == .inaccurate)
        #expect(validator.evaluate(fix(speedAccuracy: 5), now: now) == .inaccurate)
        #expect(validator.evaluate(fix(horizontalAccuracy: 80), now: now) == .inaccurate)
        #expect(validator.evaluate(fix(horizontalAccuracy: -1), now: now) == .inaccurate)
        #expect(validator.evaluate(fix(speed: 150), now: now) == .inaccurate)
    }

    @Test func standstillNoiseShowsZero() {
        #expect(validator.evaluate(fix(speed: 0.4), now: now) == .valid(kmh: 0))
    }
}
