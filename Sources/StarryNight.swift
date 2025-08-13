//
//  StarryNight.swift
//  Graviton
//
//  Created by Sihao Lu on 8/12/17.
//  Copyright © 2017 Ben Lu. All rights reserved.
//

import Foundation
@preconcurrency import SQLite

enum StarryNight {
    static let db = try! Connection(Bundle.module.path(forResource: "stars", ofType: "sqlite3")!)

    enum Constellations {
        static let table = Table("constellations")
        static let dbName = Expression<String>("constellation")
        static let dbIAUName = Expression<String>("iau")
        static let dbGenitive = Expression<String>("genitive")
        static let constellationLinePath = Bundle.module.path(forResource: "constellation_lines", ofType: "dat")!
    }

    enum Spectral {
        static let table = Table("spectral")
        static let spectralType = Expression<String>("SpT")
        static let temp = Expression<Double>("Teff")
    }

    enum ConstellationBorders {
        static let table = Table("con_border_simple")
        static let dbBorderCon = Expression<String>("con")
        static let dbLowRa = Expression<Double>("low_ra")
        static let dbHighRa = Expression<Double>("high_ra")
        static let dbLowDec = Expression<Double>("low_dec")
        static let fullBorders = Table("constellation_borders")
        static let dbOppoCon = Expression<String>("opposite_con")
    }
}
