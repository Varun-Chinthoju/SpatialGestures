import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement

/// AppKit window controller to manage custom settings window lifecycle.
public class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()
    
    private var window: NSWindow?
    
    private override init() {
        super.init()
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.minSize = NSSize(width: 820, height: 600)
        
        win.title = "SpatialGestures Settings"
        win.isReleasedWhenClosed = false
        win.center()
        win.delegate = self
        
        let hostingView = NSHostingView(rootView: SettingsView())
        win.contentView = hostingView
        
        self.window = win
    }
    
    public func show() {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Helper to request and verify macOS System Accessibility (Universal Access) permissions.
public struct AccessibilityPermission {
    public static func isGranted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    public static func request() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

/// Manages loading and persisting user settings and custom gesture templates.
public class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    @Published var scrollSensitivity: Double = 35.0
    @Published var enableScroll: Bool = true
    @Published var hotkeyModifiersRaw: UInt = NSEvent.ModifierFlags.option.rawValue
    @Published var hotkeyKeyCode: Int = 49 // Default: Option + Space
    @Published var customTemplates: [GestureTemplate] = []
    
    // HUD Customization settings
    @Published var hudThemeColor: String = "Cyan"
    @Published var showHUDSkeleton: Bool = true
    @Published var showHUDStatusText: Bool = true
    @Published var hudScale: Double = 1.0
    
    // Sensitivity and Cooldown thresholds
    @Published var swipeThreshold: Double = 0.18
    @Published var swipeCooldown: Double = 1.2
    @Published var pinchVolumeThreshold: Double = 0.18
    
    // System integration
    @Published var launchAtLogin: Bool = false
    @Published var monitorLocation: String = "Right"
    
    // Left/Right Hand Mappings & Flat hand control parameters
    @Published var leftHandAction: String = "Brightness"
    @Published var rightHandAction: String = "Volume"
    @Published var enableFlatHandControl: Bool = true
    @Published var elevationThreshold: Double = 0.06
    
    // Air Trackpad settings
    @Published var enableTrackpad: Bool = false
    @Published var trackpadHand: String = "Left"
    @Published var trackpadSpeed: Double = 1.0
    
    // Tracking Mode: "Finger" or "Eye"
    @Published var trackingMode: String = "Finger"
    
    // Multi-monitor: which screen the HUD lives on (stored as localizedName)
    @Published var hudScreen: String = NSScreen.main?.localizedName ?? ""
    
    /// Returns the NSScreen that should host the HUD, falling back to main.
    public var targetScreen: NSScreen {
        return NSScreen.screens.first { $0.localizedName == hudScreen }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
    
    public var hotkeyModifiers: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: hotkeyModifiersRaw)
    }
    
    public var hotkeyDescription: String {
        let flags = hotkeyModifiers
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        
        let name = SettingsManager.keyName(for: hotkeyKeyCode)
        return parts.joined(separator: "") + " " + name
    }
    
    /// Maps macOS hardware keycodes to human-readable labels
    public static func keyName(for keyCode: Int) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Escape"
        case 48: return "Tab"
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        // Character keys
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1: return "S"
        case 17: return "T"
        case 32: return "U"
        case 9: return "V"
        case 13: return "W"
        case 7: return "X"
        case 16: return "Y"
        case 6: return "Z"
        default: return "Key \(keyCode)"
        }
    }
    
    private let fileURL: URL
    
    private init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        self.fileURL = paths[0].appendingPathComponent("spatial_gestures.json")
        loadSettings()
    }
    
    public func saveSettings() {
        let encoder = JSONEncoder()
        
        struct SettingsPayload: Codable {
            let scrollSensitivity: Double
            let enableScroll: Bool
            let hotkeyModifiersRaw: UInt
            let hotkeyKeyCode: Int
            let customTemplates: [GestureTemplate]
            let hudThemeColor: String
            let showHUDSkeleton: Bool
            let showHUDStatusText: Bool
            let hudScale: Double
            let swipeThreshold: Double
            let swipeCooldown: Double
            let pinchVolumeThreshold: Double
            let launchAtLogin: Bool
            let monitorLocation: String
            let leftHandAction: String
            let rightHandAction: String
            let enableFlatHandControl: Bool
            let elevationThreshold: Double
            let enableTrackpad: Bool
            let trackpadHand: String
            let trackpadSpeed: Double
            let hudScreen: String
            let trackingMode: String
        }
        
        let payload = SettingsPayload(
            scrollSensitivity: scrollSensitivity,
            enableScroll: enableScroll,
            hotkeyModifiersRaw: hotkeyModifiersRaw,
            hotkeyKeyCode: hotkeyKeyCode,
            customTemplates: customTemplates,
            hudThemeColor: hudThemeColor,
            showHUDSkeleton: showHUDSkeleton,
            showHUDStatusText: showHUDStatusText,
            hudScale: hudScale,
            swipeThreshold: swipeThreshold,
            swipeCooldown: swipeCooldown,
            pinchVolumeThreshold: pinchVolumeThreshold,
            launchAtLogin: launchAtLogin,
            monitorLocation: monitorLocation,
            leftHandAction: leftHandAction,
            rightHandAction: rightHandAction,
            enableFlatHandControl: enableFlatHandControl,
            elevationThreshold: elevationThreshold,
            enableTrackpad: enableTrackpad,
            trackpadHand: trackpadHand,
            trackpadSpeed: trackpadSpeed,
            hudScreen: hudScreen,
            trackingMode: trackingMode
        )
        
        do {
            let data = try encoder.encode(payload)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
    
    public func loadSettings() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        let decoder = JSONDecoder()
        do {
            let data = try Data(contentsOf: fileURL)
            
            struct SettingsPayload: Codable {
                let scrollSensitivity: Double
                let enableScroll: Bool
                let hotkeyModifiersRaw: UInt
                let hotkeyKeyCode: Int
                let customTemplates: [GestureTemplate]
                let hudThemeColor: String?
                let showHUDSkeleton: Bool?
                let showHUDStatusText: Bool?
                let hudScale: Double?
                let swipeThreshold: Double?
                let swipeCooldown: Double?
                let pinchVolumeThreshold: Double?
                let launchAtLogin: Bool?
                let monitorLocation: String?
                let leftHandAction: String?
                let rightHandAction: String?
                let enableFlatHandControl: Bool?
                let elevationThreshold: Double?
                let enableTrackpad: Bool?
                let trackpadHand: String?
                let trackpadSpeed: Double?
                let hudScreen: String?
                let trackingMode: String?
            }
            
            let payload = try decoder.decode(SettingsPayload.self, from: data)
            self.scrollSensitivity = payload.scrollSensitivity
            self.enableScroll = payload.enableScroll
            self.hotkeyModifiersRaw = payload.hotkeyModifiersRaw
            self.hotkeyKeyCode = payload.hotkeyKeyCode
            self.customTemplates = payload.customTemplates
            
            // Safe fallbacks for backwards compatibility
            self.hudThemeColor = payload.hudThemeColor ?? "Cyan"
            self.showHUDSkeleton = payload.showHUDSkeleton ?? true
            self.showHUDStatusText = payload.showHUDStatusText ?? true
            self.hudScale = payload.hudScale ?? 1.0
            self.swipeThreshold = payload.swipeThreshold ?? 0.18
            self.swipeCooldown = payload.swipeCooldown ?? 1.2
            self.pinchVolumeThreshold = payload.pinchVolumeThreshold ?? 0.18
            self.launchAtLogin = payload.launchAtLogin ?? false
            self.monitorLocation = payload.monitorLocation ?? "Right"
            self.leftHandAction = payload.leftHandAction ?? "Brightness"
            self.rightHandAction = payload.rightHandAction ?? "Volume"
            self.enableFlatHandControl = payload.enableFlatHandControl ?? true
            self.elevationThreshold = payload.elevationThreshold ?? 0.06
            self.enableTrackpad = payload.enableTrackpad ?? false
            self.trackpadHand = payload.trackpadHand ?? "Left"
            self.trackpadSpeed = payload.trackpadSpeed ?? 1.0
            self.hudScreen = payload.hudScreen ?? (NSScreen.main?.localizedName ?? "")
            self.trackingMode = payload.trackingMode ?? "Finger"
        } catch {
            print("Failed to load settings: \(error)")
        }
    }
}

