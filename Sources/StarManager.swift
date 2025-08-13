//
//  StarManager.swift
//  StarryNight
//
//  Created by GitHub Copilot on 8/1/25.
//

import Foundation
import SatelliteKit
@preconcurrency import SQLite
import Ch3

/// Star database manager responsible for all star-related I/O operations
public class StarManager: StarManaging, @unchecked Sendable {
    let db: Connection
    
    // Table definitions
    struct Tables {
        static let starsBrightest300 = Table("stars_brightest_300")
        static let starsH3_0 = Table("stars_h3_0")
        static let starsH3_1 = Table("stars_h3_1")
        static let starsH3_2 = Table("stars_h3_2")
        static let starsInfo = Table("stars_info")
        
        // Constellation table
        static let constellations = Table("constellations")
        
        // Common columns for star tables
        static let id = SQLite.Expression<Int>("id")
        static let mag = SQLite.Expression<Double>("mag")
        static let x = SQLite.Expression<Double>("x")
        static let y = SQLite.Expression<Double>("y")
        static let z = SQLite.Expression<Double>("z")
        static let spectClass = SQLite.Expression<String?>("spect_class")
        
        // H3 columns
        static let h3_0 = SQLite.Expression<String>("h3_0")
        static let h3_1 = SQLite.Expression<String>("h3_1")
        static let h3_2 = SQLite.Expression<String>("h3_2")
        
        // Stars info columns
        static let hip = SQLite.Expression<Int?>("hip")
        static let hd = SQLite.Expression<Int?>("hd")
        static let hr = SQLite.Expression<Int?>("hr")
        static let gl = SQLite.Expression<String?>("gl")
        static let bf = SQLite.Expression<String?>("bf")
        static let proper = SQLite.Expression<String?>("proper")
        static let absmag = SQLite.Expression<Double?>("absmag")
        static let spect = SQLite.Expression<String?>("spect")
        static let ci = SQLite.Expression<Double?>("ci")
        static let bayer = SQLite.Expression<String?>("bayer")
        static let flam = SQLite.Expression<Int?>("flam")
        static let con = SQLite.Expression<String?>("con")
        static let comp = SQLite.Expression<Int?>("comp")
        static let compPrimary = SQLite.Expression<Int?>("comp_primary")
        static let base = SQLite.Expression<String?>("base")
        static let lum = SQLite.Expression<Double?>("lum")
        static let varDesig = SQLite.Expression<String?>("var")
        static let varMin = SQLite.Expression<Double?>("var_min")
        static let varMax = SQLite.Expression<Double?>("var_max")
        
        // Constellation columns
        static let constellationId = SQLite.Expression<Int>("id")
        static let constellationName = SQLite.Expression<String>("constellation")
        static let iau = SQLite.Expression<String>("iau")
        static let genitive = SQLite.Expression<String>("genitive")
    }

