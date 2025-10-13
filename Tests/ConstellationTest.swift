//
//  ConstellationTest.swift
//  Graviton
//
//  Created by Sihao Lu on 3/4/17.
//  Copyright © 2017 Ben Lu. All rights reserved.
//

import XCTest
@testable import StarryNight

final class ConstellationTest: XCTestCase {
    
    private var starManager: StarManager!
    
    override func setUp() {
        super.setUp()
        do {
            starManager = try StarManager()
        } catch {
            XCTFail("Failed to initialize StarManager: \(error)")
        }
    }
    
    override func tearDown() {
        starManager = nil
        super.tearDown()
    }

    func testConstellationQuery() {
        let iauQuery = starManager.constellation(iau: "Tau")
        XCTAssertNotNil(iauQuery)
        let nameQuery = starManager.constellation(named: "Orion")
        XCTAssertNotNil(nameQuery)
    }

    func testConstellationLinesFetch() throws {
        // You may need to adjust this path or use a test DB
        // let dbPath = Bundle.module.path(forResource: "stars", ofType: "sqlite3")!
        // let manager = StarManager(databasePath: dbPath)
        // Use the test's starManager instance
        guard let orion = starManager.constellation(iau: "Ori") else {
            XCTFail("Could not find Orion constellation in DB")
            return
        }
        let lines = starManager.constellationLines(for: orion)
        XCTAssertFalse(lines.isEmpty, "Orion should have constellation lines")
        for line in lines {
            XCTAssertNotEqual(line.star1Id, line.star2Id, "Line endpoints should not be the same star")
            XCTAssertNotNil(starManager.star(withId: line.star1Id), "Line should reference a valid star1 ID")
            XCTAssertNotNil(starManager.star(withId: line.star2Id), "Line should reference a valid star2 ID")
        }
    }

    func testConnectionLinesLoading() {
        let allConstellations = starManager.allConstellations()
        
        // Test that we have constellations loaded
        XCTAssertFalse(allConstellations.isEmpty, "Should have constellations loaded")
        
        // Test connection lines for a well-known constellation (Orion)
        if let orion = starManager.constellation(named: "Orion") {
            let orionLines = starManager.constellationLines(for: orion)
            XCTAssertFalse(orionLines.isEmpty, "Orion should have connection lines")
            
            // Verify that connection lines have valid stars
            for line in orionLines {
                let star1 = starManager.star(withId: line.star1Id)
                let star2 = starManager.star(withId: line.star2Id)
                XCTAssertNotNil(star1, "Connection line should have valid star1 ID")
                XCTAssertNotNil(star2, "Connection line should have valid star2 ID")
                if let star1, let star2 {
                    XCTAssertNotEqual(star1.id, star2.id, "Connection line should connect different stars")
                }
            }
        } else {
            XCTFail("Should be able to find Orion constellation")
        }
        
        // Test that some constellations have connection lines
        var constellationsWithLines = 0
        for constellation in allConstellations.prefix(10) { // Test first 10 to avoid long test times
            let lines = starManager.constellationLines(for: constellation)
            if !lines.isEmpty {
                constellationsWithLines += 1
            }
        }
        XCTAssertGreaterThan(constellationsWithLines, 0, "At least some constellations should have connection lines")
    }
    
    func testConstellationBordersFetch() throws {
        guard let andromeda = starManager.constellation(iau: "And") else {
            XCTFail("Could not find Andromeda constellation in DB")
            return
        }

        let borders = starManager.constellationBorders(for: andromeda)
        XCTAssertFalse(borders.isEmpty, "Andromeda should have border segments")

        for segment in borders {
            XCTAssertTrue(segment.start.lat.isFinite && segment.start.lng.isFinite, "Start coordinate should be finite")
            XCTAssertTrue(segment.end.lat.isFinite && segment.end.lng.isFinite, "End coordinate should be finite")
            XCTAssertLessThanOrEqual(abs(segment.start.lat), .pi / 2.0 + 1e-9, "Start declination should be within bounds")
            XCTAssertLessThanOrEqual(abs(segment.end.lat), .pi / 2.0 + 1e-9, "End declination should be within bounds")
            XCTAssertLessThanOrEqual(abs(segment.start.lng), .pi + 1e-9, "Start right ascension should be normalized")
            XCTAssertLessThanOrEqual(abs(segment.end.lng), .pi + 1e-9, "End right ascension should be normalized")
        }

        if let serpent = starManager.constellation(iau: "Ser1") {
            let serpentBorders = starManager.constellationBorders(for: serpent)
            XCTAssertFalse(serpentBorders.isEmpty, "Serpens Caput should expose borders")
        }
    }

}
