import SwiftUI
import AppKit
import ServiceManagement

/// App delegate to configure application presentation policy and start event monitoring on startup.
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var keyMonitor: GlobalKeyMonitor?
    @Published var isTrackingActive = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure settings are pre-loaded once the application has launched
        _ = SettingsManager.shared
        
        // Request Accessibility permission — required for global hotkey via CGEventTap
        checkAndRequestAccessibility()
        
        // Start the global hotkey listener
        let monitor = GlobalKeyMonitor()
        monitor.onHotkeyTriggered = { [weak self] in
            guard let self = self else { return }
            self.toggleTracking()
        }
        
        self.keyMonitor = monitor
        print("SpatialGestures global hotkey listener started.")
    }
    
    private func checkAndRequestAccessibility() {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if trusted {
            print("[Accessibility] Process is trusted — global hotkey will work system-wide.")
        } else {
            print("[Accessibility] NOT trusted — global hotkey may not work outside this app. Grant Accessibility in System Settings > Privacy & Security > Accessibility.")
        }
    }
    
    func toggleTracking() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isTrackingActive.toggle()
            if self.isTrackingActive {
                print("Hotkey triggered: activating tracking HUD.")
                HandTracker.shared.startSession()
                HUDWindowController.shared.show()
            } else {
                print("Hotkey triggered: deactivating tracking HUD.")
                HandTracker.shared.stopSession()
                HUDWindowController.shared.hide()
            }
        }
    }
}

/// Listens for a custom hotkey globally using CGEventTap — works system-wide even when
/// other apps are in focus, as long as Accessibility permission is granted.
class GlobalKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Local NSEvent monitor as a fallback for when the Settings window is active
    private var localMonitor: Any?
    
    /// Triggered when the registered key combination is pressed.
    var onHotkeyTriggered: (() -> Void)?
    
    init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring() {
        // CGEventTap: intercepts keyDown events at the HID session level — works in all apps
        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        
        // We need a pointer to self for the C callback
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,           // Listen-only: we don't block or swallow events
            eventsOfInterest: eventMask,
            callback: { _, _, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<GlobalKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                monitor.handleCGEvent(event)
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        )
        
        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("[GlobalKeyMonitor] CGEventTap installed successfully.")
        } else {
            print("[GlobalKeyMonitor] CGEventTap failed — Accessibility permission likely not granted. Falling back to NSEvent global monitor.")
            // Fallback: NSEvent global monitor (works when Accessibility is not granted but is less reliable)
            globalMonitorFallback = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.evaluateNSEvent(event)
            }
        }
        
        // Always add a local monitor so the hotkey works when our own Settings window is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.evaluateNSEvent(event)
            return event
        }
    }
    
    private var globalMonitorFallback: Any?
    
    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        if let monitor = globalMonitorFallback {
            NSEvent.removeMonitor(monitor)
            globalMonitorFallback = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    private func handleCGEvent(_ cgEvent: CGEvent) {
        let keyCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
        let flags = cgEvent.flags
        
        let targetKeyCode = Int64(SettingsManager.shared.hotkeyKeyCode)
        let targetMods = SettingsManager.shared.hotkeyModifiers
        
        // Map NSEvent.ModifierFlags to CGEventFlags
        var requiredFlags: CGEventFlags = []
        if targetMods.contains(.control) { requiredFlags.insert(.maskControl) }
        if targetMods.contains(.option)  { requiredFlags.insert(.maskAlternate) }
        if targetMods.contains(.shift)   { requiredFlags.insert(.maskShift) }
        if targetMods.contains(.command) { requiredFlags.insert(.maskCommand) }
        
        let activeFlags = flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        
        if keyCode == targetKeyCode && activeFlags == requiredFlags {
            onHotkeyTriggered?()
        }
    }
    
    private func evaluateNSEvent(_ event: NSEvent) {
        let targetModifiers = SettingsManager.shared.hotkeyModifiers
        let targetKeyCode = SettingsManager.shared.hotkeyKeyCode
        
        let eventModifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let eventKeyCode = Int(event.keyCode)
        
        if eventModifiers == targetModifiers && eventKeyCode == targetKeyCode {
            onHotkeyTriggered?()
        }
    }
}


@main
struct SpatialGesturesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some Scene {
        // App status item in the Menu Bar (Settings window is managed by SettingsWindowController)
        MenuBarExtra("SpatialGestures", systemImage: "hand.wave") {
            Text(appDelegate.isTrackingActive ? "Tracking: Active" : "Tracking: Paused")
            
            Button(appDelegate.isTrackingActive ? "Pause Tracking" : "Start Tracking") {
                appDelegate.toggleTracking()
            }
            
            Divider()
            
            Text("Shortcut: \(settings.hotkeyDescription)")
            
            Divider()
            
            Button("Settings...") {
                SettingsWindowController.shared.show()
            }
            
            Button(settings.launchAtLogin ? "✓ Launch at Login" : "Launch at Login") {
                settings.launchAtLogin.toggle()
                settings.saveSettings()
                if settings.launchAtLogin {
                    try? SMAppService.mainApp.register()
                } else {
                    try? SMAppService.mainApp.unregister()
                }
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