    let constellationCenter: [String: Vector] = [
        "Peg": Vector(0.86804042300030027, -0.26298778535788447, 0.33323259346164735),
        "Sex": Vector(-0.88261544888599275, 0.45798408225176818, -0.052864117997383893),
        "Cam": Vector(0.11063, 0.279104, 0.953867),
        "Hyi": Vector(0.26639540590627081, 0.18134529327579627, -0.93651974145366979),
        "Gem": Vector(-0.23881758244994242, 0.86653510813400614, 0.40920801776655763),
        "CMi": Vector(-0.39270090390813028, 0.91134208348527823, 0.11761928283425191),
        "PsA": Vector(0.77846164114146021, -0.34874792710632807, -0.51100051411291181),
        "Crt": Vector(-0.94557181578816829, 0.135809271221908, -0.27864013116882502),
        "Cyg": Vector(0.4225643876580617, -0.63608045391797319, 0.61954945653798166),
        "Cir": Vector(-0.32682695126716915, -0.35475605324807202, -0.87384563673970239),
        "Crv": Vector(-0.92783457616989706, -0.08031576433449146, -0.35714238865979198),
        "Pyx": Vector(-0.55745961748280959, 0.63627271939524954, -0.53011171117435385),
        "Cas": Vector(0.47617677658313839, 0.12623280323716718, 0.86585893416924586),
        "Lib": Vector(-0.58086743029250609, -0.72443921934044941, -0.33967879074289281),
        "Col": Vector(0.018404999745263988, 0.80542361017001585, -0.58581431355748048),
        "Cru": Vector(-0.49970639370620917, -0.066148272394197336, -0.86243354655587856),
        "Dor": Vector(0.11691800788786628, 0.48944778629630831, -0.85591718674255579),
        "Men": Vector(0.04222887673016993, 0.26426687371477192, -0.96236243608939565),
        "Oct": Vector(0.077787162737562435, -0.079178572944494485, -0.98616216286919423),
        "Sge": Vector(0.42610586953418789, -0.84730223265091231, 0.31527606584112078),
        "UMi": Vector(-0.095144015968792267, -0.14346834101846234, 0.97818780455823351),
        "Leo": Vector(-0.87533016475842496, 0.33276405943563309, 0.28350338354308335),
        "Cha": Vector(-0.16338256334915821, 0.073724898581954912, -0.9808513796174918),
        "Eri": Vector(0.49328317552112627, 0.68237294477010912, -0.42386882156986444),
        "Com": Vector(-0.87497892335674798, -0.22088837501506442, 0.41413057169087669),
        "Aps": Vector(-0.091518765404656033, -0.17198507003082142, -0.98000522957495195),
        "Mus": Vector(-0.34897097628625406, -0.044086364803255819, -0.93470861147428197),
        "Mic": Vector(0.59692419506031769, -0.56049224400299347, -0.56893673957458546),
        "Sgr": Vector(0.24881361381887032, -0.82143222285105311, -0.47929096395562237),
        "Sco": Vector(-0.24036624272522861, -0.77862391805863429, -0.54782947525435177),
        "Vul": Vector(0.3602492700555322, -0.84166760216010317, 0.39667912605287253),
        "Oph": Vector(-0.28104236370267205, -0.93665171109795708, -0.013254963959829801),
        "Aql": Vector(0.3974519805288626, -0.90247561072278748, 0.062441847045285798),
        "Ret": Vector(0.22790518424621328, 0.40899916830909333, -0.88275675003677434),
        "Pic": Vector(-0.012875956350727275, 0.54789853193763005, -0.83033452813100261),
        "LMi": Vector(-0.75004131277790254, 0.31202547384880625, 0.57903121983596295),
        "And": Vector(0.75812795337370564, 0.10320366339614294, 0.61191709261301763),
        "Cet": Vector(0.81584232532265821, 0.50956782033079739, -0.075110461113053278),
        "Lyn": Vector(-0.39797444556225064, 0.54103645933114186, 0.7003518816288683),
        "Nor": Vector(-0.28521211922812334, -0.59028120479276802, -0.75434761136979533),
        "Car": Vector(-0.30585060250591772, 0.3268995326007445, -0.8695147277901224),
        "Lup": Vector(-0.4541208548779293, -0.5772829959370207, -0.66716150990113188),
        "Lac": Vector(0.63755830690949045, -0.27918000975619273, 0.71313252671996097),
        "Del": Vector(0.62185101613822868, -0.74060322163401826, 0.25198968062135474),
        "Ori": Vector(0.13771156499400863, 0.96480562691188454, 0.1244937448664947),
        "Pup": Vector(-0.31293787630745373, 0.7353022391824795, -0.57192243188595904),
        "Cnc": Vector(-0.61161237036555094, 0.71761049391844201, 0.30476419984475117),
        "Sct": Vector(0.14497329659731623, -0.97404144254830216, -0.15823912695298492),
        "Phe": Vector(0.63433307501886838, 0.15779654048000372, -0.7462277756154202),
        "Equ": Vector(0.74634443234478642, -0.64936212329815346, 0.13993466425716175),
        "Tri": Vector(0.71455134043747426, 0.43969882725299558, 0.54133174908858839),
        "Ara": Vector(-0.09375688731551006, -0.56028252271949686, -0.81844745317771583),
        "Hor": Vector(0.38934110234113511, 0.45190267836270465, -0.78406193089185194),
        "Lyr": Vector(0.17248251092664749, -0.79060840725959491, 0.58540445777379735),
        "Cae": Vector(0.26244102936178937, 0.70223249104890828, -0.659240577129517),
        "Mon": Vector(-0.23781724490187517, 0.95190121418897899, -0.026065293550590264),
        "TrA": Vector(-0.20287964635797204, -0.33158906869536625, -0.91887286188047534),
        "Tuc": Vector(0.44023184429970869, -0.062818620392249516, -0.88852307687959986),
        "Psc": Vector(0.93469644835286747, 0.13019690199690626, 0.16505089514641494),
        "Ser1": Vector(-0.48920514402661436, -0.83631913751724163, 0.11724416081838872),
        "Cap": Vector(0.67374742427606538, -0.64870018276547048, -0.32039853382729666),
        "Cep": Vector(0.33600395951531536, -0.17700034129250869, 0.91447081549243447),
        "Per": Vector(0.42884979345206176, 0.58061553301979785, 0.67822987690068093),
        "Cen": Vector(-0.58512528913652528, -0.21400562327014805, -0.74966477387102426),
        "Gru": Vector(0.64956012147206732, -0.25254432716375286, -0.70757037414595969),
        "Aur": Vector(0.12883748171767423, 0.75261111581312978, 0.63313216988613574),
        "For": Vector(0.6521274473219022, 0.5563030171326786, -0.50328944359465999),
        "CMa": Vector(-0.22098925030592428, 0.89646308755532145, -0.36646562842786556),
        "Ari": Vector(0.7296030480596386, 0.55594375347584157, 0.37387962612410391),
        "Her": Vector(-0.1632858505096674, -0.79484767742545948, 0.55456475750867162),
        "Aqr": Vector(0.90779328919167879, -0.35416447239437121, -0.13937290564995652),
        "Pav": Vector(0.14841227195525375, -0.37112075078531487, -0.90424710489329541),
        "Vir": Vector(-0.90501939565942546, -0.34681740910094244, -0.016700498553693849),
        "Ser2": Vector(-0.000781087585124618, -0.97074919088591327, -0.1376010392042204),
        "Ind": Vector(0.43966652977731407, -0.37376894861941962, -0.81041425218849561),
        "Lep": Vector(0.12102965190965533, 0.94079725493569022, -0.3034622309696397),
        "Boo": Vector(-0.60266971535349445, -0.48837141139239826, 0.59989033377650869),
        "Vol": Vector(-0.17835261040489522, 0.30967925442444, -0.93097087185523808),
        "Ant": Vector(-0.73220185399248083, 0.38599825269258192, -0.54319960568167602),
        "Scl": Vector(0.83451936946184824, -0.016437167627518783, -0.5281660771341059),
        "UMa": Vector(-0.56387764388304273, 0.15715643323339293, 0.7631774300132218),
        "Tau": Vector(0.3703397692341413, 0.85387292534653636, 0.31162533325235048),
        "Tel": Vector(0.065954486070631049, -0.67819788760642907, -0.73108716335566204),
        "CrB": Vector(-0.49301880533198444, -0.73008445499051289, 0.46980789515957122),
        "Hya": Vector(-0.76844946579107154, 0.4303754584292282, -0.1507631464437604),
        "CrA": Vector(0.22059225097213406, -0.74462295212656826, -0.62900922127556447),
        "CVn": Vector(-0.75186515378595253, -0.15000516907410011, 0.64039289719473502),
        "Vel": Vector(-0.51579340714970356, 0.41024740599943554, -0.73249965556620511),
        "Dra": Vector(-0.12170666485642134, -0.33995596778538167, 0.89187575151842835)
    ]
    
