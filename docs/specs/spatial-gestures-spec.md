# Technical Specification: SpatialGestures

## Objective
SpatialGestures is a native macOS utility that runs in the menu bar. It lets users execute system commands (like scrolling, changing spaces, or custom keystrokes) by making hand gestures in front of the FaceTime camera. 
*   **Privacy & Efficiency:** Camera tracking is *only* active while the user holds a designated hotkey (e.g. `Fn` or `Option`).
*   **Interactive Feedback:** Holding the hotkey displays a floating, transparent HUD overlay showing a neon wireframe of the tracked hand joints.
*   **Machine Learning (Template Matching):** Users can train custom gestures by holding a pose for 2 seconds. The app stores normalized 21-point hand landmark coordinates and uses a k-NN/Euclidean distance classifier to match live gestures in real-time.

---

## Tech Stack
*   **Language:** Swift 5.9+
*   **OS Target:** macOS 13.0+ (Ventura+)
*   **Build System:** Swift Package Manager (SPM) with an executable target.
*   **Core Frameworks:**
    *   `SwiftUI` — Settings UI, MenuBarExtra, and the HUD skeleton renderer.
    *   `AppKit` (`Cocoa`) — Custom click-through, borderless transparent HUD window, and system-wide hotkey monitoring.
    *   `Vision` (`VNDetectHumanHandPoseRequest`) — Hand detection and 21-point landmark coordinate extraction.
    *   `AVFoundation` — Managing FaceTime camera capture session.
    *   `CoreGraphics` — Simulating scrolling and keystrokes globally.

---

## Commands
*   **Build the app:** `swift build -c release`
*   **Run the app:** `swift run`
*   **Run tests:** `swift test`

---

## Project Structure
```
.
├── Package.swift                             # SPM Manifest
├── Sources/
│   └── SpatialGestures/
│       ├── SpatialGesturesApp.swift          # Main @main entry, MenuBarExtra, system hotkey monitor
│       ├── Models/
│       │   └── GestureTemplate.swift         # Codable representation of a trained gesture vector
│       ├── Services/
│       │   ├── HandTracker.swift             # AVFoundation & Vision capture pipeline
│       │   ├── GestureClassifier.swift       # Euclidean distance-based comparison logic
│       │   └── ActionBinder.swift            # CoreGraphics scroll and keystroke simulator
│       └── UI/
│           ├── HUDWindowController.swift     # AppKit wrapper for transparent click-through window
│           ├── HUDOverlayView.swift          # SwiftUI neon skeletal mesh drawer
│           └── SettingsView.swift            # SwiftUI setup & interactive training wizard
└── Tests/
    └── SpatialGesturesTests/
        ├── GestureClassifierTests.swift      # Tests template matching accuracy
        └── ActionBinderTests.swift           # Tests event simulation boundaries
```

---

## Code Style
We follow modern Swift guidelines: Swift concurrency (`async`/`await`), structured SwiftUI view layouts, and descriptive type names. 

Example of our style for Core Graphics event generation:
```swift
import Foundation
import CoreGraphics

public struct ActionBinder {
    /// Simulates a system-wide scrolling event.
    /// - Parameter deltaY: The distance and direction to scroll.
    public static func simulateScroll(deltaY: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else { return }
        
        event.post(tap: .cghidEventTap)
    }
}
```

Key Conventions:
*   **Identifiers:** PascalCase for Types, camelCase for variables/functions.
*   **Safety:** Always check Vision request confidence levels before running classification.
*   **Concurrency:** Use `Task` and `@MainActor` properly to keep UI rendering off the camera processing thread.

---

## Testing Strategy
*   **Framework:** XCTest (built-in SPM test framework).
*   **Test Location:** `Tests/SpatialGesturesTests/`
*   **Unit Tests:**
    *   Verify that `GestureClassifier` correctly computes distances and matches a target pose against a database of templates.
    *   Verify the gesture normalization function mathematically scales and shifts coordinates correctly.
*   **Integration Tests:**
    *   Verify settings save/load functionality from disk (JSON serialization of custom gestures).

---

## Boundaries

*   **Always:**
    *   Check permission status before starting `AVCaptureSession`.
    *   Handle camera access denial gracefully (render a help guide in settings).
    *   Deallocate the camera resources when the hotkey is released.
*   **Ask First:**
    *   Adding external Swift package dependencies.
    *   Changing the default target macOS version.
*   **Never:**
    *   Allow the camera session to capture in the background when the hotkey is NOT pressed (critical for privacy and battery).
    *   Run heavy CPU image manipulation on the Main thread.

---

## Success Criteria

1.  **Immediate Activation:** Pressing and holding the designated hotkey starts camera capture and displays the HUD in under **200ms**.
2.  **Skeletal Tracking Visuals:** The HUD displays a real-time, matching wireframe overlay of the user's hand joints with clean visual alignment.
3.  **Low Idle Footprint:** When the hotkey is *not* held, the app consumes **0% CPU** and camera usage indicator is off.
4.  **Template Recording:** The settings panel successfully records, names, and stores a custom gesture vector to disk as JSON.
5.  **Classification Accuracy:** The classifier correctly identifies the recorded gesture and triggers the bound keyboard shortcut within **150ms** of user posing, with a similarity score of >= 85%.
6.  **Teardown:** Releasing the hotkey closes the HUD and stops camera capture instantly.

---

## Open Questions
*   *Resolved:* System notification popups when custom gestures are recognized will be added during the Polish phase.
*   *HUD Positioning:* The HUD overlay will center at the bottom of the screen to minimize visual distraction from active workflows.

