# SpatialGestures

SpatialGestures is a native macOS utility that resides in your menu bar and translates spatial hand gestures captured from your webcam (FaceTime camera or external) into system-level inputs (scrolling, desktop space switching, audio volume, display brightness, mouse operations, or custom keystrokes).

Built on top of Apple's Vision and AVFoundation frameworks, the app performs real-time, privacy-first, on-device gesture tracking and classification with minimal CPU overhead.

---

## Features

- **Privacy-First Tracking**: Camera capture is only active while tracking is toggled on (via menu bar or registered global hotkey). When paused, the camera shuts down and CPU usage falls to 0%.
- **Interactive HUD Overlay**: A floating, transparent, click-through HUD window renders a real-time neon wireframe of the tracked hand joints directly on your screen.
- **Smart Face-Proximity Guard**: Uses VNDetectFaceRectanglesRequest to track your head pose and automatically suppresses gesture execution if your hand is too close to your face (preventing false triggers when scratching your head, adjusting glasses, etc.).
- **Air Trackpad Mode**: Complete mouse control using spatial hand coordinates:
  - **Cursor Movement**: Extend your index finger.
  - **Left Click & Drag**: Pinch index finger and thumb together.
  - **Right Click**: Pinch both index and middle fingers to your thumb.
  - **Mission Control / App Exposé**: Extended 3-finger swipe Up or Down.
  - **Circular Pivot Scroll**: 2-finger circular pivot rotation (clockwise to scroll down, counter-clockwise to scroll up).
- **Custom Gesture Training**: Train bespoke gestures in under 2 seconds. The app stores scale- and rotation-invariant 21-joint landmark arrays, matching live poses in real-time using a k-NN/Euclidean distance similarity algorithm.
- **Launch at Login**: Integrates with macOS SMAppService to run seamlessly on startup.

---

## Tech Stack & Architecture

- **Language**: Swift 5.9+
- **OS Target**: macOS 13.0+ (Ventura+)
- **Build System**: Swift Package Manager (SPM)
- **Core Frameworks**:
  - SwiftUI - Settings UI, MenuBarExtra, and HUD skeleton graphics.
  - AppKit (Cocoa) - Custom click-through transparent window overlays and global system-wide hotkey monitoring.
  - Vision (VNDetectHumanHandPoseRequest, VNDetectFaceRectanglesRequest) - Hand landmark extraction and face angle tracking.
  - AVFoundation - Camera capture pipeline control.
  - CoreGraphics - System-wide scrolling, keystroke, and mouse emulation.
  - ServiceManagement - Login launch helper registration.

---

## Project Structure

```text
.
├── Package.swift                             # SPM Manifest
├── build_app.sh                              # Script to build and package into a macOS App Bundle
├── Sources/
│   └── SpatialGestures/
│       ├── SpatialGesturesApp.swift          # App entry point, MenuBarExtra, and global hotkeys
│       ├── Models/
│       │   └── GestureTemplate.swift         # Codable representation of a trained gesture vector
│       ├── Services/
│       │   ├── HandTracker.swift             # AVFoundation & Vision capture pipeline & face proximity
│       │   ├── GestureClassifier.swift       # Euclidean distance-based template matcher & gesture processor
│       │   └── ActionBinder.swift            # CoreGraphics event and AppleScript system actions simulator
│       └── UI/
│           ├── HUDWindowController.swift     # Borderless transparent click-through window
│           ├── HUDOverlayView.swift          # Neon skeletal joint drawer (SwiftUI)
│           └── SettingsView.swift            # Settings view & interactive gesture recorder
└── Tests/
    └── SpatialGesturesTests/
        ├── GestureClassifierTests.swift      # Classification similarity & threshold validation
        └── ActionBinderTests.swift           # Emulation constraints & boundaries validation
```

---

## Getting Started

### Prerequisites
- A Mac running macOS 13.0 (Ventura) or later.
- Xcode 14.0 or later (with Swift 5.9+ toolchain installed).
- A FaceTime camera or connected USB webcam.

### Build and Installation

To compile and package SpatialGestures into a native macOS app bundle:

1. Clone the repository and navigate to the directory:
   ```bash
   git clone https://github.com/Varun-Chinthoju/SpatialGestures.git
   cd SpatialGestures
   ```

2. Run the packaging build script to compile the application and generate the .app bundle:
   ```bash
   chmod +x build_app.sh
   ./build_app.sh
   ```

3. Double-click the generated SpatialGestures.app in your project folder, or drag it into your Applications folder!

### Running Tests

To run unit tests validating the gesture classifier and ActionBinder systems:
```bash
swift test
```

---

## Privacy

SpatialGestures handles all video streams, face pose data, and hand coordinate transformations entirely on your local machine. Video data never leaves the application, and no frames or recording data are saved to disk or transmitted to any external networks.