    public init() throws {
        guard let dbPath = Bundle.module.path(forResource: "stars", ofType: "sqlite3") else {
            fatalError("Unable to find stars.sqlite3 in bundle")
        }
        
        self.db = try Connection(dbPath)
    }
    
    // MARK: - Stars API

    /// Get the brightest stars
    public func brightestStars() -> [Star] {
        let query = Tables.starsBrightest300
            .order(Tables.mag.asc)
        
        do {
            let rows = try db.prepare(query)
            return rows.map { createStar(from: $0) }
        } catch {
            print("Error fetching brightest stars: \(error)")
            return []
        }
    }
    
    /// Get stars up to a maximum magnitude, starting with brightest stars and falling back to H3 levels if needed
    public func stars(maximumMagnitude: Double) -> [Star] {
        var allStars: [Star] = []
        
        // First, get stars from brightest 300 that meet the magnitude criteria
        let brightestQuery = Tables.starsBrightest300
            .filter(Tables.mag <= maximumMagnitude)
            .order(Tables.mag.asc)
        
        do {
            let brightestRows = try db.prepare(brightestQuery)
            allStars = brightestRows.map { createStar(from: $0) }
            
            // Check the magnitude of the dimmest star in brightest 300 table
            let dimmestBrightestQuery = Tables.starsBrightest300
                .order(Tables.mag.desc)
                .limit(1)
            
            if let dimmestRow = try db.pluck(dimmestBrightestQuery) {
                let dimmestMagnitude = try dimmestRow.get(Tables.mag)
                
                // If the maximum magnitude exceeds the dimmest in brightest 300, search H3 levels
                if maximumMagnitude > dimmestMagnitude {
                    // Use a Set to track star IDs to avoid duplicates
                    var starIds = Set<Int>()
                    
                    // Add existing stars to the set
                    for star in allStars {
                        starIds.insert(star.id)
                    }
                    
                    // Search through H3 levels 0, 1, 2 for additional stars
                    for level in 0...2 {
                        let levelStars = stars(forH3Level: level, maximumMagnitude: maximumMagnitude)
                        
                        for star in levelStars {
                            if !starIds.contains(star.id) {
                                allStars.append(star)
                                starIds.insert(star.id)
                            }
                        }
                    }
                    
                    // Sort the final result by magnitude since we added stars from different sources
                    allStars.sort { $0.magnitude < $1.magnitude }
                }
            }
            
        } catch {
            print("Error fetching stars with maximum magnitude \(maximumMagnitude): \(error)")
            return []
        }
        
        return allStars
    }
    
