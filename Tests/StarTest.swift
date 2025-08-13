//
//  StarTest.swift
//  Graviton
//
//  Created by Ben Lu on 2/4/17.
//  Copyright © 2017 Ben Lu. All rights reserved.
//

import XCTest
@testable import StarryNight

final class StarTest: XCTestCase {
    
    private var starManager: StarManager!
    
    override func setUp() {
        super.setUp()
        do {
            starManager = try StarManager()
        } catch {
            XCTFail("Failed to initialize StarManager: \(error)")
        }
    }
    
    func testStarQuery() throws {
        let starQuery = starManager.brightestStars()
        XCTAssertEqual(starQuery.count, 299)
    }
    
    func testStarsWithMaximumMagnitude() throws {
        // Test with very low magnitude (should only get very bright stars)
        let veryBrightStars = starManager.stars(maximumMagnitude: 1.0)
        XCTAssertFalse(veryBrightStars.isEmpty)
        XCTAssertTrue(veryBrightStars.count < 50) // Should be much less than 300
        
        // Verify all returned stars meet the magnitude criteria
        for star in veryBrightStars {
            XCTAssertLessThanOrEqual(star.magnitude, 1.0, "Star magnitude \(star.magnitude) exceeds maximum 1.0")
        }
        
        // Verify stars are sorted by magnitude
        for i in 1..<veryBrightStars.count {
            XCTAssertLessThanOrEqual(veryBrightStars[i-1].magnitude, veryBrightStars[i].magnitude, 
                                   "Stars should be sorted by magnitude in ascending order")
        }
    }
    
    func testStarsWithModerateMagnitude() throws {
        // Test with moderate magnitude (should get most of brightest 300)
        let moderateStars = starManager.stars(maximumMagnitude: 5.0)
        XCTAssertFalse(moderateStars.isEmpty)
        
        // Should get a good portion of the brightest 300 stars
        XCTAssertGreaterThan(moderateStars.count, 200)
        
        // Verify all returned stars meet the magnitude criteria
        for star in moderateStars {
            XCTAssertLessThanOrEqual(star.magnitude, 5.0, "Star magnitude \(star.magnitude) exceeds maximum 5.0")
        }
        
        // Verify stars are sorted by magnitude
        for i in 1..<moderateStars.count {
            XCTAssertLessThanOrEqual(moderateStars[i-1].magnitude, moderateStars[i].magnitude, 
                                   "Stars should be sorted by magnitude in ascending order")
        }
    }
    
    func testStarsWithHighMagnitude() throws {
        // Test with high magnitude (should trigger H3 fallback)
        let faintStars = starManager.stars(maximumMagnitude: 8.0)
        XCTAssertFalse(faintStars.isEmpty)
        
        // Should get more stars than just the brightest 300 due to H3 fallback
        XCTAssertGreaterThan(faintStars.count, 300)
        
        // Verify all returned stars meet the magnitude criteria
        for star in faintStars {
            XCTAssertLessThanOrEqual(star.magnitude, 8.0, "Star magnitude \(star.magnitude) exceeds maximum 8.0")
        }
        
        // Verify stars are sorted by magnitude
        for i in 1..<faintStars.count {
            XCTAssertLessThanOrEqual(faintStars[i-1].magnitude, faintStars[i].magnitude, 
                                   "Stars should be sorted by magnitude in ascending order")
        }
    }
    
    func testStarsMaximumMagnitudeNoDuplicates() throws {
        // Test that there are no duplicate stars when combining brightest + H3 levels
        let stars = starManager.stars(maximumMagnitude: 7.0)
        let starIds = stars.map { $0.id }
        let uniqueIds = Set(starIds)
        
        XCTAssertEqual(starIds.count, uniqueIds.count, "Should not have duplicate stars")
    }
    
