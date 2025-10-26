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
}