    /// Get stars for a specific H3 resolution level
    public func stars(forH3Level level: Int, maximumMagnitude magCutoff: Double? = nil) -> [Star] {
        let table: Table
        
        switch level {
        case 0:
            table = Tables.starsH3_0
        case 1:
            table = Tables.starsH3_1
        case 2:
            table = Tables.starsH3_2
        default:
            print("Invalid H3 level: \(level). Must be 0, 1, or 2")
            return []
        }
        
        var query = table.select(Tables.id, Tables.mag, Tables.x, Tables.y, Tables.z, Tables.spectClass)
        
        if let magCutoff = magCutoff {
            query = query.filter(Tables.mag < magCutoff)
        }
        
        query = query.order(Tables.mag.asc)
        
        do {
            let rows = try db.prepare(query)
            return rows.map { createStar(from: $0) }
        } catch {
            print("Error fetching H3 level \(level) stars: \(error)")
            return []
        }
    }
    
    /// Get stars within a specific H3 cell
    public func stars(inH3Cell h3Index: String, level: Int, maximumMagnitude magCutoff: Double? = nil) -> [Star] {
        let table: Table
        let h3Column: SQLite.Expression<String>
        
        switch level {
        case 0:
            table = Tables.starsH3_0
            h3Column = Tables.h3_0
        case 1:
            table = Tables.starsH3_1
            h3Column = Tables.h3_1
        case 2:
            table = Tables.starsH3_2
            h3Column = Tables.h3_2
        default:
            print("Invalid H3 level: \(level). Must be 0, 1, or 2")
            return []
        }
        
        var query = table
            .filter(h3Column == h3Index)
            .select(Tables.id, Tables.mag, Tables.x, Tables.y, Tables.z, Tables.spectClass)
        
        if let magCutoff = magCutoff {
            query = query.filter(Tables.mag < magCutoff)
        }
        
        query = query.order(Tables.mag.asc)
        
        do {
            let rows = try db.prepare(query)
            return rows.map { createStar(from: $0) }
        } catch {
            print("Error fetching stars in H3 cell \(h3Index): \(error)")
            return []
        }
    }
    
