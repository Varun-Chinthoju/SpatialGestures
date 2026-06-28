import SwiftUI

/// Renders a polished, 2D illustrated hand from 21 tracked joints.
/// Draws palm + fingers as smooth curved shapes with gradient fill,
/// depth shadow, knuckle creases, fingernails, and a glowing accent outline.
public struct HUDOverlayView: View {
    let points: [Point3D]
    @ObservedObject var settings = SettingsManager.shared

    public init(points: [Point3D]) { self.points = points }

    public var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                guard points.count == 21, settings.showHUDSkeleton else { return }

                // Map normalised Vision → canvas (flip Y)
                let cp = points.map { p in
                    CGPoint(x: CGFloat(p.x) * size.width,
                            y: CGFloat(1.0 - p.y) * size.height)
                }

                let accent = themeColor
                let handScale = handSize(cp: cp)  // scale-aware width sizing

                // ─── Finger joint sequences (base MCP → tip) ────────────────────────
                let fingers: [[Int]] = [
                    [1, 2, 3, 4],    // Thumb
                    [5, 6, 7, 8],    // Index
                    [9, 10, 11, 12], // Middle
                    [13, 14, 15, 16],// Ring
                    [17, 18, 19, 20] // Little
                ]
                // Base and tip half-widths, scaled to actual hand size in canvas
                let baseHW: [CGFloat] = [9, 10, 11, 9.5, 7.5].map { $0 * handScale }
                let tipHW:  [CGFloat] = [4.5, 5, 5.5, 4.5, 3.5].map { $0 * handScale }

                // ─── 1. Drop shadow (entire hand outline, offset + blurred look) ────
                let shadowOffset = CGPoint(x: 3 * handScale, y: 5 * handScale)
                drawHand(context: context, cp: cp, fingers: fingers,
                         baseHW: baseHW, tipHW: tipHW,
                         fill: .color(Color.black.opacity(0.30)),
                         stroke: nil,
                         offset: shadowOffset)

                // ─── 2. Main hand: filled with a 2-stop skin gradient ────────────────
                // Build full bounding rect of the hand to place the gradient
                let allX = cp.map(\.x); let allY = cp.map(\.y)
                let minX = allX.min()!; let maxX = allX.max()!
                let minY = allY.min()!; let maxY = allY.max()!
                let gradRect = CGRect(x: minX, y: minY,
                                     width: maxX - minX, height: maxY - minY)

                let skinGradient = Gradient(stops: [
                    .init(color: skinLight, location: 0.0),
                    .init(color: skinMid,   location: 0.55),
                    .init(color: skinDark,  location: 1.0)
                ])
                let gradShading = GraphicsContext.Shading.linearGradient(
                    skinGradient,
                    startPoint: CGPoint(x: gradRect.midX, y: gradRect.minY),
                    endPoint:   CGPoint(x: gradRect.midX, y: gradRect.maxY)
                )

                drawHand(context: context, cp: cp, fingers: fingers,
                         baseHW: baseHW, tipHW: tipHW,
                         fill: gradShading,
                         stroke: nil,
                         offset: .zero)

                // ─── 3. Accent glow outline ──────────────────────────────────────────
                // Draw outline twice: thick translucent for glow, thin solid for crispness
                drawHand(context: context, cp: cp, fingers: fingers,
                         baseHW: baseHW, tipHW: tipHW,
                         fill: nil,
                         stroke: StrokeSpec(color: accent.opacity(0.25), width: 5 * handScale),
                         offset: .zero)
                drawHand(context: context, cp: cp, fingers: fingers,
                         baseHW: baseHW, tipHW: tipHW,
                         fill: nil,
                         stroke: StrokeSpec(color: accent.opacity(0.80), width: 1.2),
                         offset: .zero)

