//
//  SiderealTime.swift
//  SpaceTime
//
//  Created by Sihao Lu on 1/3/17.
//  Copyright © 2017 Ben Lu. All rights reserved.
//

import Foundation
import CoreLocation
import MathUtil

fileprivate extension JulianDate {
    /// GMST in hours and fraction of an hour
    var greenwichMeanSiderealTime: Double {
        let diff = value - JulianDate.J2000.value
        // magic function comes from
        // https://en.wikipedia.org/wiki/Sidereal_time
        let gmst = 18.697374558 + 24.06570982441908 * diff
        return gmst.truncatingRemainder(dividingBy: 24)
    }
}

public struct SiderealTime: CustomStringConvertible {
    /// Hours with fraction
    public let hour: Double

    public var hourMinuteSecond: (Int, Int, Double) {
        let hour = Int(modf(self.hour).0)
        let min = Int(modf(modf(self.hour).1 * 60).0)
        let sec = modf(modf(modf(self.hour).1 * 60).1 * 60).0
        return (hour, min, sec)
    }

    public var hourAngle: Double {
        return radians(hours: hour)
    }

    public var description: String {
        let (hour, min, sec) = hourMinuteSecond
        return String(format: "%02d:%02d:%02d", hour, min, Int(sec))
    }

    public init(hour: Double) {
        self.hour = hour
    }

    public init(locationAndTime locTime: LocationAndTime) {
        let timeZoneHours = locTime.location.coordinate.longitude / 15
        hour = wrapHour(locTime.timestamp.greenwichMeanSiderealTime + timeZoneHours)
    }

    /// Greenwich mean sidereal time at Julian Date
    public init(julianDate: JulianDate) {
        hour = julianDate.greenwichMeanSiderealTime
    }
}

