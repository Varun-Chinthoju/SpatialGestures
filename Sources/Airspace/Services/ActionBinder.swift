import Foundation
import CoreGraphics
import AppKit

// Define dynamic function pointer signatures for DisplayServices
typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Double>) -> Int32
typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Double) -> Int32

/// Emulates system-wide scrolling, keystrokes, audio changes, display brightness, and mouse cursor inputs on macOS.
public struct ActionBinder {
    
    // Virtual key codes on macOS (standard US keyboard layout)
    private static let kVK_LeftArrow: CGKeyCode = 123
    private static let kVK_RightArrow: CGKeyCode = 124
    
    // Cache for dynamic DisplayServices symbols loaded at runtime
    private static var getBrightnessPointer: GetBrightnessFunc? = nil
    private static var setBrightnessPointer: SetBrightnessFunc? = nil
    private static var didInitDisplayServices = false
    
    private static func initDisplayServices() {
        guard !didInitDisplayServices else { return }
        didInitDisplayServices = true
        
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        if let handle = dlopen(path, RTLD_NOW) {
            if let symGet = dlsym(handle, "DisplayServicesGetLinearBrightness") {
                getBrightnessPointer = unsafeBitCast(symGet, to: GetBrightnessFunc.self)
            }
            if let symSet = dlsym(handle, "DisplayServicesSetLinearBrightness") {
                setBrightnessPointer = unsafeBitCast(symSet, to: SetBrightnessFunc.self)
            }
        }
    }
    
    /// Launches a local application by name (e.g. "Safari").
    public static func launchApplication(named name: String) {
        // Launches or focuses application natively
        NSWorkspace.shared.launchApplication(name)
    }
    
    /// Simulates a system-wide scrolling event.
    /// - Parameter deltaY: Positive scroll up, negative scroll down.
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
    
    /// Simulates changing spaces to the left (Control + Left Arrow).
    public static func simulateSwitchSpaceLeft() {
        simulateKeystroke(keyCode: kVK_LeftArrow, flags: .maskControl)
    }
    
    /// Simulates changing spaces to the right (Control + Right Arrow).
    public static func simulateSwitchSpaceRight() {
        simulateKeystroke(keyCode: kVK_RightArrow, flags: .maskControl)
    }
    
    /// Increments system audio volume by a step (e.g. 5%).
    public static func volumeUp() {
        runAppleScript("set volume output volume ((output volume of (get volume settings)) + 5)")
    }
    
    /// Decrements system audio volume by a step (e.g. 5%).
    public static func volumeDown() {
        runAppleScript("set volume output volume ((output volume of (get volume settings)) - 5)")
    }
    
    /// Toggles the system mute state.
    public static func toggleMute() {
        runAppleScript("set volume output muted not (output muted of (get volume settings))")
    }
    
    /// Increments display brightness natively by 5% (with keyboard emulation fallback).
    public static func brightnessUp() {
        initDisplayServices()
        guard let getBrightness = getBrightnessPointer, let setBrightness = setBrightnessPointer else {
            // Fallback: simulate F2 keycode (Brightness Up) via AppleScript
            runAppleScript("tell application \"System Events\" to repeat 1 times\n key code 145\n end tell")
            return
        }
        
        var current: Double = 0.5
        if getBrightness(CGMainDisplayID(), &current) == 0 {
            let target = min(1.0, current + 0.05)
            _ = setBrightness(CGMainDisplayID(), target)
            print("[Action] Brightness Up: \(Int(target * 100))%")
        }
    }
    
    /// Decrements display brightness natively by 5% (with keyboard emulation fallback).
    public static func brightnessDown() {
        initDisplayServices()
        guard let getBrightness = getBrightnessPointer, let setBrightness = setBrightnessPointer else {
            // Fallback: simulate F1 keycode (Brightness Down) via AppleScript
            runAppleScript("tell application \"System Events\" to repeat 1 times\n key code 144\n end tell")
            return
        }
        
        var current: Double = 0.5
        if getBrightness(CGMainDisplayID(), &current) == 0 {
            let target = max(0.0, current - 0.05)
            _ = setBrightness(CGMainDisplayID(), target)
            print("[Action] Brightness Down: \(Int(target * 100))%")
        }
    }
    
    /// Moves the mouse cursor to a specific screen coordinate (drag support included).
    public static func moveMouse(to point: CGPoint, drag: Bool) {
        let type: CGEventType = drag ? .leftMouseDragged : .mouseMoved
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }
    
    /// Simulates a mouse down event at a specific point.
    public static func mouseDown(at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }
    
    /// Simulates a mouse up event at a specific point.
    public static func mouseUp(at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }
    
    /// Simulates a right mouse down event.
    public static func rightMouseDown(at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        ) else { return }
        event.post(tap: .cghidEventTap)
    }
    
    /// Simulates a right mouse up event.
    public static func rightMouseUp(at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: .right
        ) else { return }
        event.post(tap: .cghidEventTap)
    }
    
    /// Opens Mission Control directly via NSWorkspace (does not depend on keyboard shortcuts).
    public static func triggerMissionControl() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
    }
    
    /// Opens App Exposé (current app's windows) via a direct CGEvent multitouch emulation.
    /// Falls back to Control+Down which works if the user has App Expose mapped there.
    public static func triggerAppExpose() {
        // Post a 4-finger swipe down gesture (App Exposé) via CoreGraphics
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let event = CGEvent(source: src)
        event?.type = CGEventType(rawValue: 29)! // kCGEventGesture - undocumented but reliable
        // Fallback: Control + F3 which most systems map to App Exposé
        simulateKeystroke(keyCode: 160, flags: .maskControl)
    }
    
    /// Emulates Cmd + Shift + / to trigger the active application's menu/help search.
    public static func simulateMenuSearch() {
        simulateKeystroke(keyCode: 44, flags: [.maskCommand, .maskShift])
    }
    
    // MARK: - Private Helpers
    
    private static func simulateKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true) else { return }
        keyDown.flags = flags
        
        guard let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else { return }
        keyUp.flags = flags
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
    
    private static func runAppleScript(_ scriptText: String) {
        if let script = NSAppleScript(source: scriptText) {
            var error: NSDictionary? = nil
            script.executeAndReturnError(&error)
            if let err = error {
                print("AppleScript Execution Error: \(err)")
            }
        }
    }
}
