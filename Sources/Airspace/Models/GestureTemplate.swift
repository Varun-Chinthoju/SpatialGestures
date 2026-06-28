import Foundation

/// A 3D coordinate point representation.
public struct Point3D: Codable, Equatable {
    public var x: Float
    public var y: Float
    public var z: Float
    
    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    /// Calculates the Euclidean distance to another point.
    public func distance(to other: Point3D) -> Float {
        let dx = x - other.x
        let dy = y - other.y
        let dz = z - other.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
}

/// The system commands that can be bound to a gesture.
public enum GestureActionType: String, Codable {
    case scrollUp
    case scrollDown
    case nextSpace
    case previousSpace
    case volumeUp
    case volumeDown
    case toggleMute
    case keystroke
    case launchApp
    case menuSearch
}



/// A serialized reference hand gesture containing its normalized coordinate points.
public struct GestureTemplate: Codable, Equatable, Identifiable {
    public var id: String { name }
    
    public let name: String
    public let actionType: GestureActionType
    public let actionData: String?
    public let landmarks: [Point3D]
    
    public init(name: String, actionType: GestureActionType, actionData: String? = nil, landmarks: [Point3D]) {
        self.name = name
        self.actionType = actionType
        self.actionData = actionData
        self.landmarks = landmarks
    }
}

/// Utility for mathematical translation, rotation, and scale normalization of hand landmarks.
public struct GestureNormalizer {
    
    /// Normalizes a set of 21 hand landmarks.
    /// 1. Centers coordinates relative to the wrist (index 0).
    /// 2. Rotates points in the XY plane so the wrist-to-middle-MCP vector points straight up (along +Y axis).
    /// 3. Scales coordinates so the maximum joint distance from the wrist is exactly 1.0.
    public static func normalize(_ points: [Point3D]) -> [Point3D] {
        guard points.count == 21 else { return points }
        
        let wrist = points[0]
        
        // Step 1: Center all coordinates at the wrist (0, 0, 0)
        let translated = points.map { p in
            Point3D(x: p.x - wrist.x, y: p.y - wrist.y, z: p.z - wrist.z)
        }
        
        // Step 2: Rotate around Z-axis so Middle MCP (index 9) aligns with positive Y-axis.
        // Vision Hand Joint indices: 0 = Wrist, 9 = Middle Finger MCP
        let middleMCP = translated[9]
        let currentAngle = atan2(middleMCP.y, middleMCP.x)
        let targetAngle = Float.pi / 2.0 // straight up (90 degrees)
        let rotationAngle = targetAngle - currentAngle
        
        let cosR = cos(rotationAngle)
        let sinR = sin(rotationAngle)
        
        let rotated = translated.map { p in
            let rx = p.x * cosR - p.y * sinR
            let ry = p.x * sinR + p.y * cosR
            return Point3D(x: rx, y: ry, z: p.z) // Keep depth (Z) invariant
        }

        
        // Step 3: Scale so that the furthest point is exactly 1.0 unit away from origin (wrist)
        let maxDistance = rotated.map { sqrt($0.x * $0.x + $0.y * $0.y + $0.z * $0.z) }.max() ?? 1.0
        let scale = maxDistance > 0 ? maxDistance : 1.0
        
        return rotated.map { p in
            Point3D(x: p.x / scale, y: p.y / scale, z: p.z / scale)
        }
    }
}
