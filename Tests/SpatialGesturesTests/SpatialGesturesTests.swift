import XCTest
@testable import SpatialGestures

final class SpatialGesturesTests: XCTestCase {
    
    /// Generates a mock hand structure of 21 joints.
    /// - Parameters:
    ///   - wrist: The starting position of the wrist (index 0).
    ///   - scale: Scale multiplier for the hand size.
    ///   - rotationAngle: Angle in radians to rotate the mock hand on the XY plane.
    private func makeMockHand(wrist: Point3D, scale: Float, rotationAngle: Float) -> [Point3D] {
        var joints: [Point3D] = []
        
        // Let's create base relative offsets for 21 joints
        // Wrist is at (0, 0, 0) relative
        for i in 0..<21 {
            let rx: Float
            let ry: Float
            let rz: Float = Float(i) * 0.02 // small depth variations
            
            if i == 0 {
                rx = 0.0
                ry = 0.0
            } else if i == 9 {
                // Middle MCP: default is straight up (0.0, 0.5)
                rx = 0.0
                ry = 0.5
            } else {
                // General spread for fingers
                rx = Float(i - 10) * 0.05
                ry = Float(i) * 0.03
            }
            
            // Apply scale
            let sx = rx * scale
            let sy = ry * scale
            let sz = rz * scale
            
            // Apply rotation in XY plane
            let rxRotated = sx * cos(rotationAngle) - sy * sin(rotationAngle)
            let ryRotated = sx * sin(rotationAngle) + sy * cos(rotationAngle)
            
            // Apply translation to target wrist position
            joints.append(Point3D(
                x: rxRotated + wrist.x,
                y: ryRotated + wrist.y,
                z: sz + wrist.z
            ))
        }
        
        return joints
    }
    
    /// Verifies that shifting, scaling, and rotating a hand produces the exact same normalized coordinates.
    func testNormalizationInvariance() {
        let wrist1 = Point3D(x: 0.0, y: 0.0, z: 0.0)
        let hand1 = makeMockHand(wrist: wrist1, scale: 1.0, rotationAngle: 0.0)
        
        // Hand 2 is heavily shifted, scaled (5x size), and rotated by 45 degrees (pi/4)
        let wrist2 = Point3D(x: 120.5, y: -45.2, z: 12.0)
        let hand2 = makeMockHand(wrist: wrist2, scale: 5.0, rotationAngle: Float.pi / 4.0)
        
        let norm1 = GestureNormalizer.normalize(hand1)
        let norm2 = GestureNormalizer.normalize(hand2)
        
        XCTAssertEqual(norm1.count, 21)
        XCTAssertEqual(norm2.count, 21)
        
        // Check wrist is at (0,0,0) for both
        XCTAssertEqual(norm1[0].x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(norm1[0].y, 0.0, accuracy: 0.0001)
        XCTAssertEqual(norm1[0].z, 0.0, accuracy: 0.0001)
        
        XCTAssertEqual(norm2[0].x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(norm2[0].y, 0.0, accuracy: 0.0001)
        XCTAssertEqual(norm2[0].z, 0.0, accuracy: 0.0001)
        
        // Check that every normalized point matches between the two configurations
        for i in 0..<21 {
            XCTAssertEqual(norm1[i].x, norm2[i].x, accuracy: 0.001, "X mismatch at joint \(i)")
            XCTAssertEqual(norm1[i].y, norm2[i].y, accuracy: 0.001, "Y mismatch at joint \(i)")
            XCTAssertEqual(norm1[i].z, norm2[i].z, accuracy: 0.001, "Z mismatch at joint \(i)")
        }
    }
    
    /// Verifies that Middle MCP (joint 9) is rotated to point straight up along the positive Y-axis (X = 0, Y > 0).
    func testRotationAlignment() {
        // Create a hand rotated by an arbitrary angle (e.g. 110 degrees)
        let wrist = Point3D(x: 10.0, y: 10.0, z: 0.0)
        let hand = makeMockHand(wrist: wrist, scale: 2.0, rotationAngle: 1.91986) // 110 degrees
        
        let normalized = GestureNormalizer.normalize(hand)
        
        // Middle MCP (index 9) should align on positive Y axis (x = 0, y > 0)
        XCTAssertEqual(normalized[9].x, 0.0, accuracy: 0.001, "Middle MCP should be aligned on X = 0")
        XCTAssertGreaterThan(normalized[9].y, 0.0, "Middle MCP should point positive along Y axis")
    }
    
    /// Verifies that the normalized coordinates are scaled to a maximum joint distance of 1.0.
    func testMaxScaleNormalization() {
        let wrist = Point3D(x: -1.0, y: 2.0, z: 5.0)
        let hand = makeMockHand(wrist: wrist, scale: 0.5, rotationAngle: -0.5)
        
        let normalized = GestureNormalizer.normalize(hand)
        
        let distances = normalized.map { sqrt($0.x * $0.x + $0.y * $0.y + $0.z * $0.z) }
        let maxDistance = distances.max() ?? 0.0
        
        XCTAssertEqual(maxDistance, 1.0, accuracy: 0.0001)
    }
}
