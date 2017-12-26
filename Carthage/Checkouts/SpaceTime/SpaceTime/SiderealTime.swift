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

fileprivate extension JulianDay {
    /// GMST in hours and fraction of an hour
    var greenwichMeanSiderealTime: Double {
        let diff = value - JulianDay.J2000.value
        // magic function comes from
        // https://en.wikipedia.org/wiki/Sidereal_time
        let gmst = 18.697374558 + 24.06570982441908 * diff
        return gmst.truncatingRemainder(dividingBy: 24)
    }
}

public struct SiderealTime: CustomStringConvertible {
    private var offsetHours: Double = 0

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

    public var offsetFromGreenwichMeanSiderealTime: SiderealTimeOffset {
        return SiderealTimeOffset(hour: offsetHours)
    }

    public var description: String {
        let (hour, min, sec) = hourMinuteSecond
        return String(format: "%02d:%02d:%02d", hour, min, Int(sec))
    }

    public init(hour: Double) {
        self.hour = hour
    }

    public init(observerLocationTime locTime: ObserverLocationTime) {
        offsetHours = locTime.location.coordinate.longitude / 15
        hour = wrapHour(locTime.timestamp.greenwichMeanSiderealTime + offsetHours)
    }

    /// Greenwich mean sidereal time at Julian Date
    public init(julianDay: JulianDay) {
        hour = julianDay.greenwichMeanSiderealTime
    }
}

public struct SiderealTimeOffset: CustomStringConvertible {
    /// Hours with fraction
    public let hour: Double

    public var signHourMinuteSecond: (Int, Int, Int, Double) {
        let sign = self.hour >= 0 ? 1 : -1
        let posHour = abs(self.hour)
        let hour = Int(modf(posHour).0)
        let min = Int(modf(modf(posHour).1 * 60).0)
        let sec = modf(modf(modf(posHour).1 * 60).1 * 60).0
        return (sign, hour, min, sec)
    }

    public var description: String {
        let (sign, hour, min, sec) = signHourMinuteSecond
        return String(format: "\(sign == 1 ? "+" : "-")%02d:%02d:%02d", hour, min, Int(sec))
    }

    public init(hour: Double) {
        self.hour = hour
    }
}
