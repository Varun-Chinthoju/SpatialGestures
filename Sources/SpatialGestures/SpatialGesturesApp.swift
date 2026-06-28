import SwiftUI
import AppKit
import AVFoundation
import ServiceManagement
import Carbon
import Combine


/// App delegate to configure application presentation policy and start event monitoring on startup.
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var keyMonitor: GlobalKeyMonitor?
    @Published var isTrackingActive = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure settings are pre-loaded once the application has launched
        _ = SettingsManager.shared
        
        // Request both Accessibility and Camera permissions up front on first launch
        requestPermissions()

        
        // Start the global hotkey listener
        let monitor = GlobalKeyMonitor()
        monitor.onHotkeyTriggered = { [weak self] in
            guard let self = self else { return }
            self.toggleTracking()
        }
        
        self.keyMonitor = monitor
        print("SpatialGestures global hotkey listener started.")
    }
    
    private func requestPermissions() {
        // 1. Accessibility — required for global hotkey (CGEventTap) to work system-wide.
        //    Passing prompt:true causes macOS to immediately show the System Settings alert.
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if trusted {
            print("[Permissions] Accessibility: already granted.")
        } else {
            print("[Permissions] Accessibility: not granted — system prompt shown.")
        }
        
        // 2. Camera — required for hand tracking via AVFoundation.
        //    If already determined, this is a no-op. Otherwise the native dialog fires.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("[Permissions] Camera: \(granted ? "granted" : "denied").")
            }
        case .authorized:
            print("[Permissions] Camera: already granted.")
        default:
            print("[Permissions] Camera: denied or restricted.")
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

/// Listens for a custom hotkey globally using Carbon events — works system-wide
class GlobalKeyMonitor {
    private var hotKeyRef: EventHotKeyRef? = nil
    private var eventHandler: EventHandlerRef? = nil
    private var cancellables = Set<AnyCancellable>()
    
    // Local NSEvent monitor as a fallback for when the Settings window is active
    private var localMonitor: Any?
    
    /// Triggered when the registered key combination is pressed.
    var onHotkeyTriggered: (() -> Void)?
    
    init() {
        startMonitoring()
        
        // Re-register hotkey automatically when settings change
        SettingsManager.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.startMonitoring()
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring() {
        stopMonitoring()
        
        let keyCode = UInt32(SettingsManager.shared.hotkeyKeyCode)
        let modifiers = carbonModifiers(from: SettingsManager.shared.hotkeyModifiers)
        
        // EventHotKeyID signature and id
        let hotKeyID = EventHotKeyID(signature: fourCharCode("SPG1"), id: 1)
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        
        // Register the global hotkey at the application target (runs system-wide without permissions)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            print("[GlobalKeyMonitor] Carbon HotKey registered successfully: keycode \(keyCode), mods \(modifiers)")
        } else {
            print("[GlobalKeyMonitor] Carbon HotKey registration failed with error code \(status).")
        }
        
        var eventSpec = EventTypeSpec(
            eventClass: OSType(fourCharCode("keyb")),
            eventKind: UInt32(5) // kEventHotKeyPressed = 5
        )
        
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, event, userData) -> OSStatus in
                if let userData = userData {
                    let monitor = Unmanaged<GlobalKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                    monitor.onHotkeyTriggered?()
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandler
        )
        
        if handlerStatus == noErr {
            print("[GlobalKeyMonitor] Carbon EventHandler installed successfully.")
        } else {
            print("[GlobalKeyMonitor] Carbon EventHandler installation failed with error code \(handlerStatus).")
        }
        
        // Always add a local monitor so the hotkey works when our own Settings window is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.evaluateNSEvent(event)
            return event
        }
    }
    
    func stopMonitoring() {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    private func carbonModifiers(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var carbonMods: UInt32 = 0
        if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
        if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
        if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
        return carbonMods
    }
    
    private func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0
        if string.utf8.count == 4 {
            for char in string.utf8 {
                result = (result << 8) + OSType(char)
            }
        }
        return result
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