/// The main application Settings view layout.
public struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    
    enum SettingsTab {
        case general
        case airTrackpad
        case customGestures
        case appearance
        case advanced
        case about
    }
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: SettingsTab.general) {
                    Label("General", systemImage: "gearshape")
                }
                NavigationLink(value: SettingsTab.airTrackpad) {
                    Label("Air Trackpad", systemImage: "hand.point.up.left")
                }
                NavigationLink(value: SettingsTab.customGestures) {
                    Label("Custom Gestures", systemImage: "hand.raised.fingers.spread")
                }
                NavigationLink(value: SettingsTab.appearance) {
                    Label("HUD Appearance", systemImage: "paintpalette")
                }
                NavigationLink(value: SettingsTab.advanced) {
                    Label("Advanced Options", systemImage: "slider.horizontal.3")
                }
                NavigationLink(value: SettingsTab.about) {
                    Label("About", systemImage: "info.circle")
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 165, maxWidth: 210)
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsView()
            case .airTrackpad:
                AirTrackpadSettingsView()
            case .customGestures:
                CustomGesturesView()
            case .appearance:
                AppearanceSettingsView()
            case .advanced:
                AdvancedSettingsView()
            case .about:
                AboutSettingsView()
            }
        }
        .frame(minWidth: 820, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
    }
}

