# Implementation Plan: SpatialGestures

## Overview
SpatialGestures is a native macOS application that tracks hand gestures from the user's camera (active only when a hotkey like `Option` is held down) to trigger system commands (scrolling, desktop switching, and custom key mapping). It features a real-time HUD rendering a neon skeletal joints mesh and a training wizard to record custom gestures via normalized coordinate distance templates.

## Architecture Decisions
- **Decision 1: Pure Swift SPM Executable Target**
  - *Rationale:* Building via Swift Package Manager avoids binary Xcode project files, which are hard to track in Git and difficult for AI agents to edit. Swift executable packages can launch Cocoa apps and open windows natively since macOS 11+.
- **Decision 2: Key Modifier Flags Monitoring (Option/Control)**
  - *Rationale:* Global hotkeys using carbon event registers or accessibility APIs require invasive user permissions. Monitoring keyboard modifier flags via global AppKit event loops is lightweight, doesn't require accessibility permissions, and matches the "hold key to activate" flow.
- **Decision 3: Core Graphics Event Tap (CGEvent) for Action Simulation**
  - *Rationale:* Generating system-wide scrolls and keyboard shortcuts programmatically is best achieved via low-level `CGEvent` posts, which work universally across all active apps on macOS.
- **Decision 4: k-NN Vector Distance for Gesture Classification**
  - *Rationale:* Dynamically training and compiling machine learning models (like Core ML) on device is slow and resource-heavy. Calculating Euclidean distance between scale- and translation-invariant normalized 21-joint landmark arrays is extremely fast, can run at 60fps, and yields instant on-device training.

---

## Task List

### Phase 1: Foundation

#### Task 1: Initialize SPM Structure
*   **Description:** Set up the file structure and build manifest (`Package.swift`) for a macOS executable.
*   **Acceptance criteria:**
    *   `Package.swift` compiles cleanly targeting macOS 13+.
    *   Exposes a single executable target named `SpatialGestures`.
*   **Verification:**
    *   Build succeeds: Run `swift build`
*   **Dependencies:** None
*   **Files likely touched:**
    *   `Package.swift`
    *   `Sources/SpatialGestures/SpatialGesturesApp.swift`
*   **Estimated scope:** Small (1-2 files)

#### Task 2: Define GestureTemplate & Vector Normalization Math
*   **Description:** Create the `GestureTemplate` model and landmark normalization math. Normalization transforms the 21 3D landmarks coordinates by centering them around the wrist (0, 0, 0) and scaling them based on the hand's overall bounding box width.
*   **Acceptance criteria:**
    *   `GestureTemplate` is Codable and maps a name, action, and landmark vector.
    *   Geometric normalization yields translation- and scale-invariant coordinates.
*   **Verification:**
    *   Build succeeds: Run `swift build`
*   **Dependencies:** Task 1
*   **Files likely touched:**
    *   `Sources/SpatialGestures/Models/GestureTemplate.swift`
*   **Estimated scope:** Small (1-2 files)

#### Task 3: Implement Foundation Unit Tests
*   **Description:** Write unit tests to verify the correctness of normalization math and Euclidean coordinate matching.
*   **Acceptance criteria:**
    *   Vector math tests scale and translate synthetic coordinates and verify the resulting normalized vectors are equal.
    *   Distance matching logic correctly evaluates matching shapes as high similarity and different shapes as low similarity.
*   **Verification:**
    *   Tests pass: Run `swift test`
*   **Dependencies:** Task 2
*   **Files likely touched:**
    *   `Tests/SpatialGesturesTests/GestureClassifierTests.swift`
*   **Estimated scope:** Small (1-2 files)

### Checkpoint: Foundation
- [ ] `swift build` compiles without errors.
- [ ] `swift test` passes all tests.

---

### Phase 2: Hand Tracking & Hotkey Trigger

#### Task 4: Implement HandTracker & Vision Camera Pipeline
*   **Description:** Create the `HandTracker` class that sets up `AVCaptureSession`, handles incoming camera buffers, and runs `VNDetectHumanHandPoseRequest` to extract 21 joint landmark coordinates.
*   **Acceptance criteria:**
    *   Starts camera feed and receives video frame buffers.
    *   Feeds frames to the Vision framework hand detector.
    *   Converts landmarks to normalized `GestureTemplate` coordinate arrays.
*   **Verification:**
    *   Build succeeds: Run `swift build`
*   **Dependencies:** Task 2
*   **Files likely touched:**
    *   `Sources/SpatialGestures/Services/HandTracker.swift`
*   **Estimated scope:** Medium (3-5 files)

#### Task 5: Implement Camera Permission Utility
*   **Description:** Implement check and request logic for camera permissions.
*   **Acceptance criteria:**
    *   Detects if camera permission is granted, denied, or not determined.
    *   Gracefully prompts user for permission if not determined.
*   **Verification:**
    *   Manual verification of authorization states.
*   **Dependencies:** Task 4
*   **Files likely touched:**
    *   `Sources/SpatialGestures/Services/HandTracker.swift`
*   **Estimated scope:** Small (1-2 files)

#### Task 6: Implement Global Modifier Key Hook & App Lifecycle
*   **Description:** Build the `MenuBarExtra` application structure and monitor keyboard modifier changes (e.g. holding `Option` or `Control`) globally.
*   **Acceptance criteria:**
    *   App starts in the menu bar with status icon.
    *   System-wide key listener detects when the hotkey is held down and starting the tracking session.
    *   System-wide key listener detects key release and stops the session.
*   **Verification:**
    *   Manual check: Run `swift run`, hold down the `Option` key, and confirm that logs indicate camera capture starts. Release and confirm it stops.
