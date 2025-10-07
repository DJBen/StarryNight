import Foundation
import Ch3
@preconcurrency import SQLite

extension StarManager {
    // MARK: - Constellation API
    
    /// Get all constellations
    public func allConstellations() -> Set<Constellation> {
        do {
            var constellations = Set<Constellation>()
            for row in try db.prepare(Tables.constellations) {
                let iau = try row.get(Tables.iau)
                if let center = constellationCenter[iau] {
                    let con = Constellation(
                        id: try row.get(Tables.id),
                        name: try row.get(Tables.constellationName),
                        iAUName: iau,
                        genitive: try row.get(Tables.genitive),
                        center: center
                    )
                    constellations.insert(con)
                }
            }
            return constellations
        } catch {
            print("Error fetching all constellations: \(error)")
            return []
        }
    }
    
    /// Get a constellation by name
    public func constellation(named name: String) -> Constellation? {
        let query = Tables.constellations.select(
            Tables.id,
            Tables.constellationName,
            Tables.iau,
            Tables.genitive
        ).filter(Tables.constellationName == name)
        
        return queryConstellation(query)
    }
    
    /// Get a constellation by IAU abbreviation
    public func constellation(iau: String) -> Constellation? {
        let query = Tables.constellations.select(
            Tables.id,
            Tables.constellationName,
            Tables.iau,
            Tables.genitive
        ).filter(Tables.iau == iau)
        
        return queryConstellation(query)
    }

    /// Get constellation connection lines from the constellation_lines table
    public func constellationLines(for constellation: Constellation) -> [Constellation.Line] {
        // Query the constellation_lines table for this constellation's id
        let linesTable = Table("constellation_lines")
        let dbConstellationId = Expression<Int>("constellation_id")
        let dbStar1Id = Expression<Int>("star1_id")
        let dbStar2Id = Expression<Int>("star2_id")

        var connectionLines: [Constellation.Line] = []
        do {
            for row in try db.prepare(linesTable.filter(dbConstellationId == constellation.id)) {
                let star1Id = try row.get(dbStar1Id)
                let star2Id = try row.get(dbStar2Id)
                if let star1 = star(withId: star1Id), let star2 = star(withId: star2Id) {
                    connectionLines.append(Constellation.Line(star1: star1, star2: star2))
                }
            }
        } catch {
            print("Error fetching constellation lines for \(constellation.iAUName): \(error)")
        }
        return connectionLines
    }

    /// Get border segments that outline the provided constellation
    public func constellationBorders(for constellation: Constellation) -> [Constellation.BorderSegment] {
        let bordersTable = Table("constellation_borders")
        let dbCon = Expression<String>("con")
        let dbOppositeCon = Expression<String?>("opposite_con")
        let dbP1RA = Expression<Double>("p1_ra")
        let dbP1Dec = Expression<Double>("p1_dec")
        let dbP2RA = Expression<Double>("p2_ra")
        let dbP2Dec = Expression<Double>("p2_dec")

        var segments: [Constellation.BorderSegment] = []

        do {
            let iauNames: [String]
            if constellation.iAUName == "Ser" {
                iauNames = ["Ser1", "Ser2"]
            } else {
                iauNames = [constellation.iAUName]
            }

            var query = bordersTable
            if let firstIAU = iauNames.first {
                var predicate = dbCon == firstIAU
                for iau in iauNames.dropFirst() {
                    predicate = predicate || dbCon == iau
                }
                query = query.filter(predicate)
            }

            for row in try db.prepare(query) {
                let startRA = try row.get(dbP1RA)
                let startDec = try row.get(dbP1Dec)
                let endRA = try row.get(dbP2RA)
                let endDec = try row.get(dbP2Dec)
                let startCoordinate = raDecToLatLng(raHours: startRA, decDegrees: startDec)
                let endCoordinate = raDecToLatLng(raHours: endRA, decDegrees: endDec)

                let segment = Constellation.BorderSegment(
                    start: startCoordinate,
                    end: endCoordinate,
                    oppositeConstellationIAU: try row.get(dbOppositeCon)
                )
                segments.append(segment)
            }
        } catch {
            print("Error fetching borders for constellation \(constellation.iAUName): \(error)")
        }

        return segments
    }

    private func raDecToLatLng(raHours: Double, decDegrees: Double) -> LatLng {
        let raRadians = raHours * .pi / 12.0
        let decRadians = decDegrees * .pi / 180.0
        return LatLng(lat: decRadians, lng: normalizeLongitude(raRadians))
    }

    private func normalizeLongitude(_ longitude: Double) -> Double {
        var lon = longitude
        let twoPi = 2.0 * .pi
        lon.formTruncatingRemainder(dividingBy: twoPi)
        if lon <= -.pi {
            lon += twoPi
        } else if lon > .pi {
            lon -= twoPi
        }
        return lon
    }

    /// Get neighboring constellations for a given constellation
    public func neighbors(for constellation: Constellation) -> Set<Constellation> {
        // Define the constellation borders table structure
        let fullBorders = Table("constellation_borders")
        let dbBorderCon = SQLite.Expression<String>("con")
        let dbOppoCon = SQLite.Expression<String>("opposite_con")
        
        var query = fullBorders.select(dbOppoCon)
        if constellation.iAUName == "Ser" {
            query = query.filter(dbBorderCon == "Ser1" || dbBorderCon == "Ser2")
        } else {
            query = query.filter(dbBorderCon == constellation.iAUName)
        }
        
        var constellations: [Constellation] = []
        do {
            for row in try db.prepare(query) {
                let oppoCon = try row.get(dbOppoCon)
                if let neighborConstellation = self.constellation(iau: oppoCon) {
                    constellations.append(neighborConstellation)
                }
            }
        } catch {
            print("Error fetching neighbors for constellation \(constellation.iAUName): \(error)")
        }
        
        return Set<Constellation>(constellations)
    }
    
    // MARK: - Private Constellation Helpers
    
    private func queryConstellation(_ query: QueryType) -> Constellation? {
        do {
            if let row = try db.pluck(query) {
                let iau = try row.get(Tables.iau)
                if let center = constellationCenter[iau] {
                    return Constellation(
                        id: try row.get(Tables.id),
                        name: try row.get(Tables.constellationName),
                        iAUName: iau,
                        genitive: try row.get(Tables.genitive),
                        center: center
                    )
                } else {
                    return nil
                }
            } else {
                return nil
            }
        } catch {
            print("Error querying constellation: \(error)")
            return nil
        }
    }
}

extension StarManager {
    public func displayCenter(for constellation: Constellation) -> SIMD3<Double>? {
        return constellationCenter[constellation.iAUName]
    }

    public func displayCenters(for constellations: [Constellation]) async -> [Constellation: SIMD3<Double>] {
        var result = [Constellation: SIMD3<Double>]()
        for constellation in constellations {
            if constellation.iAUName == "Ser1" || constellation.iAUName == "Ser2" || constellation.iAUName == "Ser" {
                if let ser1 = self.constellation(iau: "Ser1"), let ser1Center = constellationCenter["Ser1"] {
                    result[ser1] = ser1Center
                }
                if let ser2 = self.constellation(iau: "Ser2"), let ser2Center = constellationCenter["Ser2"] {
                    result[ser2] = ser2Center
                }
            } else {
                if let center = constellationCenter[constellation.iAUName] {
                    result[constellation] = center
                }
            }
        }
        return result
    }
}
