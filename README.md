![Header image](https://github.com/DJBen/StarryNight/raw/master/External%20Assets/S-Green.png)

# StarryNight
[![Language](https://img.shields.io/badge/Swift-4.0-orange.svg?style=flat)](https://swift.org)
[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](http://www.gnu.org/licenses/gpl-3.0)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

## Overview
_StarryNight is all you need for curiosity towards stars and constellations._

- Database of 15000+ stars within 7th magnitude.
  - [Star Catalogs](https://en.wikipedia.org/wiki/Star_catalogue) including HR, HD, HIP, [Gould](https://en.wikipedia.org/wiki/Gould_designation) and [Bayer](https://en.wikipedia.org/wiki/Bayer_designation)-[Flamsteed](https://en.wikipedia.org/wiki/Flamsteed_designation) designations.
  - Celestial coordinate and proper motion.
  - Visual and absolute magnitude, luminance, spectral type, binary star info, and other physical properties.
- Extended Constellation support.
  - Position query and inverse position query.
  - Constellation line and constellation border.
  - Abbreviation, genitive and etymology.

## Installation

### Carthage

    github "DJBen/StarryNight" ~> 0.1.0

## Usage

### Stars

1. All stars brighter than...

```swift
Star.magitudeLessThan(7)
```
2. Star with specific designation.

```swift
Star.hr(9077)
Star.hd(224750)
Star.hip(25)
```
3. Star closest to specific celestial coordinate
This is very useful to locate the closest star to user input.

```swift
let coord = Vector3.init(equatorialCoordinate: EquatorialCoordinate.init(rightAscension: radians(hours: 5, minutes: 20), declination: radians(degrees: 10), distance: 1)).normalized()
Star.closest(to: coord, maximumMagnitude: 2.5)
// Bellatrix
```

### Constellations

1. Constellation with name or [IAU symbol](https://www.iau.org/public/themes/constellations/).
```swift
Constellation.iau("Tau")
Constellation.named("Orion")
```
2. Constellation that contains specific celestial coordinate.
This is very useful to locate the constellation that contains the region of user input.

  It is implemented as a category on `EquatorialCoordinate`. See [SpaceTime](https://github.com/DJBen/SpaceTime) repo for implementation and usage of coordinate classes.

```swift
let coord = EquatorialCoordinate.init(rightAscension: 1.547, declination: 0.129, distance: 1)
coord.constellation
// Orion
```

3. Neighboring constellations and centers.

```swift
// Get a set of neighboring constellations
Constellation.iau("Ori").neighbors
// Get the coordinate of center(s) of current constellation
Constellation.iau("Ori").displayCenters
```

  *Note*: `displayCenters` returns an array of one element for all constellations except Serpens, which will include two elements - one center for Serpens Caput and the other for Serpens Cauda.

## Remarks
Data extracted from [HYG database](https://github.com/astronexus/HYG-Database) and processed into SQLite. The star catalog has been trimmed to 7th magnitude to reduce file size. Feel free to download the full catalog and import into SQLite whenever you see fit.
