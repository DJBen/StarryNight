//
//  SpectralType.swift
//  Orbits
//
//  Created by Ben Lu on 2/11/17.
//  Copyright © 2017 Ben Lu. All rights reserved.
//

import Foundation
import SQLite

public struct SpectralType: CustomStringConvertible {
    public let rawType: String
    public var description: String {
        return rawType
    }

    public let type: String
    public let subType: Double?
    public let luminosityClass: String?

    /// Spectral peculiarities of the star
    ///
    /// seealso: [Stellar Classification](https://en.wikipedia.org/wiki/Stellar_classification)
    public let peculiarities: String?

    private var shortenedSpectralType: String {
        return "\(type)\(subType != nil ? String(subType!) : String())\(luminosityClass ?? String())"
    }

    /// The effective temperature
    public var temperature: Double {
        guard let subType = subType else {
            return 0
        }

        let fractionSubtype = "\(type)\(String(format: "%.1f", subType))%"
        let integerSubtype = "\(type)\(String(Int(subType)))%"
        if let row = try? StarryNight.db.pluck(
            StarryNight.Spectral.table.select(StarryNight.Spectral.temp).where(StarryNight.Spectral.spectralType.like(fractionSubtype))
        ) {
            return row[StarryNight.Spectral.temp] + 273.15
        } else if let row = try? StarryNight.db.pluck(
            StarryNight.Spectral.table.select(StarryNight.Spectral.temp).where(StarryNight.Spectral.spectralType.like(integerSubtype))
        ) {
            return row[StarryNight.Spectral.temp] + 273.15
        }
        // This is rare but may happen
        return 0
    }

}
