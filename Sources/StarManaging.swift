//
//  StarManaging.swift
//  StarryNight
//
//  Created by GitHub Copilot on 8/6/25.
//

import Foundation
import SatelliteKit

/// Protocol defining the star management interface
public protocol StarManaging: Sendable {
    
    /// Get the brightest stars
    func brightestStars() -> [Star]
    
    /// Get stars up to a maximum magnitude, starting with brightest stars and falling back to more H3 resolution levels if needed
    func stars(maximumMagnitude: Double) -> [Star]
        
    /// Get stars for a specific H3 resolution level
    func stars(forH3Level level: Int, maximumMagnitude magCutoff: Double?) -> [Star]
    
    /// Get stars within a specific H3 cell
    func stars(inH3Cell h3Index: String, level: Int, maximumMagnitude magCutoff: Double?) -> [Star]
    
    /// Get stars within a rectangular viewport defined by four lat/lon vertices
    /// Always includes all brightest 300 stars plus stars from appropriate H3 cells
    func stars(inViewport vertices: [(latitude: Double, longitude: Double)], maximumMagnitude magCutoff: Double?) -> [Star]
    
    /// Find the closest star to a given cartesian coordinate
    func closestStar(to coordinate: Vector, maximumMagnitude magCutoff: Double?, maximumAngularDistance angularDistance: Double?) -> Star?
    
    /// Search for stars by name or catalog identifier
    func searchStars(matching name: String) -> [Star]
    
    /// Get a specific star by ID
    func star(withId id: Int) -> Star?
    
    /// Get detailed information for a star
    func starInfo(forId id: Int) -> StarInfo?
    
    /// Get star with detailed information loaded
    func starWithInfo(id: Int) -> Star?
    
    // MARK: - Constellation API
    
    /// Get all constellations
    func allConstellations() -> Set<Constellation>
    
    /// Get a constellation by name
    func constellation(named name: String) -> Constellation?
    
    /// Get a constellation by IAU abbreviation
    func constellation(iau: String) -> Constellation?
    
    /// Get constellation connection lines
    func constellationLines(for constellation: Constellation) -> [Constellation.Line]
    
    /// Get neighboring constellations for a given constellation
    func neighbors(for constellation: Constellation) -> Set<Constellation>
}