// MARK: - Shared Settings Design System

/// Standard card container used by every settings section.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

/// Consistent divider between card rows.
struct CardDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 16)
    }
}

/// Section heading with an SF Symbol icon and accent color.
struct SectionHeader: View {
    let title: String
    let icon: String
    var color: Color = .accentColor

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(color)
            .padding(.top, 6)
    }
}

/// A standard two-column settings row (label left, control right).
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let sub = subtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

/// A slider row with label, live value display, and save-on-change.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var format: (Double) -> String = { "\(Int($0))" }
    var onChanged: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.body)
                Spacer()
                Text(format(value))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 38, alignment: .trailing)
            }
            Slider(value: $value, in: range, step: step)
                .tint(.accentColor)
                .onChange(of: value) { _ in onChanged() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

struct GeneralSettingsView: View {

    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var tracker = HandTracker.shared
    
    @State private var isRecordingHotkey = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ── Activation ─────────────────────────────────────────────────────
                SectionHeader(title: "Activation", icon: "bolt.fill", color: .blue)

                SettingsCard {
                    SettingsRow(
                        title: "Toggle Hotkey",
                        subtitle: "Key combo to enable or disable hand tracking."
                    ) {
                        Button(isRecordingHotkey ? "Press keys…" : settings.hotkeyDescription) {
                            isRecordingHotkey = true
                        }
                        .font(.system(.body, design: .monospaced).bold())
                        .buttonStyle(.bordered)
                        .tint(isRecordingHotkey ? .orange : .accentColor)
                    }
                }

                // ── Hand Mappings ──────────────────────────────────────────────────
                SectionHeader(title: "Hand Action Mappings", icon: "hand.raised.fill", color: .purple)

                SettingsCard {
                    SettingsRow(title: "Left Hand") {
                        Picker("", selection: $settings.leftHandAction) {
                            Text("Brightness").tag("Brightness")
                            Text("Volume").tag("Volume")
                            Text("None").tag("None")
                        }
                        .pickerStyle(.menu).frame(width: 140)
                        .onChange(of: settings.leftHandAction) { _ in settings.saveSettings() }
                    }
                    CardDivider()
                    SettingsRow(title: "Right Hand") {
                        Picker("", selection: $settings.rightHandAction) {
                            Text("Volume").tag("Volume")
                            Text("Brightness").tag("Brightness")
                            Text("None").tag("None")
                        }
                        .pickerStyle(.menu).frame(width: 140)
                        .onChange(of: settings.rightHandAction) { _ in settings.saveSettings() }
                    }
                    CardDivider()
                    SettingsRow(
                        title: "Flat Hand Elevation",
                        subtitle: "Raise/lower a flat open palm to adjust volume or brightness."
                    ) {
                        Toggle("", isOn: $settings.enableFlatHandControl)
                            .toggleStyle(.switch)
                            .onChange(of: settings.enableFlatHandControl) { _ in settings.saveSettings() }
                    }
                    if settings.enableFlatHandControl {
                        CardDivider()
                        SliderRow(
                            title: "Elevation Sensitivity",
                            value: $settings.elevationThreshold,
                            range: 0.02...0.20, step: 0.01,
                            format: { String(format: "%.2f", $0) },
                            onChanged: { settings.saveSettings() }
                        )
                    }
                }

                // ── Fist Scroll ────────────────────────────────────────────────────
                SectionHeader(title: "Fist Scroll", icon: "hand.raised.fingers.spread", color: .teal)

                SettingsCard {
                    SettingsRow(
                        title: "Enable Fist Scrolling",
                        subtitle: "Clench your hand and drag up/down to scroll."
                    ) {
                        Toggle("", isOn: $settings.enableScroll)
                            .toggleStyle(.switch)
                            .onChange(of: settings.enableScroll) { _ in settings.saveSettings() }
                    }
                    if settings.enableScroll {
                        CardDivider()
                        SliderRow(
                            title: "Scroll Speed",
                            value: $settings.scrollSensitivity,
                            range: 10...80, step: 5,
                            onChanged: { settings.saveSettings() }
                        )
                    }
                }

                // ── Monitor Setup ──────────────────────────────────────────────────
                SectionHeader(title: "Monitor Setup", icon: "display.2", color: .cyan)

                SettingsCard {
                    MonitorDiagramView()
                    CardDivider()
                    SettingsRow(
                        title: "External Monitor Position",
                        subtitle: "Where the external monitor sits relative to your laptop."
                    ) {
                        Picker("", selection: $settings.monitorLocation) {
                            Text("None").tag("None")
                            Text("Left of Laptop").tag("Left")
                            Text("Right of Laptop").tag("Right")
                        }
                        .pickerStyle(.menu).frame(width: 150)
                        .onChange(of: settings.monitorLocation) { _ in settings.saveSettings() }
                    }
                    CardDivider()
                    SettingsRow(
                        title: "HUD Display Screen",
                        subtitle: "Which screen the gesture HUD overlay appears on."
                    ) {
                        Picker("", selection: $settings.hudScreen) {
                            ForEach(NSScreen.screens, id: \.localizedName) { screen in
                                let isMain = (screen == NSScreen.main)
                                Text(screen.localizedName + (isMain ? " (Main)" : ""))
                                    .tag(screen.localizedName)
                            }
                        }
                        .pickerStyle(.menu).frame(width: 190)
                        .onChange(of: settings.hudScreen) { _ in
                            settings.saveSettings()
                            HUDWindowController.shared.repositionToTargetScreen()
                        }
                    }
                }

                // ── Device Status ──────────────────────────────────────────────────
                SectionHeader(title: "Device Status", icon: "checkmark.shield.fill", color: .green)

                SettingsCard {
                    SettingsRow(title: "FaceTime Camera") {
                        Label(
                            tracker.cameraAuthorized ? "Connected" : "Access Denied",
                            systemImage: tracker.cameraAuthorized ? "camera.fill" : "camera.slash.fill"
                        )
                        .foregroundStyle(tracker.cameraAuthorized ? .green : .red)
                        .font(.callout.bold())
                    }
                    CardDivider()
                    SettingsRow(title: "Accessibility (Global Hotkey)") {
                        if AXIsProcessTrusted() {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.callout.bold())
                        } else {
                            Button("Open System Settings") {
                                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.small).tint(.orange)
                        }
                    }
                }

                // ── Launch at Login ────────────────────────────────────────────────
                SectionHeader(title: "System Integration", icon: "power", color: .orange)

                SettingsCard {
                    SettingsRow(
                        title: "Launch at Login",
                        subtitle: "Start SpatialGestures automatically when you turn on your Mac."
                    ) {
                        Toggle("", isOn: $settings.launchAtLogin)
                            .toggleStyle(.switch)
                            .onChange(of: settings.launchAtLogin) { _ in
                                settings.saveSettings()
                                if settings.launchAtLogin {
                                    try? SMAppService.mainApp.register()
                                } else {
                                    try? SMAppService.mainApp.unregister()
                                }
                            }
                    }
                }

            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("General Settings")
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if isRecordingHotkey {
                    let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
                    settings.hotkeyModifiersRaw = flags.rawValue
                    settings.hotkeyKeyCode = Int(event.keyCode)
                    settings.saveSettings()
                    isRecordingHotkey = false
                    return nil
                }
                return event
            }
        }
    }
}