*   **Dependencies:** Task 5
*   **Files likely touched:**
    *   `Sources/SpatialGestures/SpatialGesturesApp.swift`
*   **Estimated scope:** Medium (3-5 files)

### Checkpoint: Tracking Pipeline
- [ ] App launches into the menu bar.
- [ ] Camera session starts/stops in < 200ms on key hold/release.

---

### Phase 3: HUD UI Overlay

#### Task 7: Implement HUDWindowController transparent overlay
*   **Description:** Create an AppKit `NSWindow` subclass configured to be transparent, borderless, click-through, and layered above all other windows.
*   **Acceptance criteria:**
    *   Saves window parameters to avoid event capture (completely ignores mouse events).
    *   Displays a SwiftUI hosting controller on top of active apps.
*   **Verification:**
    *   Manual check: Renders dummy SwiftUI view on top of other windows. Clicking coordinates passes straight through to active background apps.
*   **Dependencies:** Task 6
*   **Files likely touched:**
    *   `Sources/SpatialGestures/UI/HUDWindowController.swift`
*   **Estimated scope:** Small (1-2 files)

#### Task 8: Implement HUDOverlayView neon joint mesh
*   **Description:** Design the SwiftUI overlay that receives tracked coordinates and renders them as neon points connected by glowing paths representing the fingers.
*   **Acceptance criteria:**
    *   Renders 21 points and connecting finger bones with a futuristic neon-glow styling.
    *   Updates mesh dynamically when new coordinates arrive.
*   **Verification:**
    *   Manual check: Verify wireframe overlay matches active hand shape on screen.
*   **Dependencies:** Task 7
*   **Files likely touched:**
    *   `Sources/SpatialGestures/UI/HUDOverlayView.swift`
*   **Estimated scope:** Small (1-2 files)

### Checkpoint: Visual Overlay
- [ ] Overlay window is properly displayed when hotkey is held.
- [ ] Neon skeletal tracking follows fingers with low latency (<50ms display lag).

---

### Phase 4: Event Simulation & Default Gestures

#### Task 9: Implement ActionBinder Event Simulation
*   **Description:** Write system command triggers using CoreGraphics to emulate vertical scrolling (wheel events) and keystrokes.
*   **Acceptance criteria:**
    *   `simulateScroll(deltaY:)` scrolls active views system-wide.
    *   `simulateKeyPress(keys:)` posts simulated keystrokes.
*   **Verification:**
    *   Manual check: Calling simulation functions moves a browser window or triggers shortcuts.
*   **Dependencies:** Task 6
*   **Files likely touched:**
    *   `Sources/SpatialGestures/Services/ActionBinder.swift`
*   **Estimated scope:** Small (1-2 files)

#### Task 10: Code Default Gestures (Waves)
*   **Description:** Write algorithms to detect simple wave-up, wave-down, wave-left, and wave-right gestures.
*   **Acceptance criteria:**
    *   Calculates vector velocity over consecutive frames to detect hand swipes.
    *   Wave Up/Down maps to page scroll.
    *   Wave Left/Right maps to space changes.
*   **Verification:**
    *   Manual check: Wave hand up/down while holding Option, verify screen scrolls.
*   **Dependencies:** Task 4, Task 9
*   **Files likely touched:**
    *   `Sources/SpatialGestures/Services/GestureClassifier.swift`
*   **Estimated scope:** Medium (3-5 files)

### Checkpoint: Active Default Gestures
- [ ] Horizontal waves switch macOS spaces smoothly.
- [ ] Vertical waves scroll pages naturally.

---

### Phase 5: Settings & Custom Gesture Training

#### Task 11: Implement SettingsView & Config Management
*   **Description:** Design settings window in SwiftUI where users can toggle gestures, adjust scroll speed, and change default hotkey.
*   **Acceptance criteria:**
    *   UI lets user select options.
    *   Persists user selections to a configuration file or `UserDefaults`.
*   **Verification:**
    *   Manual check: Change configs, restart app, verify settings persist.
    *   Build succeeds: Run `swift build`
*   **Dependencies:** Task 6
*   **Files likely touched:**
    *   `Sources/SpatialGestures/UI/SettingsView.swift`
*   **Estimated scope:** Medium (3-5 files)

#### Task 12: Implement Custom Gesture Recorder Wizard
*   **Description:** Create interactive panel where users can trigger recording, name a gesture, hold a pose for 2 seconds, and save the average normalized coordinates vector.
*   **Acceptance criteria:**
    *   Visual countdown (3, 2, 1) and capture loop.
    *   Saves the resulting `GestureTemplate` array as custom user configurations.
    *   Maps template to a keyboard shortcut.
*   **Verification:**
    *   Manual check: Run wizard, record gesture, check output JSON file. Verify that doing the custom gesture triggers the keyboard shortcut.
*   **Dependencies:** Task 11, Task 3, Task 10
*   **Files likely touched:**
    *   `Sources/SpatialGestures/UI/SettingsView.swift`
*   **Estimated scope:** Medium (3-5 files)

### Checkpoint: Complete
- [ ] All unit tests pass.
- [ ] Application builds without warnings.
- [ ] Default gestures and custom trained gestures trigger actions with high accuracy and zero lag.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| **Fn Key Interception** | High | macOS has sandbox constraints blocking Fn key global monitoring. We will use standard Option or Control as fallback hotkeys. |
| **Camera Startup Latency** | High | AVCaptureSession startup can take 500ms. If sluggish, we keep the session active in the background but turn off capture output streams when idle. |
| **Vector Variance** | Medium | Distance math may be sensitive to finger distance or angle. We resolve this by normalizing coordinates relative to the wrist joint and scaling bounds. |

---

## Open Questions
*   *Resolved:* System notification popups when custom gestures are recognized are moved to the Polish phase.
