import SwiftUI

/// Draws a 2D filled hand silhouette from 21 tracked joint positions.
/// Each finger is rendered as a tapered rounded ribbon. The palm is a filled
/// convex polygon connecting all knuckle bases. Fingertips and palm glow softly.
public struct HUDOverlayView: View {
    let points: [Point3D]
    @ObservedObject var settings = SettingsManager.shared

    public init(points: [Point3D]) {
        self.points = points
    }

    public var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard points.count == 21, settings.showHUDSkeleton else { return }

                // Map normalised Vision coords → canvas pixels (flip Y: Vision origin = bottom-left)
                let cp = points.map { p in
                    CGPoint(x: CGFloat(p.x) * size.width,
                            y: CGFloat(1.0 - p.y) * size.height)
                }

                let skin   = skinColor
                let accent = themeColor

                // ── 1. Palm filled polygon ──────────────────────────────────────────
                // Vertices: wrist (0), then knuckle bases of each finger in order,
                // closed back through pinky knuckle base → wrist.
                // Index order: thumb-base (1), index-MCP (5), middle-MCP (9),
                //              ring-MCP (13), little-MCP (17)
                let palmIndices = [0, 1, 5, 9, 13, 17]
                var palmPath = Path()
                palmPath.move(to: cp[palmIndices[0]])
                for i in palmIndices.dropFirst() { palmPath.addLine(to: cp[i]) }
                palmPath.closeSubpath()

                context.fill(palmPath, with: .color(skin.opacity(0.72)))
                context.stroke(palmPath, with: .color(accent.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                // ── 2. Fingers as tapered filled ribbons ────────────────────────────
                // Each finger: joints listed base→tip.
                // Width tapers from ~widthBase at the MCP knuckle to ~widthTip at the tip.
                let fingers: [[Int]] = [
                    [1, 2, 3, 4],       // Thumb
                    [5, 6, 7, 8],       // Index
                    [9, 10, 11, 12],    // Middle
                    [13, 14, 15, 16],   // Ring
                    [17, 18, 19, 20],   // Little
                ]
                let baseWidths: [CGFloat] = [11, 14, 15, 13, 10]
                let tipWidths:  [CGFloat] = [ 6,  7,  7,  6,  5]

                for (fi, joints) in fingers.enumerated() {
                    let bw = baseWidths[fi]
                    let tw = tipWidths[fi]
                    let count = joints.count   // typically 4 segments (base MCP to tip)

                    var leftSide:  [CGPoint] = []
                    var rightSide: [CGPoint] = []

                    for (si, jointIdx) in joints.enumerated() {
                        let t = CGFloat(si) / CGFloat(count - 1)
                        let halfW = (bw * (1 - t) + tw * t) / 2.0

                        let curr = cp[jointIdx]

                        // Perpendicular direction at this joint
                        let perp: CGPoint
                        if si == 0 {
                            // Use direction to next joint
                            let next = cp[joints[si + 1]]
                            perp = normalized(perpendicular(from: curr, to: next))
                        } else if si == count - 1 {
                            // Use direction from previous joint
                            let prev = cp[joints[si - 1]]
                            perp = normalized(perpendicular(from: prev, to: curr))
                        } else {
                            // Average of incoming and outgoing perpendiculars
                            let prev = cp[joints[si - 1]]
                            let next = cp[joints[si + 1]]
                            let p1 = normalized(perpendicular(from: prev, to: curr))
                            let p2 = normalized(perpendicular(from: curr, to: next))
                            perp = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                        }

                        leftSide.append(CGPoint(x: curr.x - perp.x * halfW,
                                                y: curr.y - perp.y * halfW))
                        rightSide.append(CGPoint(x: curr.x + perp.x * halfW,
                                                 y: curr.y + perp.y * halfW))
                    }

                    // Build finger path: left side forward, right side backward, rounded cap at tip
                    var fingerPath = Path()
                    fingerPath.move(to: leftSide[0])
                    for pt in leftSide.dropFirst() { fingerPath.addLine(to: pt) }

                    // Rounded fingertip cap
                    let tipL = leftSide.last!
                    let tipR = rightSide.last!
                    let tipCenter = cp[joints.last!]
                    let tipRadius = distance(tipL, tipR) / 2.0
                    let startAngle = atan2(tipL.y - tipCenter.y, tipL.x - tipCenter.x)
                    let endAngle   = atan2(tipR.y - tipCenter.y, tipR.x - tipCenter.x)
                    fingerPath.addArc(center: tipCenter,
                                      radius: tipRadius,
                                      startAngle: Angle(radians: Double(startAngle)),
                                      endAngle:   Angle(radians: Double(endAngle)),
                                      clockwise: false)

                    for pt in rightSide.reversed().dropFirst() { fingerPath.addLine(to: pt) }
                    fingerPath.closeSubpath()

                    // Fill with skin tone, stroke with accent glow
                    context.fill(fingerPath, with: .color(skin.opacity(0.80)))
                    context.stroke(fingerPath, with: .color(accent.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }

                // ── 3. Joint highlight dots ─────────────────────────────────────────
                let tipIndices: Set<Int> = [4, 8, 12, 16, 20]
                for (i, pt) in cp.enumerated() {
                    let r: CGFloat = tipIndices.contains(i) ? 5 : 3
                    let dotRect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)

                    // Soft glow halo
                    context.fill(Path(ellipseIn: dotRect.insetBy(dx: -3, dy: -3)),
                                 with: .color(accent.opacity(0.18)))
                    // Bright dot
                    context.fill(Path(ellipseIn: dotRect),
                                 with: .color(tipIndices.contains(i) ? Color.white.opacity(0.9) : accent.opacity(0.75)))
                }

                // ── 4. Wrist circle ─────────────────────────────────────────────────
                let wrist = cp[0]
                let wr: CGFloat = 7
                let wristRect = CGRect(x: wrist.x - wr, y: wrist.y - wr, width: wr * 2, height: wr * 2)
                context.fill(Path(ellipseIn: wristRect), with: .color(skin.opacity(0.9)))
                context.stroke(Path(ellipseIn: wristRect), with: .color(accent.opacity(0.7)), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Geometry helpers

    /// Returns the perpendicular vector (rotated 90°) of the direction from a→b.
    private func perpendicular(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return CGPoint(x: -dy, y: dx)   // rotate 90°
    }

    private func normalized(_ v: CGPoint) -> CGPoint {
        let len = sqrt(v.x * v.x + v.y * v.y)
        guard len > 0.001 else { return CGPoint(x: 0, y: 1) }
        return CGPoint(x: v.x / len, y: v.y / len)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x; let dy = b.y - a.y
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - Colours

    /// Warm skin-tone fill that pairs naturally with any accent glow.
    private var skinColor: Color {
        Color(red: 0.92, green: 0.78, blue: 0.62)
    }

    private var themeColor: Color {
        switch settings.hudThemeColor {
        case "Green":   return .green
        case "Magenta": return .pink
        case "Orange":  return .orange
        default:        return .cyan
        }
    }
}
