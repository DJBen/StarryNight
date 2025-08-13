//
//  BayerFlamsteed.swift
//  Graviton
//
//  Created by Ben Lu on 6/29/17.
//  Copyright © 2017 Ben Lu. All rights reserved.
//

import Foundation

// superscripts from 1 to 9
private let superscripts = ["", "\u{00b9}", "\u{00b2}", "\u{00b3}", "\u{2074}", "\u{2075}", "\u{2076}", "\u{2077}", "\u{2078}", "\u{2079}"]

public struct BayerFlamsteed: CustomStringConvertible, Hashable, Equatable, Sendable {
    public enum DesignationType: Sendable {
        case bayer
        case flamsteed
        case bayerFlamsteed
    }

    public var description: String {
        switch type {
        case .bayer:
            return "\(greekLetter!) \(constellation.genitive)"
        case .flamsteed:
            return "\(flamsteed!)\(superscriptedBinaryNumber) \(constellation.genitive)"
        case .bayerFlamsteed:
            return "\(flamsteed!) \(greekLetter!)\(superscriptedBinaryNumber) \(constellation.genitive)"
        }
    }

    public var superscriptedBinaryNumber: String {
        if let num = binaryNumber {
            return superscripts[num]
        } else {
            return ""
        }
    }

    public let type: DesignationType
    public let flamsteed: Int?
    public let greekLetter: GreekLetter?
    public let binaryNumber: Int?
    public let constellation: Constellation

    public init?(bayer: String?, flamsteed: Int?, constellation: Constellation) {
        self.constellation = constellation
        self.flamsteed = flamsteed
        let bayerPattern = #/(\w+)(?:-(\d+))?/#
        if let match = bayer?.firstMatch(of: bayerPattern) {
            self.greekLetter = GreekLetter(shortEnglish: String(match.1))
            self.binaryNumber = match.2.flatMap({ Int($0) })
            self.type = flamsteed == nil ? .bayer : .bayerFlamsteed
        } else if flamsteed != nil {
            self.greekLetter = nil
            self.binaryNumber = nil
            self.type = .flamsteed
        } else {
            return nil
        }
    }
}

// http://www.unicode.org/charts/PDF/U0370.pdf
public struct GreekLetter: CustomStringConvertible, Hashable, Equatable, Sendable {
    private static let greekAlphabetEnglish = [
        "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "omikron", "pi", "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega"
    ]

    private static func indexFromShortEnglish(_ english: String) -> Int? {
        let threeOrEnd = min(english.lengthOfBytes(using: .utf8), 3)
        let threeLetter = english.lowercased()[..<english.index(english.startIndex, offsetBy: threeOrEnd)]
        guard let index = greekAlphabetEnglish.firstIndex(where: { (string) -> Bool in
            let threeOrEnd = min(string.lengthOfBytes(using: .utf8), 3)
            return string[..<string.index(string.startIndex, offsetBy: threeOrEnd)] == threeLetter
        }) else {
            return nil
        }
        return index
    }

    public static func at(index: Int) -> String {
        // eliminate out-of-bound error
        _ = greekAlphabetEnglish[index]
        var rawValue = UnicodeScalar("α").value + UInt32(index)
        // offset duplicate sigmas
        if rawValue >= UnicodeScalar("ς").value {
            rawValue += 1
        }
        var str = ""
        str.unicodeScalars.append(UnicodeScalar(rawValue)!)
        return str
    }

    public let index: Int

    public init(index: Int) {
        self.index = index
    }

    public init?(shortEnglish: String) {
        if let index = GreekLetter.indexFromShortEnglish(shortEnglish) {
            self.index = index
        } else {
            return nil
        }
    }

    public var description: String {
        return GreekLetter.at(index: self.index)
    }
}
