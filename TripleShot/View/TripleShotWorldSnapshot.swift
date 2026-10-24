import Foundation

// Port of view/TripleShotWorldSnapshot.kt (TripleShotGame dd722e5), statement by statement.
// Spec 06 sections 3.1 and 7. Units are presentation metres (X right, Y up, Z toward the camera).
// Kotlin data classes become structs with `var` properties (so `copy(x = ...)` can be written as a mutated copy).
// Only `CourtPoint` is compared by value on Android (`hoopKey != scene.hoops` in the renderer), so it alone gets
// Equatable/Hashable, with the Kotlin data-class semantics for Float properties (Float.compare, i.e. floatToIntBits:
// NaN equals NaN and 0.0 differs from -0.0). `TripleShotWorldBall.resource` is the drawable resource (Android Int id,
// iOS `ADrawableRes` name, DESIGN 2.7). `TripleShotWorldMarker.selected` and `TripleShotWorldSnapshot.timeNanos` are
// kept although no renderer reads them (spec 06 section 8 item 17).

/** Presentation metres: X right, Y up, Z toward the camera. No rules live in this package. */
struct CourtPoint: Hashable, CustomStringConvertible {
    var x: Float
    var y: Float
    var z: Float

    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Positional form of `CourtPoint(x, y, z)` (the labelled initialiser is preferred, DESIGN 2.1).
    init(_ x: Float, _ y: Float, _ z: Float) {
        self.init(x: x, y: y, z: z)
    }

    /// Kotlin `copy(x = ..., y = ..., z = ...)`.
    func copy(x: Float? = nil, y: Float? = nil, z: Float? = nil) -> CourtPoint {
        return CourtPoint(x: x ?? self.x, y: y ?? self.y, z: z ?? self.z)
    }

    /// Kotlin data-class `equals`: each Float property is compared with `Float.compare(a, b) == 0`.
    static func == (lhs: CourtPoint, rhs: CourtPoint) -> Bool {
        return lhs.x.toBits() == rhs.x.toBits() && lhs.y.toBits() == rhs.y.toBits() && lhs.z.toBits() == rhs.z.toBits()
    }

    /// Consistent with `==` (Kotlin `hashCode()` hashes the same floatToIntBits values).
    func hash(into hasher: inout Hasher) {
        hasher.combine(x.toBits())
        hasher.combine(y.toBits())
        hasher.combine(z.toBits())
    }

    /// Kotlin data-class `toString()` (Java Float formatting), so string interpolation prints what Kotlin prints.
    /// Used by the renderer's TRIPLE_PLAY diagnostics log (`ball=<owner>:<position>`, TripleShotPremiumRenderer.kt 274).
    var description: String {
        return "CourtPoint(x=\(javaString(x)), y=\(javaString(y)), z=\(javaString(z)))"
    }
}

struct TripleShotWorldActor {
    var id: String
    var position: CourtPoint
    var state: TripleShotPlayerRenderer.State
    var controlled: Bool
    var team: Int
    var label: String
    var labelColor: Int

    init(
        id: String,
        position: CourtPoint,
        state: TripleShotPlayerRenderer.State,
        controlled: Bool = false,
        team: Int = 0,
        label: String = "",
        labelColor: Int = AColor.WHITE
    ) {
        self.id = id
        self.position = position
        self.state = state
        self.controlled = controlled
        self.team = team
        self.label = label
        self.labelColor = labelColor
    }
}

struct TripleShotWorldBall {
    var position: CourtPoint
    var resource: ADrawableRes
    var owner: String?
    var rotation: Float
    var inFront: Bool

    init(
        position: CourtPoint,
        resource: ADrawableRes,
        owner: String? = nil,
        rotation: Float = 0,
        inFront: Bool = true
    ) {
        self.position = position
        self.resource = resource
        self.owner = owner
        self.rotation = rotation
        self.inFront = inFront
    }
}

struct TripleShotWorldMarker {
    var position: CourtPoint
    var text: String
    var selected: Bool

    init(position: CourtPoint, text: String, selected: Bool) {
        self.position = position
        self.text = text
        self.selected = selected
    }
}

struct TripleShotWorldSnapshot {
    var timeNanos: Int64
    var courtId: String
    var teamSize: Int
    var actors: [TripleShotWorldActor]
    var balls: [TripleShotWorldBall]
    var hoops: [CourtPoint]
    var atmosphere: TripleShotCourtAtmosphere
    var markers: [TripleShotWorldMarker]
    var guides: [CourtPoint]
    var rimShake: Float
    var netSway: Float
    var activeHoopIndex: Int

    init(
        timeNanos: Int64,
        courtId: String,
        teamSize: Int,
        actors: [TripleShotWorldActor],
        balls: [TripleShotWorldBall],
        hoops: [CourtPoint],
        atmosphere: TripleShotCourtAtmosphere,
        markers: [TripleShotWorldMarker] = [],
        guides: [CourtPoint] = [],
        rimShake: Float = 0,
        netSway: Float = 0,
        activeHoopIndex: Int = 0
    ) {
        self.timeNanos = timeNanos
        self.courtId = courtId
        self.teamSize = teamSize
        self.actors = actors
        self.balls = balls
        self.hoops = hoops
        self.atmosphere = atmosphere
        self.markers = markers
        self.guides = guides
        self.rimShake = rimShake
        self.netSway = netSway
        self.activeHoopIndex = activeHoopIndex
    }
}

protocol TripleShotWorldSink: AnyObject { func submit(snapshot: TripleShotWorldSnapshot) }

/** One conversion at the boundary; the original simulation keeps its calibrated coordinates. */
enum TripleShotWorldCoordinates {
    static let RIM_HEIGHT: Float = 3.35

    static func solo(sourceX: Float, sourceY: Float, lift: Float = 0) -> CourtPoint {
        return CourtPoint(x: (sourceX - 512) * 0.014, y: lift, z: (sourceY - 948) * 0.017)
    }

    static func team(sourceX: Float, sourceY: Float, lift: Float = 0) -> CourtPoint {
        return CourtPoint(x: (sourceX - 834) * 0.014, y: lift, z: (sourceY - 531) * 0.034)
    }
}
