![Header](https://github.com/DJBen/SpaceTime/raw/master/External%20Assets/T-Blue.png)

# SpaceTime

[![Language](https://img.shields.io/badge/Swift-4.0-orange.svg?style=flat)](https://swift.org)
[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![Build Status](https://travis-ci.org/DJBen/SpaceTime.svg?branch=master)](https://travis-ci.org/DJBen/SpaceTime)

## Overview

- Astronomy coordinate conversion. Conversion among [equatorial coordinate](https://en.wikipedia.org/wiki/Equatorial_coordinate_system) (right ascension and declination), [horizontal coordinate](https://en.wikipedia.org/wiki/Horizontal_coordinate_system) (azimuth and altitude) and their corresponding Cartesian equivalents
- Calculate [Julian Day](https://en.wikipedia.org/wiki/Julian_day) and [Local sidereal time](https://en.wikipedia.org/wiki/Sidereal_time).
- Matrix / Quaternion transformation from celestial coordinate system to local tangent plane. Supports [North-East-Down](https://en.wikipedia.org/wiki/North_east_down) coordinate from [earth-centered, earth-fixed](https://en.wikipedia.org/wiki/ECEF) coordinate system for any given longitude, latitude and timestamp.

## Demo
You can find a demo project under `SpaceTimeDemo` directory.
It showcases several useful scenarios.

![Screenshot](https://github.com/DJBen/SpaceTime/raw/master/External%20Assets/Screenshot.png)

## Installation

### Carthage

    github "DJBen/SpaceTime" ~> 0.2.0

## Usage
Equatorial to horizontal coordinate:
```swift
// Supply observer location and timestamp
let locTime = ObserverLocationTime(location: location, timestamp: JulianDay.now)
let vegaCoord = EquatorialCoordinate(rightAscension: radians(hours: 18, minutes: 36, seconds: 56.33635), declination: radians(degrees: 38, minutes: 47, seconds: 1.2802), distance: 1)
// Azimuth and altitude of Vega
let vegaAziAlt = HorizontalCoordinate.init(equatorialCoordinate: vegaCoord, observerInfo: locTime)
```
Greenwich Mean Sidereal Time:
```swift
SiderealTime.init(julianDay: JulianDay.now)
```
Local Apparent Sidereal Time:
```swift
// Get location from GPS or hard code
let locTime = ObserverLocationTime(location: location, timestamp: JulianDay.now)
let localSidTime = SiderealTime.init(observerLocationTime: locTime)
```
More use cases can be found in the source.
