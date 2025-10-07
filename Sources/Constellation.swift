//
//  Constellation.swift
//  Orbits
//
//  Created by Ben Lu on 2/3/17.
//  Copyright © 2017 Ben Lu. All rights reserved.
//

import Foundation
import Ch3

public struct Constellation: Hashable, Identifiable, @unchecked Sendable {
    public struct Line: CustomStringConvertible, Sendable {
        public let star1: Star
        public let star2: Star

        public var description: String {
            return "(\(star1) - \(star2))"
        }
        
        public init(star1: Star, star2: Star) {
            self.star1 = star1
            self.star2 = star2
        }
    }

    public struct BorderSegment: Hashable, Sendable {
        /// Start of the border segment in equatorial coordinates (Dec, RA) in radians.
        public let start: LatLng
        /// End of the border segment in equatorial coordinates (Dec, RA) in radians.
        public let end: LatLng
        /// Opposite side constellation IAU abbreviation, if the dataset specifies one.
        public let oppositeConstellationIAU: String?

        public init(start: LatLng, end: LatLng, oppositeConstellationIAU: String?) {
            self.start = start
            self.end = end
            self.oppositeConstellationIAU = oppositeConstellationIAU
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(iAUName)
    }

    public static func ==(lhs: Constellation, rhs: Constellation) -> Bool {
        return lhs.iAUName == rhs.iAUName
    }

    public let id: Int
    public let name: String
    public let iAUName: String
    public let genitive: String
    /// A unit vector pointing to the center of the constellation
    public let center: SIMD3<Double>

    public var localizedName: String {
        return NSLocalizedString(name, bundle: .module, comment: "")
    }

    public init(
        id: Int,
        name: String,
        iAUName: String,
        genitive: String,
        center: SIMD3<Double>
    ) {
        self.id = id
        self.name = name
        self.iAUName = iAUName
        self.genitive = genitive
        self.center = center
    }
}
