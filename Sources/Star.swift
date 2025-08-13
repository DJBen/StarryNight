//
//  Star.swift
//  Orbits
//
//  Created by Ben Lu on 2/1/17.
//  Copyright © 2017 Ben Lu. All rights reserved.
//

import Foundation
import SQLite

/// Core star data structure containing essential rendering information
public struct Star: Hashable, Equatable, @unchecked Sendable {
    /// Unique identifier for the star
    public let id: Int
    /// The star's apparent magnitude
    public let magnitude: Double
    /// The Cartesian coordinates of the star, in a system based on the equatorial coordinates as seen from Earth. 
    /// +X is in the direction of the vernal equinox (at epoch 2000), +Z towards the north celestial pole, 
    /// and +Y in the direction of R.A. 6 hours, declination 0 degrees.
    public let coordinate: SIMD3<Double>
    /// The star's spectral class (simplified from spectral type)
    public let spectralClass: String?
    /// Optional detailed information about the star (loaded on demand)
    public var info: StarInfo?
    
    public init(id: Int, magnitude: Double, coordinate: SIMD3<Double>, spectralClass: String?, info: StarInfo? = nil) {
        self.id = id
        self.magnitude = magnitude
        self.coordinate = coordinate
        self.spectralClass = spectralClass
        self.info = info
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func ==(lhs: Star, rhs: Star) -> Bool {
        return lhs.id == rhs.id
    }

    /// Load detailed information for this star
    public mutating func loadInfo(starManager: StarManager) {
        self.info = starManager.starInfo(forId: id)
    }
    
    /// Create a new star with detailed information loaded
    public func withInfo(starManager: StarManager) -> Star {
        var star = self
        star.loadInfo(starManager: starManager)
        return star
    }
}

/// Detailed star information from the stars_info table
public struct StarInfo: Hashable, Equatable, Sendable {
    /// The star's ID in the Hipparcos catalog, if known.
    public let hipId: Int?
    /// The star's ID in the Henry Draper catalog, if known.
    public let hdId: Int?
    /// The star's ID in the Harvard Revised catalog, which is the same as its number in the Yale Bright Star Catalog.
    public let hrId: Int?
    /// Gliese catalog identifier
    public let gl: String?
    /// The Bayer / Flamsteed designation
    public let bfDesignation: BayerFlamsteed?
    /// A common name for the star, such as "Barnard's Star" or "Sirius"
    public let properName: String?
    /// The star's absolute magnitude
    public let absoluteMagnitude: Double?
    /// Raw spectral type in string
    public let spectralType: String?
    /// Color index
    public let colorIndex: Double?
    /// Bayer designation
    public let bayer: String?
    /// Flamsteed number
    public let flamsteed: Int?
    /// The constellation this star belongs to
    public let constellation: Constellation?
    /// Component information
    public let component: Int?
    /// Primary component ID
    public let componentPrimary: Int?
    /// Base catalog name
    public let base: String?
    /// The star's luminosity
    public let luminosity: Double?
    /// Variable star designation
    public let variableDesignation: String?
    /// Minimum magnitude for variable stars
    public let variableMin: Double?
    /// Maximum magnitude for variable stars
    public let variableMax: Double?
    
    public init(hipId: Int?, hdId: Int?, hrId: Int?, gl: String?, bfDesignation: BayerFlamsteed?, 
                properName: String?, absoluteMagnitude: Double?, spectralType: String?, 
                colorIndex: Double?, bayer: String?, flamsteed: Int?, constellation: Constellation?,
                component: Int?, componentPrimary: Int?, base: String?, luminosity: Double?,
                variableDesignation: String?, variableMin: Double?, variableMax: Double?) {
        self.hipId = hipId
        self.hdId = hdId
        self.hrId = hrId
        self.gl = nilIfEmpty(gl)
        self.bfDesignation = bfDesignation
        self.properName = nilIfEmpty(properName)
        self.absoluteMagnitude = absoluteMagnitude
        self.spectralType = nilIfEmpty(spectralType)
        self.colorIndex = colorIndex
        self.bayer = nilIfEmpty(bayer)
        self.flamsteed = flamsteed
        self.constellation = constellation
        self.component = component
        self.componentPrimary = componentPrimary
        self.base = nilIfEmpty(base)
        self.luminosity = luminosity
        self.variableDesignation = nilIfEmpty(variableDesignation)
        self.variableMin = variableMin
        self.variableMax = variableMax
    }
    
    /// Computed properties for display names
    public var hrIdString: String? {
        return hrId != nil ? "HR \(hrId!)" : nil
    }
    
    public var hipIdString: String? {
        return hipId != nil ? "HIP \(hipId!)" : nil
    }
    
    public var hdIdString: String? {
        return hdId != nil ? "HD \(hdId!)" : nil
    }
    
    public var bayerFlamsteedDesignation: String? {
        return bfDesignation?.description
    }
    
    public var displayName: String? {
        let bfDesignation = bayerFlamsteedDesignation
        return properName ?? bfDesignation ?? gl ?? hrIdString ?? hdIdString ?? hipIdString
    }
    
    /// Parse Constellation enum from the constellation property
    public var constellationEnum: Constellation? {
        return constellation
    }
    
    /// Check if this is a variable star
    public var isVariable: Bool {
        return variableDesignation != nil
    }
}

private func nilIfEmpty(_ name: String?) -> String? {
    if let str = name {
        return str.trimmingCharacters(in: .whitespacesAndNewlines) == "" ? nil : str
    }
    return nil
}
