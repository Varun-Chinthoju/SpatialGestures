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
        
        // Start the global hotkey keydown listener
        let monitor = GlobalKeyMonitor()
        monitor.onHotkeyTriggered = { [weak self] in
            guard let self = self else { return }
            self.toggleTracking()
        }
        
        self.keyMonitor = monitor
        print("SpatialGestures global hotkey listener started successfully.")
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

/// Listens for a custom recorded hotkey (modifiers + keycode) globally as a toggle switch.
class GlobalKeyMonitor {
    private var globalMonitor: Any?
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
        // Global monitor for key down events (handles other active applications)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.evaluateEvent(event)
        }
        // Local monitor for key down events (handles when our Settings window is active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.evaluateEvent(event)
            return event
        }
    }
    
    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    private func evaluateEvent(_ event: NSEvent) {
        let targetModifiers = SettingsManager.shared.hotkeyModifiers
        let targetKeyCode = SettingsManager.shared.hotkeyKeyCode
        
        let eventModifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let eventKeyCode = Int(event.keyCode)
        
        // Match both modifiers and keycode
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