struct AirTrackpadSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ── Finger Trackpad Mappings ────────────────────────────────────
                SectionHeader(title: "Finger Trackpad Settings", icon: "hand.point.up.fill", color: .teal)

                SettingsCard {
                    SettingsRow(
                        title: "Enable Air Trackpad",
                        subtitle: "Control mouse cursor with index finger pointing."
                    ) {
                        Toggle("", isOn: $settings.enableTrackpad)
                            .toggleStyle(.switch)
                            .onChange(of: settings.enableTrackpad) { _ in settings.saveSettings() }
                    }
                    if settings.enableTrackpad {
                        CardDivider()
                        SettingsRow(title: "Trackpad Hand") {
                            Picker("", selection: $settings.trackpadHand) {
                                Text("Left Hand").tag("Left")
                                Text("Right Hand").tag("Right")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                            .onChange(of: settings.trackpadHand) { _ in settings.saveSettings() }
                        }
                        CardDivider()
                        SliderRow(
                            title: "Tracking Speed / Sensitivity",
                            value: $settings.trackpadSpeed,
                            range: 0.5...2.5, step: 0.1,
                            format: { String(format: "%.1fx", $0) },
                            onChanged: { settings.saveSettings() }
                        )
                    }
                }

                // Section 2: Instructions (with Info symbol)
                VStack(alignment: .leading, spacing: 10) {
                    Label("How to Use", systemImage: "info.circle.fill")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "hand.point.up.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Point to Move")
                                    .font(.body)
                                    .bold()
                                Text("Point exactly one finger (your index finger extended, other fingers curled) and move it to slide the cursor relative to its position.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Clutch to Pause (Fist)")
                                    .font(.body)
                                    .bold()
                                Text("Clench your hand into a fist to temporarily lock the cursor. Move your arm back to center, then reopen your index finger to resume moving.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "hand.tap.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Left & Right Click")
                                    .font(.body)
                                    .bold()
                                Text("• Left Click: Pinch your index finger and thumb together.\n• Right Click: Pinch index, middle, and thumb together.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.up.and.down.text.horizontal")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Scroll")
                                    .font(.body)
                                    .bold()
                                Text("Extend exactly two fingers (index and middle) and move your hand up or down to scroll pages.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.up.and.down.and.sparkles")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("System Swipes (3 Fingers)")
                                    .font(.body)
                                    .bold()
                                Text("Raise exactly three fingers (index, middle, and ring) and rotate your wrist to trigger Mission Control or App Exposé.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Air Trackpad Settings")
    }
}

