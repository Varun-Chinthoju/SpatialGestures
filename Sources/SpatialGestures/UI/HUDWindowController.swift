import AppKit
import SwiftUI

/// AppKit Window Controller managing the transparent, click-through HUD overlay.
public class HUDWindowController: NSWindowController {
    
    public static let shared = HUDWindowController()
    
    private init() {
        // Create a borderless, transparent window large enough to prevent scaling clips
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        
        // Sits above standard apps but below the macOS main menu bar
        window.level = .mainMenu + 1
        
        // CRITICAL: Makes the window click-through so the user can interact with background apps
        window.ignoresMouseEvents = true
        
        // Keep window pinned to the active space and stationary
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        // Wrap our SwiftUI HUD content inside an NSHostingView
        let hostingView = NSHostingView(rootView: HUDWindowContentView())
        window.contentView = hostingView
        
        super.init(window: window)
        
        // Position window at the bottom center of the primary screen
        positionWindowAtBottom()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func positionWindowAtBottom() {
        guard let window = window, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        
        let x = screenFrame.origin.x + (screenFrame.size.width - windowSize.width) / 2
        let y = screenFrame.origin.y + 30 // Sits 30pt above the bottom dock area
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    /// Displays the overlay window.
    public func show() {
        window?.orderFrontRegardless()
    }
    
    /// Hides the overlay window.
    public func hide() {
        window?.orderOut(nil)
    }
}

/// SwiftUI wrapper for the HUD Overlay layout.
struct HUDWindowContentView: View {
    @ObservedObject var tracker = HandTracker.shared
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        let cardSize = CGFloat(320.0 * settings.hudScale)
        
        ZStack {
            if !tracker.trackedHands.isEmpty {
                // Sleek, frosted glassmorphic card backdrop
                RoundedRectangle(cornerRadius: 24 * CGFloat(settings.hudScale))
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24 * CGFloat(settings.hudScale))
                            .stroke(LinearGradient(
                                colors: [themeColor.opacity(0.4), themeColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ), lineWidth: 1.5)
                    )
                    .shadow(color: themeColor.opacity(0.15), radius: 15 * CGFloat(settings.hudScale))
                    .frame(width: cardSize, height: cardSize)
                
                VStack(spacing: 0) {
                    // Real-time Face Gaze Direction indicator
                    if let yaw = tracker.faceYaw {
                        HStack(spacing: 6) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: cardSize * 0.04))
                            Text("Gaze: \(Int(yaw))°")
                                .font(.system(size: cardSize * 0.038, weight: .semibold, design: .rounded))
                            Spacer()
                            Text(gazeLocationDescription)
                                .font(.system(size: cardSize * 0.038, weight: .bold, design: .rounded))
                                .foregroundColor(themeColor)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20 * CGFloat(settings.hudScale))
                        .padding(.top, 16 * CGFloat(settings.hudScale))
                    }
                    
                    ZStack {
                        // Render ALL tracked hands in the HUD!
                        ForEach(0..<tracker.trackedHands.count, id: \.self) { idx in
                            HUDOverlayView(points: tracker.trackedHands[idx])
                                .padding(20 * CGFloat(settings.hudScale))
                        }
                    }
                    .frame(width: cardSize, height: tracker.faceYaw != nil ? cardSize * 0.7 : cardSize * 0.8)
                    
                    if settings.showHUDStatusText {
                        Text(tracker.activeGestureName)
                            .font(.system(size: cardSize * 0.05, weight: .bold, design: .rounded))
                            .foregroundColor(themeColor)
                            .padding(.bottom, 16 * CGFloat(settings.hudScale))
                            .frame(width: cardSize)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .frame(width: cardSize, height: cardSize)
            }
        }
        .frame(width: 600, height: 600)
        .animation(.easeInOut(duration: 0.25), value: !tracker.trackedHands.isEmpty)
    }
    
    private var themeColor: Color {
        switch settings.hudThemeColor {
        case "Green": return .green
        case "Magenta": return .pink
        case "Orange": return .orange
        default: return .cyan
        }
    }
    
    private var gazeLocationDescription: String {
        guard let yaw = tracker.faceYaw else { return "" }
        let loc = settings.monitorLocation
        
        if loc == "Right" && yaw > 12 {
            return "Monitor (Right)"
        } else if loc == "Left" && yaw < -12 {
            return "Monitor (Left)"
        } else if loc == "None" {
            return "Screen"
        } else {
            return "Laptop Screen"
        }
    }
}
