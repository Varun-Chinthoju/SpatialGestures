# Task List: SpatialGestures Implementation

This list defines the step-by-step development process. We will check off tasks sequentially.

---

## Phase A: Project Setup & Core Models

- [ ] **Task 1: Initialize Swift Package Manager (SPM) Project**
  - **Description:** Set up the file structure and build manifest (`Package.swift`) for a macOS executable.
  - **Acceptance:** `Package.swift` builds successfully, targeting macOS 13+, exposing a single executable target `SpatialGestures`.
  - **Verify:** Run `swift build` and check for clean compilation.
  - **Files:** 
    - `Package.swift`
    - `Sources/SpatialGestures/SpatialGesturesApp.swift` (Placeholder main)

- [ ] **Task 2: Define Models & Vector Math Helpers**
  - **Description:** Create the `GestureTemplate` model and normalization helper libraries.
  - **Acceptance:** 
    - `GestureTemplate` holds 21 coordinates (points for hand landmarks).
    - Landmarks center-normalization (setting wrist to (0,0)) and scale-normalization (scaling by hand bounding box) are mathematically implemented.
    - JSON conversion is fully functional.
  - **Verify:** The compiler builds the classes without error.
  - **Files:**
    - `Sources/SpatialGestures/Models/GestureTemplate.swift`

- [ ] **Task 3: Implement Core Unit Tests**
  - **Description:** Write XCTests verifying the distance calculations and normalization routines.
  - **Acceptance:** 
    - Unit tests confirm that coordinates offset and scale normalization outputs remain translation/scale-invariant.
    - Template matching (Euclidean distance) yields high scores for identical templates and low scores for distinct ones.
  - **Verify:** Run `swift test` and ensure all tests pass.
  - **Files:**
    - `Tests/SpatialGesturesTests/GestureClassifierTests.swift`

---

## Phase B: Hand Tracking Pipeline

- [ ] **Task 4: Implement HandTracker & AVCaptureSession**
  - **Description:** Create `HandTracker` using `AVFoundation` and Apple's `Vision` frame processing framework.
  - **Acceptance:**
    - `HandTracker` launches camera capture session.
    - Frame processing hook feeds pixel buffers to `VNDetectHumanHandPoseRequest`.
    - Coordinates are correctly extracted from vision results when confidence is high.
  - **Verify:** Execute compilation and verify no camera API errors.
  - **Files:**
    - `Sources/SpatialGestures/Services/HandTracker.swift`

- [ ] **Task 5: Implement Camera Permission Utility**
  - **Description:** Create checks for user camera settings and permissions.
  - **Acceptance:** Gracefully checks and requests camera access, providing appropriate boolean states to the UI.
  - **Verify:** Test permission states in simulated environment.
  - **Files:**
    - `Sources/SpatialGestures/Services/HandTracker.swift` (Appended)

---

## Phase C: App Lifecycle & Hotkey Trigger

- [ ] **Task 6: Set up Menu Bar UI Structure**
  - **Description:** Configure the application `@main` entry point with a SwiftUI `MenuBarExtra` indicator icon and options.
  - **Acceptance:** The app compiles and can run in the menu bar with options for "Settings", "Active Toggle", and "Quit".
  - **Verify:** Run `swift run`, see the status icon in macOS menu bar.
  - **Files:**
    - `Sources/SpatialGestures/SpatialGesturesApp.swift`

- [ ] **Task 7: Implement Global Hotkey Monitoring**
  - **Description:** Implement global interceptor for key events (e.g. holding `Option` or `Control`).
  - **Acceptance:**
    - Intercepts key down / modifier flags change.
    - Starts the `HandTracker` session immediately on key press.
    - Stops the `HandTracker` session immediately on key release.
  - **Verify:** Log start/stop capture outputs in terminal during key presses.
  - **Files:**
    - `Sources/SpatialGestures/SpatialGesturesApp.swift`

---

## Phase D: HUD Rendering Overlay

- [ ] **Task 8: Implement HUDWindowController transparent overlay**
  - **Description:** Set up custom borderless AppKit overlay window (`NSWindow`) that sits on top of all system windows, allows click-throughs, and behaves as an overlay.
  - **Acceptance:** Window is completely invisible except for its SwiftUI content, cannot be clicked or focused, and loads on top of all active apps.
  - **Verify:** Show a colored rectangle SwiftUI view, verify it displays on top of screen and click events pass straight through it.
  - **Files:**
    - `Sources/SpatialGestures/UI/HUDWindowController.swift`

- [ ] **Task 9: Implement HUDOverlayView neon mesh graphics**
  - **Description:** Design a SwiftUI view that connects the 21 joints of the tracked hand using paths and coordinates supplied by `HandTracker`.
  - **Acceptance:** Displays points for knuckles and lines for fingers with high visual appeal (glassmorphic styling, neon/glow outline).
  - **Verify:** Run mock hand joint coordinates through the view, check visual output.
  - **Files:**
    - `Sources/SpatialGestures/UI/HUDOverlayView.swift`

---

## Phase E: Event Simulation (ActionBinder)

- [ ] **Task 10: Implement CoreGraphics Scroll & Key Simulation**
  - **Description:** Create the `ActionBinder` to programmatically trigger scroll offsets and key shortcuts.
  - **Acceptance:**
    - Simulates scroll up/down events system-wide.
    - Simulates keystroke sequences system-wide.
  - **Verify:** Execute simulated events, verify active target app responds (e.g., volume is adjusted or active document scrolls).
  - **Files:**
    - `Sources/SpatialGestures/Services/ActionBinder.swift`

- [ ] **Task 11: Bind Default Swipe/Wave Gestures**
  - **Description:** Code default heuristics for scrolling (vertical wave) and desktop switching (horizontal wave).
  - **Acceptance:**
    - Wave hand vertically -> triggers scroll events.
    - Wave hand horizontally -> triggers workspace changes.
  - **Verify:** Manual verification under active capture.
  - **Files:**
    - `Sources/SpatialGestures/Services/GestureClassifier.swift`

---

## Phase F: Settings UI & Training Wizard

- [ ] **Task 12: Build SettingsView Layout**
  - **Description:** Implement general SwiftUI layout to toggle active state, adjust sensitivity parameters, and list custom gestures.
  - **Acceptance:** Visually rich UI that saves configurations to `UserDefaults` or JSON configuration file.
  - **Verify:** Changing settings persists variables on app restart.
  - **Files:**
    - `Sources/SpatialGestures/UI/SettingsView.swift`

- [ ] **Task 13: Build Custom Gesture Recording Wizard**
  - **Description:** UI flow that guides the user to record, name, and bind a custom gesture.
  - **Acceptance:** 
    - Counts down (3, 2, 1).
    - Captures a series of coordinate frames.
    - Computes reference centroid vector.
    - Mappings can be bound to key sequences.
  - **Verify:** Perform gesture training flow, check saved JSON config for correct vector.
  - **Files:**
    - `Sources/SpatialGestures/UI/SettingsView.swift` (Appended)
