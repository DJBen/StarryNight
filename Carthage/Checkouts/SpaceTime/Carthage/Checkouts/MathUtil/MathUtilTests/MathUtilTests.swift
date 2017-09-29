//
//  MathUtilTests.swift
//  MathUtil
//
//  Created by Sihao Lu on 7/21/17.
//  Copyright © 2017 Sihao. All rights reserved.
//

import XCTest
@testable import MathUtil

class MathUtilTests: XCTestCase {
    
    func testAngleConversion() {
        XCTAssertEqual(degrees(radians: Double.pi / 2), 90)
        XCTAssertEqual(radians(degrees: 30), 30 * Double.pi / 180)
        XCTAssertEqual(radians(degrees: degrees(radians: 43.32)), 43.32)
    }

    func testHourConversion() {
        XCTAssertEqualWithAccuracy(radians(hours: 6, minutes: 45, seconds: 9), radians(degrees: 101.2875), accuracy: 1e-3)
    }

    func testInterpolation() {
        let interp = Easing(startValue: 2.1, endValue: 7.5)
        XCTAssertEqual(interp.value(at: 0.85), 2.1 + (7.5 - 2.1) * 0.85)
    }
}
