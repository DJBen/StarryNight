# MathUtil

[![Language](https://img.shields.io/badge/Swift-4.0-orange.svg?style=flat)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![Build Status](https://travis-ci.org/DJBen/MathUtil.svg?branch=master)](https://travis-ci.org/DJBen/MathUtil)

## Overview

- Strongly typed radian, degree and hour angle classes and conversions.
- 3x3 matrix, 4x4 matrix and quaternion support.
  - Conversion between matrix, quaternion, Euler angle, and axis and rotation.
  - Matrix, quaternion multiplication, inversion and scalar multiplication.
  - Overloaded multiplication and division operators in contexts of matrix and quaternion.
- Interpolation support for linear, quadratic and cubic curves with ease-in, ease-out, ease-in-out modes.
- Detect whether two line segments cross each other.
- Operator overloading for `SCNVector3` and more.

## Installation

### Carthage

    # Swift 4.0
    github "DJBen/MathUtil" ~> 0.3.0

This version is compatible with Swift 4. To use Swift 3.x compatible version, use `0.1.x` instead.

    # Swift 3.x
    github "DJBen/MathUtil" ~> 0.1.0


## Usage

### Strongly Typed Angles
#### Radian-degree Angle Conversion
```swift
RadianAngle(degreeAngle: DegreeAngle(30)).value // 0.523...
DegreeAngle(radianAngle: RadianAngle(Double.Pi / 2)).value  // 90
```
#### Hour Angle Conversion and Formatting
```swift
// Sirius' right ascension is 6h 45m 9s
let deg = DegreeAngle(hour: 6, minute: 45, second: 9)
deg.value // 101.2875

let hourAngle = HourAngle(value: deg)
// Use any custom number formatters for different decimal lengths
hourAngle.compoundDecimalNumberFormatter = NumberFormatter()
print(hourAngle.compoundDescription) // 6h 45m 9s

// Antares' right ascension is −26.432002 degrees
let degreeAngle = DegreeAngle(-26.432002)
print(degreeAngle.compoundDescription) // -26° 25′ 55″
```

### Matrix, Quaternion and Vector Arithmetics

See documentation for [VectorMath](https://github.com/nicklockwood/VectorMath).

### Interpolations

#### Linear interpolation
```swift
// Starts at 2.1; ends at 7.5; wants to know 85% value.
let interp = Easing(startValue: 2.1, endValue: 7.5)
interp.value(at: 0.85)   // 6.69
```
#### Quadratic, Cubic, Ease In, Ease Out

The following easing functions are available and [here](http://gizma.com/easing/) is their mathematic definitions.
```swift
public enum EasingFunction {
    case linear
    case quadraticEaseIn
    case quadraticEaseOut
    case quadraticEaseInOut
    case cubicEaseIn
    case cubicEaseOut
    case cubicEaseInOut
}
```
Just pass in the function when initializing `Easing` and take advantage of it!
```swift
Easing(easingMethod: .cubicEaseInOut, startValue: 21, endValue: -9)
```
### Operator overloading

- Add operator arithmetics for `CGVector` and `SCNVector3`.

## Remarks

`MathUtil/VectorMath**` are based on
[@nicklockwood](https://github.com/nicklockwood)'s [VectorMath](https://github.com/nicklockwood/VectorMath). Great thanks!
  - Based on 0.3 version. Not bumping up to the latest release because I adopted a different order of deriving Euler angles from Quaternion and vice versa.
