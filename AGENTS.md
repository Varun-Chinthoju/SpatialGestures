# Agent Rules for SpatialGestures

This file contains rules, guidelines, and constraints for AI agents working in this repository.

## Development Rules
1.  **Coordinate Mapping:** Always keep hand coordinate translations (e.g., converting normalized camera coords from `0.0 - 1.0` to screen coords) robust to different screen aspect ratios and multi-monitor setups.
2.  **Hardware Performance:** AVCaptureSession initialization can be heavy. Ensure it is handled asynchronously where possible, and do not recreate sessions unnecessarily.
3.  **Synthesizing Events:** When using `CGEvent` to synthesize keystrokes, scroll actions, or mouse movements, check that the process has accessibility permissions (`AXIsProcessTrusted()`) and prompt the user if not trusted.
4.  **Menu Bar Application:** Since this app runs with `LSUIElement = 1` (agent app / status bar menu), keep the UI lightweight. Avoid launching heavy window controllers unless requested.
5.  **Build Validation:** Always verify build integrity using `./build_app.sh` before finalizing changes, to ensure compilation, codesigning, and plist integration succeed.