    /// Get stars within a rectangular viewport defined by four lat/lon vertices
    /// Always includes all brightest 300 stars plus stars from appropriate H3 cells
    public func stars(inViewport vertices: [(latitude: Double, longitude: Double)], maximumMagnitude magCutoff: Double? = nil) -> [Star] {
        guard vertices.count == 4 else {
            print("Error: Viewport must have exactly 4 vertices")
            return []
        }
        
        // Start with brightest 300 stars (always included)
        var allStars = Set<Int>() // Use Set to avoid duplicates by star ID
        let brightestStars = brightestStars()
        for star in brightestStars {
            if let magCutoff = magCutoff {
                if star.magnitude < magCutoff {
                    allStars.insert(star.id)
                }
            } else {
                allStars.insert(star.id)
            }
        }
        
        // Convert lat/lon vertices to GeoCoord for H3 (convert degrees to radians)
        let geoCoords = vertices.map { vertex in
            GeoCoord(lat: vertex.latitude * .pi / 180.0, lon: vertex.longitude * .pi / 180.0)
        }
        
        // Create polygon for H3 polyfill
        let geofence = Geofence(numVerts: Int32(geoCoords.count), verts: UnsafeMutablePointer<GeoCoord>.allocate(capacity: geoCoords.count))
        for (index, coord) in geoCoords.enumerated() {
            geofence.verts[index] = coord
        }
        defer {
            geofence.verts.deallocate()
        }
        
        var polygon = GeoPolygon(geofence: geofence, numHoles: 0, holes: nil)
        
        // Determine the appropriate H3 level by checking if all vertices fall in the same cell
        var useLevel = 0
        
        for testLevel in 0...2 {
            let h3Indices = geoCoords.map { coord in
                withUnsafePointer(to: coord) { coordPtr in
                    geoToH3(coordPtr, Int32(testLevel))
                }
            }
            let uniqueIndices = Set(h3Indices)
            
            if uniqueIndices.count == 1 {
                // All vertices in same cell, can use higher resolution
                useLevel = testLevel + 1
                if useLevel > 2 {
                    useLevel = 2 // Cap at level 2
                    break
                }
            } else {
                // Use current level
                useLevel = testLevel
                break
            }
        }
        
        // Get H3 cells covering the polygon at the determined level
        let maxCells = maxPolyfillSize(&polygon, Int32(useLevel))
        let h3Cells = UnsafeMutablePointer<H3Index>.allocate(capacity: Int(maxCells))
        defer {
            h3Cells.deallocate()
        }
        
        polyfill(&polygon, Int32(useLevel), h3Cells)
        
        // Query stars from each H3 cell
        for i in 0..<Int(maxCells) {
            let h3Index = h3Cells[i]
            if h3Index != 0 { // Valid H3 index
                // Convert H3Index to string
                let bufferSize = 17 // H3 string representation needs max 16 chars + null terminator
                let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }
                
                h3ToString(h3Index, buffer, bufferSize)
                
                if let h3IndexString = String(cString: buffer, encoding: .utf8) {
                    let cellStars = stars(inH3Cell: h3IndexString, level: useLevel, maximumMagnitude: magCutoff)
                    for star in cellStars {
                        allStars.insert(star.id)
                    }
                }
            }
        }
        
        // Convert star IDs back to Star objects
        var result: [Star] = []
        for starId in allStars {
            if let star = star(withId: starId) {
                result.append(star)
            }
        }
        