struct CustomGesturesView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var showRecordingWizard = false
    @State private var editingTemplate: GestureTemplate? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Custom Gestures")
                    .font(.title)
                    .bold()
                Spacer()
                Button(action: { showRecordingWizard = true }) {
                    Label("Record New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 16)
            
            Divider()
            
            if settings.customTemplates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hand.wave")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No custom gestures trained yet.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Train a new pose to trigger applications or commands.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                List {
                    ForEach(settings.customTemplates) { template in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                    .font(.headline)
                                HStack(spacing: 8) {
                                    Image(systemName: template.actionType == .launchApp ? "arrow.up.forward.app" : "keyboard")
                                        .font(.caption)
                                    Text("Triggers: \(template.actionType.rawValue)\(template.actionData != nil ? " (\(template.actionData!))" : "")")
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Button("Edit") {
                                    editingTemplate = template
                                }
                                .buttonStyle(.bordered)
                                
                                Button(role: .destructive) {
                                    if let idx = settings.customTemplates.firstIndex(of: template) {
                                        settings.customTemplates.remove(at: idx)
                                        settings.saveSettings()
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Custom Gestures")
        .sheet(isPresented: $showRecordingWizard) {
            RecordingWizardView(isPresented: $showRecordingWizard)
        }
        .sheet(item: $editingTemplate) { template in
            EditGestureView(template: template, isPresented: Binding(
                get: { editingTemplate != nil },
                set: { newValue in if !newValue { editingTemplate = nil } }
            ))
        }
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ── Styling & Theme ───────────────────────────────────────────────
                SectionHeader(title: "Styling & Theme", icon: "paintpalette.fill", color: .purple)

                SettingsCard {
                    SettingsRow(title: "HUD Theme Color") {
                        Picker("", selection: $settings.hudThemeColor) {
                            Text("Cyan").tag("Cyan")
                            Text("Green").tag("Green")
                            Text("Magenta").tag("Magenta")
                            Text("Orange").tag("Orange")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        .onChange(of: settings.hudThemeColor) { _ in settings.saveSettings() }
                    }
                    CardDivider()
                    SettingsRow(
                        title: "Show Skeleton Joints",
                        subtitle: "Render circles for skeletal joints in the HUD hand overlay."
                    ) {
                        Toggle("", isOn: $settings.showHUDSkeleton)
                            .toggleStyle(.switch)
                            .onChange(of: settings.showHUDSkeleton) { _ in settings.saveSettings() }
                    }
                    CardDivider()
                    SettingsRow(
                        title: "Show Gesture Status Text",
                        subtitle: "Display recognized gesture names at the bottom of the HUD card."
                    ) {
                        Toggle("", isOn: $settings.showHUDStatusText)
                            .toggleStyle(.switch)
                            .onChange(of: settings.showHUDStatusText) { _ in settings.saveSettings() }
                    }
                }

                // ── HUD Dimensions ────────────────────────────────────────────────
                SectionHeader(title: "HUD Dimensions", icon: "arrow.up.left.and.arrow.down.right", color: .blue)

                SettingsCard {
                    SliderRow(
                        title: "HUD Window Scale",
                        value: $settings.hudScale,
                        range: 0.6...1.4, step: 0.1,
                        format: { String(format: "%.1fx", $0) },
                        onChanged: { settings.saveSettings() }
                    )
                }

            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("HUD Appearance")
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    @State private var isAccessibilityGranted = AccessibilityPermission.isGranted()
    private let permissionTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Advanced Settings")
                    .font(.title)
                    .bold()
                    .padding(.bottom, 10)
                
                // Section 1: Flat Hand elevation controls
                VStack(alignment: .leading, spacing: 10) {
                    Text("Flat Hand Elevation")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable Flat Hand Elevation")
                                    .font(.body)
                                Text("Raise/lower flat open palm vertically to adjust volume or brightness.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $settings.enableFlatHandControl)
                                .toggleStyle(.switch)
                                .onChange(of: settings.enableFlatHandControl) { _ in settings.saveSettings() }
                        }
                        .padding(12)
                        
                        if settings.enableFlatHandControl {
                            Divider().padding(.horizontal, 12)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Elevation Motion Sensitivity")
                                    Spacer()
                                    Text(String(format: "%.2f", settings.elevationThreshold))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $settings.elevationThreshold, in: 0.02...0.15, step: 0.01)
                                    .onChange(of: settings.elevationThreshold) { _ in settings.saveSettings() }
                            }
                            .padding(12)
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }
                
                // Section 2: Sensitivity Thresholds
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sensitivity Thresholds")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 0) {
                        // Swipe Sensitivity
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Swipe Motion Sensitivity")
                                Spacer()
                                Text(String(format: "%.2f", settings.swipeThreshold))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.swipeThreshold, in: 0.08...0.30, step: 0.02)
                                .onChange(of: settings.swipeThreshold) { _ in settings.saveSettings() }
                        }
                        .padding(12)
                        
                        Divider().padding(.horizontal, 12)
                        
                        // Swipe Cooldown
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Swipe Cooldown Delay")
                                Spacer()
                                Text(String(format: "%.1fs", settings.swipeCooldown))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.swipeCooldown, in: 0.5...3.0, step: 0.1)
                                .onChange(of: settings.swipeCooldown) { _ in settings.saveSettings() }
                        }
                        .padding(12)
                        
                        Divider().padding(.horizontal, 12)
                        
                        // Pinch Volume control
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Volume/Brightness Pinch Sensitivity")
                                Spacer()
                                Text(String(format: "%.2f", settings.pinchVolumeThreshold))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.pinchVolumeThreshold, in: 0.08...0.30, step: 0.02)
                                .onChange(of: settings.pinchVolumeThreshold) { _ in settings.saveSettings() }
                        }
                        .padding(12)
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }
                
                // Section 3: Login Integration
                VStack(alignment: .leading, spacing: 10) {
                    Text("System Integration")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Launch at Login")
                                    .font(.body)
                                Text("Start SpatialGestures automatically when you turn on your Mac.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $settings.launchAtLogin)
                                .toggleStyle(.switch)
                                .onChange(of: settings.launchAtLogin) { newValue in
                                    settings.saveSettings()
                                    updateLaunchAtLogin(newValue)
                                }
                        }
                        .padding(12)
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }
                
                // Section 4: OS Controls Access
                VStack(alignment: .leading, spacing: 10) {
                    Text("System Accessibility")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 0) {
                        HStack {
                            Label("Accessibility Control", systemImage: "accessibility")
                                .font(.body)
                            Spacer()
                            Text(isAccessibilityGranted ? "Granted" : "Required")
                                .foregroundColor(isAccessibilityGranted ? .green : .red)
                                .bold()
                        }
                        .padding(12)
                        
                        if !isAccessibilityGranted {
                            Divider().padding(.horizontal, 12)
                            
                            HStack {
                                Text("Accessibility is required to simulate mouse scrolling and keystrokes.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Grant Access...") {
                                    _ = AccessibilityPermission.request()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                            .padding(12)
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Advanced Options Settings")
        .onReceive(permissionTimer) { _ in
            isAccessibilityGranted = AccessibilityPermission.isGranted()
        }
    }
    
    private func updateLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Try loading the actual app icon bundle resource, fallback to system image if command-line testing
            if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
               let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.15), radius: 10)
            } else {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 6) {
                Text("SpatialGestures")
                    .font(.title)
                    .bold()
                
                Text("Version 1.0.0 (Build 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Skeletally-tracked, zero-touch gesture inputs for macOS, leveraging native Apple Vision hand-pose estimation models and ad-hoc event simulation.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Divider().frame(width: 200).padding(.vertical, 10)
            
            VStack(spacing: 4) {
                Text("Created by Varun Chinthoju")
                    .font(.body)
                    .bold()
                Text("A 9th grader who codes for fun")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("About SpatialGestures")
    }
}

struct RecordingWizardView: View {
    @Binding var isPresented: Bool
    @ObservedObject var tracker = HandTracker.shared
    @ObservedObject var settings = SettingsManager.shared
    
    @State private var gestureName = ""
    @State private var actionType = GestureActionType.toggleMute
    @State private var targetAppName = "Safari"
    
    @State private var countdown = 0
    @State private var isRecording = false
    @State private var recordBuffer: [[Point3D]] = []
    @State private var infoMessage = "Ready to record"
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Record Custom Gesture")
                .font(.title2)
                .bold()
            
            VStack(alignment: .leading, spacing: 8) {
                TextField("Gesture Name (e.g. Thumbs Up)", text: $gestureName)
                    .textFieldStyle(.roundedBorder)
                
                Picker("Action To Bind", selection: $actionType) {
                    Section(header: Text("System Actions")) {
                        Text("Toggle Mute").tag(GestureActionType.toggleMute)
                        Text("Volume Up").tag(GestureActionType.volumeUp)
                        Text("Volume Down").tag(GestureActionType.volumeDown)
                        Text("Trigger Menu Search").tag(GestureActionType.menuSearch)
                    }
                    Section(header: Text("Applications")) {
                        Text("Open Application").tag(GestureActionType.launchApp)
                    }
                }
                
                if actionType == .launchApp {
                    TextField("Application Name (e.g. Spotify)", text: $targetAppName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal)
            
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.85))
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    )
                
                if let hand = tracker.trackedHand {
                    HUDOverlayView(points: hand)
                        .padding(16)
                } else {
                    Text("No hand in camera view")
                        .foregroundColor(.secondary)
                }
                
                if countdown > 0 {
                    Text("\(countdown)")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(.cyan)
                        .transition(.scale)
                } else if isRecording {
                    Text("HOLD POSE!")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.pink)
                }
            }
            .padding(.horizontal)
            
            Text(infoMessage)
                .font(.callout)
                .foregroundColor(isRecording ? .pink : .secondary)
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    tracker.stopSession()
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Button("Start Training") {
                    startTrainingFlow()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(gestureName.isEmpty || countdown > 0 || isRecording)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 400, height: 450)
        .onAppear {
            tracker.startSession()
        }
        .onDisappear {
            tracker.stopSession()
        }
        .onReceive(timer) { _ in
            if countdown > 0 {
                countdown -= 1
                if countdown == 0 {
                    startCaptureSession()
                }
            }
        }
        .onChange(of: tracker.trackedHand) { newHand in
            if isRecording, let hand = newHand {
                recordBuffer.append(hand)
            }
        }
    }
    
    private func startTrainingFlow() {
        countdown = 3
        infoMessage = "Get ready..."
        recordBuffer.removeAll()
    }
    
    private func startCaptureSession() {
        isRecording = true
        infoMessage = "Recording pose... hold still!"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.finalizeRecording()
        }
    }
    
    private func finalizeRecording() {
        isRecording = false
        
        guard recordBuffer.count > 5 else {
            infoMessage = "Failed to capture hand coordinates. Hold hand steady."
            return
        }
        
        var averageJoints: [Point3D] = []
        let frameCount = Float(recordBuffer.count)
        
        for jointIdx in 0..<21 {
            var sumX: Float = 0.0
            var sumY: Float = 0.0
            for frame in recordBuffer {
                sumX += frame[jointIdx].x
                sumY += frame[jointIdx].y
            }
            averageJoints.append(Point3D(x: sumX / frameCount, y: sumY / frameCount, z: 0.0))
        }
        
        let normalized = GestureNormalizer.normalize(averageJoints)
        
        let template = GestureTemplate(
            name: gestureName,
            actionType: actionType,
            actionData: actionType == .launchApp ? targetAppName : nil,
            landmarks: normalized
        )
        
        settings.customTemplates.append(template)
        settings.saveSettings()
        
        infoMessage = "Successfully trained gesture: \(gestureName)!"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isPresented = false
        }
    }
}

