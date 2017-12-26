//
//  ViewController.swift
//  SpaceTimeDemo
//
//  Created by Sihao Lu on 7/23/17.
//  Copyright © 2017 Sihao. All rights reserved.
//

import UIKit
import SpaceTime
import CoreLocation
import MathUtil

let julianDayFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 5
    return formatter
}()

let coordinateFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 2
    return formatter
}()

let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    formatter.timeZone = TimeZone(secondsFromGMT: 0)!
    return formatter
}()

// Hint: http://heavens-above.com/whattime.aspx?lat=37.323&lng=-122.0322&loc=Cupertino&alt=72&tz=PST
// is a good site to verify the result if set location in simulator to "Apple"
class ViewController: UIViewController, CLLocationManagerDelegate {

    @IBOutlet var julianDayLabel: UILabel!
    @IBOutlet var utcDateLabel: UILabel!
    @IBOutlet var currentCoordinateLabel: UILabel!
    @IBOutlet var lstLabel: UILabel!
    @IBOutlet var vegaLabel: UILabel!

    lazy var locationManager = CLLocationManager()

    let vegaCoord = EquatorialCoordinate(rightAscension: radians(hours: 18, minutes: 36, seconds: 56.33635), declination: radians(degrees: 38, minutes: 47, seconds: 1.2802), distance: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        let displayLink = CADisplayLink(target: self, selector: #selector(screenUpdate))
        displayLink.add(to: .main, forMode: .defaultRunLoopMode)

        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }

    @objc func screenUpdate() {
        let date = Date()
        let jdValue = JulianDay(date: date).value as NSNumber
        julianDayLabel.text = "Current Julian Date: \(julianDayFormatter.string(from: jdValue)!)"
        utcDateLabel.text = "Current UTC Date: \(dateFormatter.string(from: date))"
        if let location = locationManager.location {
            let locTime = ObserverLocationTime(location: location, timestamp: JulianDay(date: date))
            let sidTime = SiderealTime.init(observerLocationTime: locTime)
            lstLabel.text = "Local Sidereal Time: \(String(describing: sidTime))"
            let vegaAziAlt = HorizontalCoordinate.init(equatorialCoordinate: vegaCoord, observerInfo: locTime)
            vegaLabel.text = "Vega: (Altitude: \(coordinateFormatter.string(from: degrees(radians: vegaAziAlt.altitude) as NSNumber)!), Azimuth: \(coordinateFormatter.string(from: degrees(radians: vegaAziAlt.azimuth) as NSNumber)!))\nAbove horizon? \(vegaAziAlt.altitude > 0 ? "Yes" : "No")"
        }
    }

    // MARK: Location manager
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        guard status != .authorizedWhenInUse || status != .authorizedAlways else {
            return
        }
        locationManager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last!
        currentCoordinateLabel.text = "Lat: " + coordinateFormatter.string(from: location.coordinate.latitude as NSNumber)! + ", Lon: " + coordinateFormatter.string(from: location.coordinate.longitude as NSNumber)!
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print(error)
    }
}