        return result
    }
    
    /// Find the closest star to a given cartesian coordinate
    public func closestStar(
        to coordinate: Vector,
        maximumMagnitude magCutoff: Double? = nil,
        maximumAngularDistance angularDistance: Double? = nil
    ) -> Star? {
        // Convert cartesian coordinate to latitude/longitude
        let (latitude, longitude) = cartesianToLatLon(coordinate)
        
        // Convert to GeoCoord for H3
        let geoCoord = GeoCoord(lat: latitude * .pi / 180.0, lon: longitude * .pi / 180.0)
        
        // Get H3 indices for different resolution levels
        let h3_0_index = withUnsafePointer(to: geoCoord) { coordPtr in
            geoToH3(coordPtr, 0)
        }
        let h3_1_index = withUnsafePointer(to: geoCoord) { coordPtr in
            geoToH3(coordPtr, 1)
        }
        let h3_2_index = withUnsafePointer(to: geoCoord) { coordPtr in
            geoToH3(coordPtr, 2)
        }
        
        // Convert H3 indices to strings for database queries
        let h3_0_string = h3IndexToString(h3_0_index)
        let h3_1_string = h3IndexToString(h3_1_index)
        let h3_2_string = h3IndexToString(h3_2_index)
        
        var closestStar: Star?
        var minimumDistance = Double.infinity
        
        // Helper function to calculate distance and find closest star
        func checkStarsFromQuery(_ query: QueryType) {
            do {
                let rows = try db.prepare(query)
                for row in rows {
                    let star = createStar(from: row)
                    let distance = (normalize(coordinate) - normalize(star.coordinate)).magnitude()
                    
                    // Check angular distance constraint if provided
                    if let angularDistance = angularDistance {
                        let actualAngularDistance = 2 * asin(distance / 2)
                        if actualAngularDistance > angularDistance {
                            continue
                        }
                    }
                    
                    if distance < minimumDistance {
                        minimumDistance = distance
                        closestStar = star
                    }
                }
            } catch {
                print("Error querying stars: \(error)")
            }
        }
        
        if let h3_0_string = h3_0_string {
            // 1. Start with brightest 300 stars
            var query = Tables.starsBrightest300
                .filter(Tables.h3_0 == h3_0_string)
                .select(Tables.id, Tables.mag, Tables.x, Tables.y, Tables.z, Tables.spectClass)
            if let magCutoff = magCutoff {
                query = query.filter(Tables.mag < magCutoff)
            }
            checkStarsFromQuery(query)
            
            // 2. Check H3 level 0 with H3 filter
            var h3_0_query = Tables.starsH3_0
                .filter(Tables.h3_0 == h3_0_string)
                .select(Tables.id, Tables.mag, Tables.x, Tables.y, Tables.z, Tables.spectClass)
            if let magCutoff = magCutoff {
                h3_0_query = h3_0_query.filter(Tables.mag < magCutoff)
            }
            checkStarsFromQuery(h3_0_query)
        }
        
        // 3. Check H3 level 1 with H3 filter
        if let h3_1_string = h3_1_string {
            var h3_1_query = Tables.starsH3_1
                .filter(Tables.h3_1 == h3_1_string)
                .select(Tables.id, Tables.mag, Tables.x, Tables.y, Tables.z, Tables.spectClass)
            if let magCutoff = magCutoff {
                h3_1_query = h3_1_query.filter(Tables.mag < magCutoff)
            }
            checkStarsFromQuery(h3_1_query)
        }
        
        // 4. Check H3 level 2 with H3 filter
        if let h3_2_string = h3_2_string {
            var h3_2_query = Tables.starsH3_2
                .filter(Tables.h3_2 == h3_2_string)
                .select(Tables.id, Tables.mag, Tables.x, Tables.y, Tables.z, Tables.spectClass)
            if let magCutoff = magCutoff {
                h3_2_query = h3_2_query.filter(Tables.mag < magCutoff)
            }
            checkStarsFromQuery(h3_2_query)
        }
        
        return closestStar
    }
    
    // MARK: - Private Helper Functions
    
    /// Convert cartesian coordinates to latitude/longitude
    private func cartesianToLatLon(_ coordinate: Vector) -> (latitude: Double, longitude: Double) {
        // Normalize the vector (in case it's not already unit length)
        let magnitude = sqrt(coordinate.x * coordinate.x + coordinate.y * coordinate.y + coordinate.z * coordinate.z)
        guard magnitude > 0 else {
            return (0, 0)
        }
        
        let x_norm = coordinate.x / magnitude
        let y_norm = coordinate.y / magnitude
        let z_norm = coordinate.z / magnitude
        
        // Convert to spherical coordinates
        // Latitude (declination): arcsin(z)
        let latitude = asin(z_norm) * 180.0 / .pi
        
        // Longitude (right ascension): atan2(y, x)
        let longitude = atan2(y_norm, x_norm) * 180.0 / .pi
        
        return (latitude, longitude)
    }
    
    /// Convert H3 index to string
    private func h3IndexToString(_ h3Index: H3Index) -> String? {
        guard h3Index != 0 else { return nil }
        
        let bufferSize = 17 // H3 string representation needs max 16 chars + null terminator
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        h3ToString(h3Index, buffer, bufferSize)
        
        return String(cString: buffer, encoding: .utf8)
    }
    
    /// Search for stars by name or catalog identifier
    public func searchStars(matching name: String) -> [Star] {
        if name.isEmpty {
            return []
        }
        
        let query: QueryType
        
        if let hrMatch = try? #/hr\s*(\d+)/#.ignoresCase().firstMatch(in: name),
           let hrNumber = Int(hrMatch.1) {
            query = Tables.starsInfo.filter(Tables.hr == hrNumber)
        } else if let hdMatch = try? #/hd\s*(\d+)/#.ignoresCase().firstMatch(in: name),
                  let hdNumber = Int(hdMatch.1) {
            query = Tables.starsInfo.filter(Tables.hd == hdNumber)
        } else if let hipMatch = try? #/hip\s*(\d+)/#.ignoresCase().firstMatch(in: name),
                   let hipNumber = Int(hipMatch.1) {
            query = Tables.starsInfo.filter(Tables.hip == hipNumber)
        } else {
            query = Tables.starsInfo.filter(Tables.proper.like("%\(name)%"))
        }
        
        do {
            let infoRows = try db.prepare(query)
            var results: [Star] = []
            
            for infoRow in infoRows {
                let id = try infoRow.get(Tables.id)
                if let star = star(withId: id) {
                    results.append(star)
                }
            }
            
            return results
        } catch {
            print("Error searching stars: \(error)")
            return []
        }
    }
    
    /// Get a specific star by ID
    public func star(withId id: Int) -> Star? {
        // Try to find in brightest stars first
        let brightestQuery = Tables.starsBrightest300.filter(Tables.id == id)
        if let row = try? db.pluck(brightestQuery) {
            return createStar(from: row)
        }
        
        // Try H3 tables
        for level in 0...2 {
            let table: Table
            switch level {
            case 0: table = Tables.starsH3_0
            case 1: table = Tables.starsH3_1  
            case 2: table = Tables.starsH3_2
            default: continue
            }
            
            let query = table.filter(Tables.id == id)
            if let row = try? db.pluck(query) {
                return createStar(from: row)
            }
        }
        
        return nil
    }
    
    /// Get detailed information for a star
    public func starInfo(forId id: Int) -> StarInfo? {
        // Join with constellations table to get full constellation information
        let query = Tables.starsInfo
            .join(Tables.constellations, on: Tables.starsInfo[Tables.con] == Tables.constellations[Tables.iau])
            .filter(Tables.starsInfo[Tables.id] == id)
        
        do {
            if let row = try db.pluck(query) {
                return createStarInfo(from: row)
            }
        } catch {
            print("Error fetching star info for ID \(id): \(error)")
        }
        
        return nil
    }
    
    /// Get star with detailed information loaded
    public func starWithInfo(id: Int) -> Star? {
        guard var star = star(withId: id) else { return nil }
        star.info = starInfo(forId: id)
        return star
    }
    
    // MARK: - Private Helpers
    
    private func createStar(from row: Row) -> Star {
        let id = try! row.get(Tables.id)
        let magnitude = try! row.get(Tables.mag)
        let x = try! row.get(Tables.x)
        let y = try! row.get(Tables.y)
        let z = try! row.get(Tables.z)
        let spectralClass = try! row.get(Tables.spectClass)
        
        let coordinate = Vector(x, y, z)
        return Star(id: id, magnitude: magnitude, coordinate: coordinate, spectralClass: spectralClass)
    }
    
    private func createStarInfo(from row: Row) -> StarInfo {
        // Get constellation information from joined table
        let constellation: Constellation?
        let iauName = try? row.get(Tables.iau)
        let constellationId = try? row.get(Tables.constellations[Tables.constellationId])
        let constellationName = try? row.get(Tables.constellationName)
        let genitive = try? row.get(Tables.genitive)
        if let iauName, let constellationId, let constellationName, let genitive, let center = constellationCenter[iauName] {
            constellation = Constellation(id: constellationId, name: constellationName, iAUName: iauName, genitive: genitive, center: center)
        } else {
            constellation = nil
        }

        let bfDesignation: BayerFlamsteed?
        if let constellation {
            let bayer = try? row.get(Tables.bayer)
            let flam = try? row.get(Tables.flam)
            bfDesignation = BayerFlamsteed(bayer: bayer, flamsteed: flam, constellation: constellation)
        } else {
            bfDesignation = nil
        }
        
        return StarInfo(
            hipId: try! row.get(Tables.hip),
            hdId: try! row.get(Tables.hd),
            hrId: try! row.get(Tables.hr),
            gl: try! row.get(Tables.gl),
            bfDesignation: bfDesignation,
            properName: try! row.get(Tables.proper),
            absoluteMagnitude: try! row.get(Tables.absmag),
            spectralType: try! row.get(Tables.spect),
            colorIndex: try! row.get(Tables.ci),
            bayer: try! row.get(Tables.bayer),
            flamsteed: try! row.get(Tables.flam),
            constellation: constellation,
            component: try! row.get(Tables.comp),
            componentPrimary: try! row.get(Tables.compPrimary),
            base: try! row.get(Tables.base),
            luminosity: try! row.get(Tables.lum),
            variableDesignation: try! row.get(Tables.varDesig),
            variableMin: try! row.get(Tables.varMin),
            variableMax: try! row.get(Tables.varMax)
        )
    }
}
