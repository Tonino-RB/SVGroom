import Foundation

/// Plot-time model of an AxiDraw (high-resolution mode, standard pen-lift servo):
/// trapezoidal speed profile, slowing down in corners, and servo time for each pen lift.
/// Machine constants are the published defaults of the AxiDraw software (axidraw_conf.py).
struct MotionModel {
    private static let mmPerInch = 25.4
    /// Speed at 100 %, mm/s (8.6979 in/s, scaled by 1/110 in AxiDraw).
    private static let speedLimit = 8.6979 * mmPerInch / 110
    /// Acceleration at 100 %, mm/s²: pen down 40 in/s², pen up 60 in/s².
    private static let downAccel = 40 * mmPerInch, upAccel = 60 * mmPerInch
    /// Corner rounding distance, mm (GRBL-style junction deviation; AxiDraw cornering 10 → 0.002 in).
    private static let cornering = 0.002 * mmPerInch
    /// Paths closer than this are joined without lifting the pen, mm (AxiDraw min_gap 0.006 in).
    static let joinGap = 0.006 * mmPerInch
    /// Points this close to a straight line through their neighbours are dropped before planning, mm.
    private static let mergeTolerance = 0.0002 * mmPerInch

    let downSpeed, upSpeed, downAccel, upAccel: Double
    /// Pen raise + pen lower, seconds.
    let liftTime: Double

    init(_ s: PlotSettings) {
        downSpeed = max(s.penDownSpeed, 1) * Self.speedLimit
        upSpeed = max(s.penUpSpeed, 1) * Self.speedLimit
        downAccel = max(s.acceleration, 1) / 100 * Self.downAccel
        upAccel = max(s.acceleration, 1) / 100 * Self.upAccel
        // Servo: transit time and sweep-rate time, blended (ms). Standard servo constants.
        let travel = abs(s.penUpHeight - s.penDownHeight)
        func servo(_ rate: Double) -> Double {
            travel < 0.9 ? 0 : pow(pow(2.69 * travel + 45, 4) + pow(200 * travel / max(rate, 1), 4), 0.25)
        }
        liftTime = (servo(s.penRaiseRate) + servo(s.penLowerRate)) / 1000
    }

    /// Pen-up move between two points, from rest to rest.
    func travelTime(_ distance: Double) -> Double {
        Self.moveTime(distance, v0: 0, v1: 0, vmax: upSpeed, accel: upAccel)
    }

    /// Pen-down polyline from rest to rest. The speed at each vertex is limited by the corner angle
    /// and by what acceleration allows over the neighbouring segments.
    func strokeTime(_ stroke: [Point]) -> Double {
        let pts = Self.merged(stroke)
        var lengths: [Double] = [], dirs: [Point] = []
        lengths.reserveCapacity(pts.count)
        dirs.reserveCapacity(pts.count)
        for i in 1..<max(pts.count, 1) {
            let l = pts[i - 1].distance(to: pts[i])
            guard l > 1e-9 else { continue }
            lengths.append(l)
            dirs.append(Point(x: (pts[i].x - pts[i - 1].x) / l, y: (pts[i].y - pts[i - 1].y) / l))
        }
        let n = lengths.count
        guard n > 0 else { return 0 }

        // Junction speed limits: v[i] is the speed at the start of segment i.
        var v = [Double](repeating: 0, count: n + 1)
        let a = downAccel
        for i in 1..<n {
            let cosTheta = -(dirs[i - 1].x * dirs[i].x + dirs[i - 1].y * dirs[i].y)
            let sinHalf = ((1 - cosTheta) / 2).squareRoot()
            v[i] = sinHalf > 0.9999 ? downSpeed : min(downSpeed, (a * Self.cornering * sinHalf / (1 - sinHalf)).squareRoot())
        }
        for i in 1..<n { v[i] = min(v[i], (v[i - 1] * v[i - 1] + 2 * a * lengths[i - 1]).squareRoot()) }
        for i in stride(from: n - 1, to: 0, by: -1) { v[i] = min(v[i], (v[i + 1] * v[i + 1] + 2 * a * lengths[i]).squareRoot()) }

        var t = 0.0
        for i in 0..<n { t += Self.moveTime(lengths[i], v0: v[i], v1: v[i + 1], vmax: downSpeed, accel: a) }
        return t
    }

    /// Drops points that lie within `mergeTolerance` of the segment joining the kept point before them
    /// and a later point, like the AxiDraw does (at most 64 points are merged into one segment).
    static func merged(_ pts: [Point]) -> [Point] {
        guard pts.count > 2 else { return pts }
        var out = [pts[0]]
        var anchor = 0
        for i in 2..<pts.count {
            let a = pts[anchor], c = pts[i]
            var straight = i - anchor <= 64
            if straight {
                for j in anchor + 1..<i where pts[j].distance(toSegment: a, c) > mergeTolerance { straight = false; break }
            }
            if !straight { out.append(pts[i - 1]); anchor = i - 1 }
        }
        out.append(pts[pts.count - 1])
        return out
    }

    /// Duration of one straight move of length `d`, entering at v0 and leaving at v1, the way the AxiDraw
    /// software plans it in 25 ms time slices: a trapezoid when there is room to cruise, a triangle when
    /// the ramps are long enough, otherwise a single ramp from a boosted start speed, or a constant speed.
    static func moveTime(_ d: Double, v0 v0In: Double, v1 v1In: Double, vmax: Double, accel a: Double) -> Double {
        guard d > 0 else { return 0 }
        let slice = 0.025
        let v0 = min(v0In, vmax), v1 = min(v1In, vmax)
        let accelDist = (vmax * vmax - v0 * v0) / (2 * a), decelDist = (vmax * vmax - v1 * v1) / (2 * a)
        if d > accelDist + decelDist + slice * vmax && d / vmax > 4 * slice {
            return (vmax - v0) / a + (vmax - v1) / a + (d - accelDist - decelDist) / vmax
        }

        // Triangle; the acceleration is softened when the move is nearly long enough to cruise.
        let ramps = accelDist + decelDist
        let al = ramps > 0 && d >= 0.9 * ramps ? 0.9 * ramps / d * a : a
        var ta = ((2 * v0 * v0 + 2 * v1 * v1 + 4 * al * d).squareRoot() - 2 * v0) / (2 * al)
        let peak = v0 + al * ta // Not capped at vmax: short moves can exceed the set speed.
        if (ta / slice).rounded(.down) == 0 { ta = 0 }
        let td = ta - (v1 - v0) / al
        let accelSlices = (ta / slice).rounded(.down), decelSlices = (td / slice).rounded(.down)
        if accelSlices + decelSlices > 4 {
            // The AxiDraw sends one slice fewer than the ramps add up to (measured on its planned moves).
            return ta + td - (decelSlices > 0 ? td / decelSlices : ta / accelSlices)
        }

        // Too short for both ramps: one linear ramp from (peak + v0) / 2 to v1, or constant speed.
        let start = (peak + v0) / 2
        guard start != v1 else { return d / start }
        let ramp = max(-a, min(a, (v1 * v1 - start * start) / (2 * d)))
        let t = (v1 - start) / ramp
        return (t / slice).rounded(.down) > 1 ? t : d / max(peak, v1)
    }
}
