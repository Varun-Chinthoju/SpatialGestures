# SpatialGestures — Spec & Blueprint

## Problem Statement
How might we design a lightweight, native macOS menu bar app that uses the FaceTime camera to translate hand gestures into system commands (scrolling, space-switching, and custom user-trained actions) with real-time HUD feedback, an intuitive training interface, and zero background battery drain?

## Recommended Direction
A native SwiftUI + Vision application targeting macOS 13+.
*   **The Menu Bar App:** Lives in the menu bar with a settings panel to toggle gestures, sensitivity, configure the activation key, and manage trained gestures.
*   **The Hold-to-Talk HUD:** Camera/Vision framework starts *only* when the activation hotkey is held. Displays a sleek glassmorphic HUD showing the neon tracking wireframe of the hand.
*   **The Custom Gesture Recorder:** An interactive screen in Settings where the user can record a custom hand pose, save its normalized joint templates, and map it to any macOS keypress or shell script.

---

## MVP Scope

### In-Scope (What We Are Building)
1.  **Menu Bar Status Item:** Access to Settings, Toggle Active State, and Quit.
2.  **Settings & Training Window:** 
    *   Sleek SwiftUI panel to manage settings.
    *   **Custom Gesture Manager:** Create, Delete, and Edit custom gestures.
    *   **Recording Wizard:** Counts down, opens camera, captures reference landmark arrays, and saves them.
3.  **Real-Time Active Overlay HUD:** Click-through window displaying the neon hand tracking mesh.
4.  **Template-Matching Engine:** Nearest-neighbor classification comparing live frames against saved custom templates in real-time.
5.  **Action Binding Engine:** Maps gestures to macOS actions:
    *   Default actions: Scrolling (Wave Up/Down), Desktop Switching (Wave Left/Right).
    *   Custom actions: Simulate keystroke combinations (e.g. `Cmd + Tab`), run custom AppleScript, or trigger shortcuts.

### Not Doing (For the MVP)
*   **Dynamic Gesture Sequences:** We will classify static poses (e.g. making a thumbs-up, peace sign, or open palm) and simple swipe motions, but we won't try to recognize complex spatial paths like drawing circles or cursive writing.
*   **Cloud Syncing:** Gestures saved locally as JSON configurations.

---

## Key Assumptions to Validate
- [ ] **Landmark Consistency:** Does Vision's joint tracking remain consistent enough across different lighting conditions and skin tones to support template matching with a simple Euclidean/Cosine distance formula?
- [ ] **AVCaptureSession Startup Latency:** Can we launch the camera session in < 150ms when the hotkey is pressed?
- [ ] **Global Key Monitoring:** Can we monitor `flagsChanged` events system-wide without requiring macOS Accessibility/Universal Access permissions?

---

## Open Questions
1. Should the HUD overlay appear right at the mouse cursor or centered at the bottom of the screen? (Centered at the bottom of the screen is less disruptive to active work).