    func testStarsMaximumMagnitudeComparison() throws {
        // Test that a more restrictive magnitude returns fewer or equal stars
        let stars5 = starManager.stars(maximumMagnitude: 5.0)
        let stars6 = starManager.stars(maximumMagnitude: 6.0)
        
        XCTAssertLessThanOrEqual(stars5.count, stars6.count, 
                               "More restrictive magnitude should return fewer or equal stars")
        
        // Verify that all stars from the more restrictive set are in the less restrictive set
        let stars6Ids = Set(stars6.map { $0.id })
        for star in stars5 {
            XCTAssertTrue(stars6Ids.contains(star.id), 
                         "Star from magnitude 5.0 set should also be in magnitude 6.0 set")
        }
    }
    
    func testClosestStar() throws {
        // Test closestStar function at north pole with different magnitude limits
        // North pole coordinates: (0, 0, 1)
        let northPoleCoordinate = SIMD3<Double>(0, 0, 1)
        
        // Find closest star with magnitude limit of 4.0 (brighter stars only)
        let maybeNorthStar = starManager.closestStar(
            to: northPoleCoordinate,
            maximumMagnitude: 4.0
        )
        
        // Both searches should find stars
        let northStar: Star = try XCTUnwrap(maybeNorthStar, "Should find a star near north pole with magnitude <= 4.0")

        // Verify magnitude constraints are respected
        XCTAssertLessThanOrEqual(northStar.magnitude, 4.0, 
                               "Bright star magnitude should be <= 4.0, got \(northStar.magnitude)")

        let properName = starManager.starInfo(forId: northStar.id)?.properName
        XCTAssertEqual(properName, "Polaris", "Expected star at north pole to be Polaris")
    }
    
    func testClosestStarSouthPole() throws {
        // Test closestStar function at south pole with different magnitude limits
        // South pole coordinates: (0, 0, -1)
        let southPoleCoordinate = SIMD3<Double>(0, 0, -1)
        
        // Find closest star with magnitude limit of 1.0 (very bright stars only)
        let maybeStar1 = starManager.closestStar(
            to: southPoleCoordinate,
            maximumMagnitude: 1.0
        )
        
        // Find closest star with magnitude limit of 5.0 (moderate brightness)
        let maybeStar5 = starManager.closestStar(
            to: southPoleCoordinate,
            maximumMagnitude: 5.0
        )
        
        // Find closest star with magnitude limit of 6.0 (dimmer stars)
        let maybeStar6 = starManager.closestStar(
            to: southPoleCoordinate,
            maximumMagnitude: 8.0
        )
        
        // All searches should find stars
        XCTAssertNil(maybeStar1, "Should not find a star near south pole with magnitude <= 1.0")
        let star5: Star = try XCTUnwrap(maybeStar5, "Should find a star near south pole with magnitude <= 5.0")
        let star6: Star = try XCTUnwrap(maybeStar6, "Should find a star near south pole with magnitude <= 8.0")
        
        // Verify magnitude constraints are respected
        XCTAssertLessThanOrEqual(star5.magnitude, 5.0,
                               "Moderate star magnitude should be <= 5.0, got \(star5.magnitude)")
        XCTAssertLessThanOrEqual(star6.magnitude, 8.0,
                               "Dimmer star magnitude should be <= 8.0, got \(star6.magnitude)")
        
        // Get proper names for context
        let displayName5 = starManager.starInfo(forId: star5.id)?.displayName
        let displayName6 = starManager.starInfo(forId: star6.id)?.displayName
        
        XCTAssertEqual(displayName5, "δ Octantis")
        XCTAssertEqual(displayName6, "HD 99685")

        // Verify that we're getting the closest star for each magnitude limit
        // The star found with a more restrictive magnitude should be at least as bright as more permissive ones
        XCTAssertLessThanOrEqual(star5.magnitude, star6.magnitude, 
                               "Star found with magnitude limit 5.0 should be brighter than or equal to star found with limit 8.0")
    }
}
