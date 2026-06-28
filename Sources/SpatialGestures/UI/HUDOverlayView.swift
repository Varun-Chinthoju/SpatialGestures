import SwiftUI

/// Draws a premium, neon-styled skeletal mesh of a tracked hand's 21 joints.
public struct HUDOverlayView: View {
    let points: [Point3D]
    @ObservedObject var settings = SettingsManager.shared
    
    // Joint connections defining the finger bones skeleton structure
    private let boneConnections: [(Int, Int)] = [
        // Thumb
        (0, 1), (1, 2), (2, 3), (3, 4),
        // Index Finger
        (0, 5), (5, 6), (6, 7), (7, 8),
        // Middle Finger
        (0, 9), (9, 10), (10, 11), (11, 12),
        // Ring Finger
        (0, 13), (13, 14), (14, 15), (15, 16),
        // Little Finger
        (0, 17), (17, 18), (18, 19), (19, 20)
    ]
    
    public init(points: [Point3D]) {
        self.points = points
    }
    
    public var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard points.count == 21 else { return }
                
                // Hide skeleton elements if disabled in settings
                guard settings.showHUDSkeleton else { return }
                
                // Translate normalized Vision points ([0.0, 1.0]) to screen coordinates
                let canvasPoints = points.map { p in
                    CGPoint(
                        x: CGFloat(p.x) * size.width,
                        y: CGFloat(1.0 - p.y) * size.height // Flip Y since Vision origin is bottom-left
                    )
                }
                
                let activeColor = themeColor
                
                // 1. Draw connecting bone lines with active theme color glow
                for (startIdx, endIdx) in boneConnections {
                    guard startIdx < canvasPoints.count, endIdx < canvasPoints.count else { continue }
                    let startPoint = canvasPoints[startIdx]
                    let endPoint = canvasPoints[endIdx]
                    
                    var path = Path()
                    path.move(to: startPoint)
                    path.addLine(to: endPoint)
                    
                    // Glow effect: draw thick translucent path under a thin sharp line
                    context.stroke(
                        path,
                        with: .color(activeColor.opacity(0.4)),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    context.stroke(
                        path,
                        with: .color(activeColor),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                }
                
                // 2. Draw knuckles/joint points with glowing dots
                for (index, point) in canvasPoints.enumerated() {
                    let rect = CGRect(
                        x: point.x - 4,
                        y: point.y - 4,
                        width: 8,
                        height: 8
                    )
                    
                    // Highlight finger tips in a different color
                    let isTip = [4, 8, 12, 16, 20].contains(index)
                    let dotColor = isTip ? Color.yellow : (activeColor == .pink ? Color.purple : Color.pink)
                    
                    // Draw glow ring
                    context.stroke(
                        Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                        with: .color(dotColor.opacity(0.4)),
                        lineWidth: 2
                    )
                    // Draw center dot
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(dotColor)
                    )
                }
            }
        }
    }
    
    private var themeColor: Color {
        switch settings.hudThemeColor {
        case "Green": return .green
        case "Magenta": return .pink
        case "Orange": return .orange
        default: return .cyan
        }
    }
}