                // ─── 4. Knuckle crease lines ─────────────────────────────────────────
                let creaseJoints: [Int] = [2, 3, 6, 7, 10, 11, 14, 15, 18, 19]
                for idx in creaseJoints {
                    guard idx < cp.count else { continue }
                    // Determine adjacent joints for perpendicular direction
                    let prev = max(idx - 1, 0)
                    let next = min(idx + 1, cp.count - 1)
                    let perp = normalized(perpendicular(from: cp[prev], to: cp[next]))
                    let crW = (idx % 4 == 2 ? 5.0 : 3.5) * handScale  // knuckle wider than mid-joint
                    let c = cp[idx]
                    let p1 = CGPoint(x: c.x - perp.x * crW, y: c.y - perp.y * crW)
                    let p2 = CGPoint(x: c.x + perp.x * crW, y: c.y + perp.y * crW)
                    var creasePath = Path()
                    creasePath.move(to: p1)
                    creasePath.addLine(to: p2)
                    context.stroke(creasePath,
                                   with: .color(skinDark.opacity(0.45)),
                                   style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                }

                // ─── 5. Fingernails ──────────────────────────────────────────────────
                let tipIndices = [4, 8, 12, 16, 20]
                for (fi, tipIdx) in tipIndices.enumerated() {
                    let finger = fingers[fi]
                    guard finger.count >= 2 else { continue }
                    let base   = cp[finger[finger.count - 2]]
                    let tipPt  = cp[tipIdx]

                    // Direction along finger toward tip
                    let dir = normalized(CGPoint(x: tipPt.x - base.x, y: tipPt.y - base.y))
                    let perp = normalized(perpendicular(from: base, to: tipPt))

                    let nailW = tipHW[fi] * 1.1 * handScale  // slightly narrower than finger tip
                    let nailH = nailW * 0.7

                    // Offset nail slightly toward the tip of the finger
                    let nailCenter = CGPoint(x: tipPt.x - dir.x * nailH * 0.6,
                                            y: tipPt.y - dir.y * nailH * 0.6)

                    // Build a small rounded-rect path oriented along the finger direction
                    var nailPath = Path()
                    let corners: [CGPoint] = [
                        CGPoint(x: nailCenter.x - perp.x * nailW - dir.x * nailH * 0.4,
                                y: nailCenter.y - perp.y * nailW - dir.y * nailH * 0.4),
                        CGPoint(x: nailCenter.x + perp.x * nailW - dir.x * nailH * 0.4,
                                y: nailCenter.y + perp.y * nailW - dir.y * nailH * 0.4),
                        CGPoint(x: nailCenter.x + perp.x * nailW + dir.x * nailH * 0.6,
                                y: nailCenter.y + perp.y * nailW + dir.y * nailH * 0.6),
                        CGPoint(x: nailCenter.x - perp.x * nailW + dir.x * nailH * 0.6,
                                y: nailCenter.y - perp.y * nailW + dir.y * nailH * 0.6),
                    ]
                    nailPath.move(to: corners[0])
                    nailPath.addQuadCurve(to: corners[1],
                                         control: CGPoint(x: nailCenter.x - dir.x * nailH * 0.4,
                                                          y: nailCenter.y - dir.y * nailH * 0.4))
                    nailPath.addLine(to: corners[2])
                    nailPath.addQuadCurve(to: corners[3],
                                         control: CGPoint(x: nailCenter.x + dir.x * nailH * 0.6,
                                                          y: nailCenter.y + dir.y * nailH * 0.6))
                    nailPath.closeSubpath()

                    context.fill(nailPath, with: .color(Color.white.opacity(0.55)))
                    context.stroke(nailPath, with: .color(accent.opacity(0.4)),
                                   style: StrokeStyle(lineWidth: 0.7))
                }

                // ─── 6. Tip glow dots ────────────────────────────────────────────────
                for tipIdx in tipIndices {
                    let pt = cp[tipIdx]
                    let r: CGFloat = 4.5 * handScale
                    // Outer glow halo
                    context.fill(Path(ellipseIn: CGRect(x: pt.x - r * 1.8, y: pt.y - r * 1.8,
                                                        width: r * 3.6, height: r * 3.6)),
                                 with: .color(accent.opacity(0.12)))
                    // Inner bright dot
                    context.fill(Path(ellipseIn: CGRect(x: pt.x - r * 0.55, y: pt.y - r * 0.55,
                                                        width: r * 1.1, height: r * 1.1)),
                                 with: .color(accent.opacity(0.85)))
                }

                // ─── 7. Wrist indicator ──────────────────────────────────────────────
                let wrist = cp[0]
                let wr: CGFloat = 6 * handScale
                context.fill(Path(ellipseIn: CGRect(x: wrist.x - wr, y: wrist.y - wr,
                                                     width: wr * 2, height: wr * 2)),
                             with: .color(skinMid.opacity(0.9)))
                context.stroke(Path(ellipseIn: CGRect(x: wrist.x - wr, y: wrist.y - wr,
                                                       width: wr * 2, height: wr * 2)),
                               with: .color(accent.opacity(0.75)), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Core hand drawing

    private struct StrokeSpec {
        let color: Color
        let width: CGFloat
    }

    /// Draws the full hand shape (palm + all fingers) as one compound path.
    private func drawHand(context: GraphicsContext,
                          cp: [CGPoint],
                          fingers: [[Int]],
                          baseHW: [CGFloat],
                          tipHW: [CGFloat],
                          fill: GraphicsContext.Shading?,
                          stroke: StrokeSpec?,
                          offset: CGPoint) {

        let shift: (CGPoint) -> CGPoint = { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }

        // ── Palm: smooth curve through wrist + all knuckle bases ──
        let palmRing: [Int] = [0, 1, 5, 9, 13, 17]
        var palmPath = Path()
        let palmPts = palmRing.map { shift(cp[$0]) }

        palmPath.move(to: palmPts[0])
        // Smooth catmull-rom-like curve through palm ring
        for i in 1..<palmPts.count {
            let prev = palmPts[max(i - 1, 0)]
            let curr = palmPts[i]
            let next = palmPts[min(i + 1, palmPts.count - 1)]
            let ctrl1 = CGPoint(x: prev.x + (curr.x - prev.x) * 0.5,
                                y: prev.y + (curr.y - prev.y) * 0.5)
            let ctrl2 = CGPoint(x: curr.x - (next.x - curr.x) * 0.2,
                                y: curr.y - (next.y - curr.y) * 0.2)
            palmPath.addCurve(to: curr, control1: ctrl1, control2: ctrl2)
        }
        // Smooth close back to wrist
        let last = palmPts.last!
        let first = palmPts.first!
        palmPath.addCurve(to: first,
                          control1: CGPoint(x: last.x + (first.x - last.x) * 0.4,
                                           y: last.y + (first.y - last.y) * 0.4),
                          control2: CGPoint(x: first.x - (first.x - last.x) * 0.1,
                                           y: first.y - (first.y - last.y) * 0.1))

        if let f = fill   { context.fill(palmPath, with: f) }
        if let s = stroke { context.stroke(palmPath, with: .color(s.color),
                                           style: StrokeStyle(lineWidth: s.width,
                                                              lineCap: .round,
                                                              lineJoin: .round)) }

        // ── Fingers ───────────────────────────────────────────────
        for (fi, joints) in fingers.enumerated() {
            let n = joints.count
            var leftSide:  [CGPoint] = []
            var rightSide: [CGPoint] = []

            for (si, jointIdx) in joints.enumerated() {
                let t  = CGFloat(si) / CGFloat(n - 1)
                let hw = (baseHW[fi] * (1 - t) + tipHW[fi] * t)
                let c  = shift(cp[jointIdx])

                let perp: CGPoint
                if si == 0 {
                    perp = normalized(perpendicular(from: shift(cp[joints[0]]),
                                                   to:   shift(cp[joints[1]])))
                } else if si == n - 1 {
                    perp = normalized(perpendicular(from: shift(cp[joints[n - 2]]),
                                                   to:   shift(cp[joints[n - 1]])))
                } else {
                    let p1 = normalized(perpendicular(from: shift(cp[joints[si - 1]]),
                                                     to:   c))
                    let p2 = normalized(perpendicular(from: c,
                                                     to:   shift(cp[joints[si + 1]])))
                    perp = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                }

                leftSide.append(CGPoint(x: c.x - perp.x * hw, y: c.y - perp.y * hw))
                rightSide.append(CGPoint(x: c.x + perp.x * hw, y: c.y + perp.y * hw))
            }

            var fp = Path()
            fp.move(to: leftSide[0])

            // Left edge — smooth curves through each segment
            for i in 1..<leftSide.count {
                let ctrl = midPoint(leftSide[i - 1], leftSide[i])
                fp.addQuadCurve(to: leftSide[i], control: ctrl)
            }

            // Rounded tip cap
            let tipL      = leftSide.last!
            let tipR      = rightSide.last!
            let tipCenter = shift(cp[joints.last!])
            let tipRadius = dist(tipL, tipR) / 2.0
            let angL = atan2(tipL.y - tipCenter.y, tipL.x - tipCenter.x)
            let angR = atan2(tipR.y - tipCenter.y, tipR.x - tipCenter.x)
            fp.addArc(center: tipCenter, radius: tipRadius,
                      startAngle: .radians(Double(angL)),
                      endAngle:   .radians(Double(angR)),
                      clockwise: false)

            // Right edge reversed
            for i in stride(from: rightSide.count - 2, through: 0, by: -1) {
                let ctrl = midPoint(rightSide[i + 1], rightSide[i])
                fp.addQuadCurve(to: rightSide[i], control: ctrl)
            }
            fp.closeSubpath()

            if let f = fill   { context.fill(fp, with: f) }
            if let s = stroke { context.stroke(fp, with: .color(s.color),
                                               style: StrokeStyle(lineWidth: s.width,
                                                                  lineCap: .round,
                                                                  lineJoin: .round)) }
        }
    }

    // MARK: - Geometry helpers

    /// Estimates scale factor from actual wrist→middle-MCP distance vs expected canvas size.
    private func handSize(cp: [CGPoint]) -> CGFloat {
        let d = dist(cp[0], cp[9])
        let normalised = d / 120.0   // 120px is roughly full-size on a 320pt card
        return max(0.5, min(1.5, normalised))
    }

    private func perpendicular(from a: CGPoint, to b: CGPoint) -> CGPoint {
        CGPoint(x: -(b.y - a.y), y: b.x - a.x)
    }

    private func normalized(_ v: CGPoint) -> CGPoint {
        let len = sqrt(v.x * v.x + v.y * v.y)
        guard len > 0.001 else { return CGPoint(x: 0, y: 1) }
        return CGPoint(x: v.x / len, y: v.y / len)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2))
    }

    private func midPoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    // MARK: - Colours

    private var skinLight: Color { Color(red: 0.98, green: 0.87, blue: 0.73) }
    private var skinMid:   Color { Color(red: 0.90, green: 0.74, blue: 0.58) }
    private var skinDark:  Color { Color(red: 0.76, green: 0.58, blue: 0.42) }

    private var themeColor: Color {
        switch settings.hudThemeColor {
        case "Green":   return .green
        case "Magenta": return .pink
        case "Orange":  return .orange
        default:        return .cyan
        }
    }
}