/// Allows the user to reconfigure an existing gesture's name, action type, and parameters.
struct EditGestureView: View {
    let template: GestureTemplate
    @Binding var isPresented: Bool
    @ObservedObject var settings = SettingsManager.shared
    
    @State private var gestureName = ""
    @State private var actionType = GestureActionType.toggleMute
    @State private var targetAppName = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Custom Gesture")
                .font(.title2)
                .bold()
            
            VStack(alignment: .leading, spacing: 12) {
                TextField("Gesture Name", text: $gestureName)
                    .textFieldStyle(.roundedBorder)
                
                Picker("Action To Bind", selection: $actionType) {
                    Section(header: Text("System Actions")) {
                        Text("Toggle Mute").tag(GestureActionType.toggleMute)
                        Text("Volume Up").tag(GestureActionType.volumeUp)
                        Text("Volume Down").tag(GestureActionType.volumeDown)
                        Text("Trigger Menu Search").tag(GestureActionType.menuSearch)
                    }
                    Section(header: Text("Applications")) {
                        Text("Open Application").tag(GestureActionType.launchApp)
                    }
                }
                
                if actionType == .launchApp {
                    TextField("Application Name (e.g. Spotify)", text: $targetAppName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Trained Pose Preview")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.85))
                        .frame(height: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    
                    HUDOverlayView(points: template.landmarks)
                        .padding(16)
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Button("Save Changes") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(gestureName.isEmpty)
            }
            .padding(.bottom, 16)
        }
        .frame(width: 400, height: 500)
        .padding(20)
        .onAppear {
            gestureName = template.name
            actionType = template.actionType
            targetAppName = template.actionData ?? ""
        }
    }
    
    private func saveChanges() {
        if let idx = settings.customTemplates.firstIndex(where: { $0.id == template.id }) {
            let updated = GestureTemplate(
                name: gestureName,
                actionType: actionType,
                actionData: actionType == .launchApp ? targetAppName : nil,
                landmarks: template.landmarks
            )
            settings.customTemplates[idx] = updated
            settings.saveSettings()
        }
        isPresented = false
    }
}

// MARK: - Live Monitor Diagram

/// Visual diagram showing all connected NSScreens laid out relative to each other,
/// with the HUD target screen highlighted.
struct MonitorDiagramView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    // Refresh when screens change (plug/unplug)
    @State private var screens: [NSScreen] = NSScreen.screens
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "display.2")
                    .foregroundColor(.secondary)
                Text("Connected Displays")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(screens.count) screen\(screens.count == 1 ? "" : "s") detected")
                    .font(.caption)
                    .foregroundColor(screens.count > 1 ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(screens.count > 1 ? Color.green.opacity(0.12) : Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            // Draw a miniature layout of all screens using their actual frame positions
            GeometryReader { geo in
                let diagramPadding: CGFloat = 16
                let availableW = geo.size.width - diagramPadding * 2
                let availableH = geo.size.height - diagramPadding * 2
                
                // Compute the union bounding rect of all screens
                let allFrames = screens.map { $0.frame }
                let minX = allFrames.map { $0.minX }.min() ?? 0
                let minY = allFrames.map { $0.minY }.min() ?? 0
                let maxX = allFrames.map { $0.maxX }.max() ?? 1
                let maxY = allFrames.map { $0.maxY }.max() ?? 1
                let totalW = maxX - minX
                let totalH = maxY - minY
                
                let scaleX = availableW / totalW
                let scaleY = availableH / totalH
                let scale = min(scaleX, scaleY) * 0.85
                
                // Center the whole layout
                let layoutW = totalW * scale
                let layoutH = totalH * scale
                let offsetX = diagramPadding + (availableW - layoutW) / 2
                let offsetY = diagramPadding + (availableH - layoutH) / 2
                
                ZStack {
                    ForEach(screens, id: \.localizedName) { screen in
                        let f = screen.frame
                        let isMain = (screen == NSScreen.main)
                        let isHUDTarget = (screen.localizedName == settings.hudScreen) ||
                                         (settings.hudScreen == "Main" && isMain)
                        
                        let x = (f.minX - minX) * scale + offsetX
                        // NSScreen Y is bottom-up, flip for screen coords
                        let y = (maxY - f.maxY) * scale + offsetY
                        let w = f.width * scale
                        let h = f.height * scale
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isHUDTarget
                                    ? Color.cyan.opacity(0.18)
                                    : Color(NSColor.controlBackgroundColor).opacity(0.8))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isHUDTarget ? Color.cyan : Color.gray.opacity(0.4),
                                        lineWidth: isHUDTarget ? 2 : 1)
                            
                            VStack(spacing: 2) {
                                if isMain {
                                    Image(systemName: "laptopcomputer")
                                        .font(.system(size: min(w, h) * 0.18))
                                        .foregroundColor(isHUDTarget ? .cyan : .secondary)
                                } else {
                                    Image(systemName: "display")
                                        .font(.system(size: min(w, h) * 0.18))
                                        .foregroundColor(isHUDTarget ? .cyan : .secondary)
                                }
                                
                                Text(screen.localizedName)
                                    .font(.system(size: min(w * 0.14, 9)))
                                    .foregroundColor(isHUDTarget ? .cyan : .primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                                Text("\(Int(f.width))x\(Int(f.height))")
                                    .font(.system(size: min(w * 0.11, 8)))
                                    .foregroundColor(.secondary)
                                
                                if isHUDTarget {
                                    Text("HUD Here")
                                        .font(.system(size: min(w * 0.11, 7), weight: .bold))
                                        .foregroundColor(.cyan)
                                }
                            }
                        }
                        .frame(width: w, height: h)
                        .position(x: x + w / 2, y: y + h / 2)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(height: 110)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
            // If currently selected screen disappeared, fall back to main
            if !screens.contains(where: { $0.localizedName == settings.hudScreen }) {
                settings.hudScreen = NSScreen.main?.localizedName ?? "Main"
                settings.saveSettings()
            }
            HUDWindowController.shared.repositionToTargetScreen()
        }
    }
}

