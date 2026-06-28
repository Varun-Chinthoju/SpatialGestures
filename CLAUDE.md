# SpatialGestures Development Guide

This guide outlines build, test, and run commands, along with coding styles for the **SpatialGestures** project.

## Build and Run Commands

### Building
*   **Compile package targets (development/debug):**
    ```bash
    swift build
    ```
*   **Build the standalone macOS App Bundle (`SpatialGestures.app`):**
    ```bash
    ./build_app.sh
    ```
    This script compiles the project in release mode, generates the app icon, creates the macOS bundle structure, embeds the `Info.plist`, and applies an ad-hoc codesignature.

### Testing
*   **Run unit tests:**
    ```bash
    swift test
    ```

### Running
*   **Run package executable (CLI / developer mode):**
    ```bash
    swift run SpatialGestures
    ```
    *Note: Camera access and accessibility APIs might not work correctly when run directly from the terminal without appropriate permissions.*
*   **Run the macOS App Bundle (recommended):**
    ```bash
    open SpatialGestures.app
    ```

---

## Coding Style & Guidelines

### Swift & Architecture
*   **Language Version:** Swift 5.9+ (utilizing macOS 13+ APIs).
*   **Concurrency:** Use modern Swift concurrency (`async`/`await`, `Task`) or GCD dispatching correctly. Ensure heavy Vision / AVFoundation processing is performed on background queues, and UI updates/accessibility event synthesis occur on the main queue.
*   **Architecture:** Organize code under `Sources/SpatialGestures/` inside the appropriate subdirectories:
    *   `Models/`: Data structures representing gestures, configuration, or actions.
    *   `Services/`: Singleton or core utility classes for hardware/system integration (e.g., [HandTracker.swift](file:///Users/varun/Development/Thrum/Sources/SpatialGestures/Services/HandTracker.swift), [GestureClassifier.swift](file:///Users/varun/Development/Thrum/Sources/SpatialGestures/Services/GestureClassifier.swift), [ActionBinder.swift](file:///Users/varun/Development/Thrum/Sources/SpatialGestures/Services/ActionBinder.swift)).
    *   `UI/`: Lightweight menu bar interfaces, status menus, settings windows, or overlays.
*   **Style Rules:**
    *   Prefer strong typing and enums over raw string constants where possible.
    *   Document public/internal methods, especially logic dealing with gesture coordinates and coordinate mapping.
    *   Keep memory footprint minimal: use `autoreleasepool` blocks if processing large numbers of high-frequency frames or video buffers.
