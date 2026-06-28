import Foundation
import AppKit

/// Mathematical classifier that computes Euclidean distances between normalized hand coordinates.
public class GestureClassifier {
    
    private static let maxExpectedDistance: Float = 4.0
    
    /// Computes similarity index (0.0 to 1.0) between two normalized coordinate sets.
    public static func similarity(between livePoints: [Point3D], and templatePoints: [Point3D]) -> Float {
        guard livePoints.count == 21 && templatePoints.count == 21 else {
            return 0.0
        }
        
        var totalDistance: Float = 0.0
        for i in 0..<21 {
            totalDistance += livePoints[i].distance(to: templatePoints[i])
        }
        
        let score = 1.0 - (totalDistance / maxExpectedDistance)
        return max(0.0, min(1.0, score))
    }
    
    /// Checks a live normalized joint set against all custom templates and returns the closest match.
    public static func classify(livePoints: [Point3D], against templates: [GestureTemplate], threshold: Float = 0.82) -> GestureTemplate? {
        guard livePoints.count == 21 else { return nil }
        
        var bestMatch: GestureTemplate? = nil
        var highestScore: Float = 0.0
        
        for template in templates {
            let score = similarity(between: livePoints, and: template.landmarks)
            if score >= threshold && score > highestScore {
                highestScore = score
                bestMatch = template
            }
        }
        
        return bestMatch
    }
}

/// Processes real-time hand joints and classifies them into system actions.
public class GestureProcessor {
    
    public static let shared = GestureProcessor()
    
    /// Holds coordinate history and state variables for an individual hand to support independent dual-hand tracking.
    private class HandState {
        var historyX: [Float] = []
        var historyY: [Float] = []
        let historyLimit = 10
        
        var spaceSwitchCooldown = Date.distantPast
        var customGestureCooldown = Date.distantPast
        
        // Pinch sliding states
        var isCurrentlyPinching = false
        var pinchStartY: Float = 0.0
        
        // Flat hand elevation states
        var isCurrentlyElevating = false
        var elevationStartY: Float = 0.0
        
        // Air Trackpad mouse states
        var wasPinchingForMouse = false
        var wasRightPinching = false
        
        // Relative mouse coordinates
        var lastIndexX: Float? = nil
        var lastIndexY: Float? = nil
        var smoothDeltaX: Float = 0.0
        var smoothDeltaY: Float = 0.0
        
        // Circular scrolling angle (2-finger scroll)
        var lastScrollAngle: Float? = nil
        
        // Circular swipe angle (3-finger Mission Control / Exposé) - kept separate from scroll
        var swipeAngle: Float? = nil
        
        // Accumulated rotation for 3-finger circular swipe
        var swipeAccumulator: Float = 0.0
        
        // Linear vertical swipe states (3-finger vertical motion)
        var lastSwipeY: Float? = nil
        var swipeAccumulatorY: Float = 0.0
        
        // Pinch click-vs-drag states
        var pinchStartCursorLocation: CGPoint? = nil
        var isDragActive = false
        
        // Debounce frame counters to prevent transient transition triggers
        var threeFingerFrameCount = 0
        var twoFingerFrameCount = 0
        
        func reset() {
            historyX.removeAll()
            historyY.removeAll()
            isCurrentlyPinching = false
            isCurrentlyElevating = false
            wasPinchingForMouse = false
            wasRightPinching = false
            lastIndexX = nil
            lastIndexY = nil
            smoothDeltaX = 0.0
            smoothDeltaY = 0.0
            lastScrollAngle = nil
            swipeAngle = nil
            swipeAccumulator = 0.0
            lastSwipeY = nil
            swipeAccumulatorY = 0.0
            pinchStartCursorLocation = nil
            isDragActive = false
            threeFingerFrameCount = 0
            twoFingerFrameCount = 0
        }
    }
    
    private let leftHandState = HandState()
    private let rightHandState = HandState()
    
    private init() {}
    
    /// Processes a single frame of 21 hand joints coordinates.
    public func processFrame(_ points: [Point3D], isLeft: Bool) {
        guard points.count == 21 else { return }
        
        let state = isLeft ? leftHandState : rightHandState
        
        // 1. If this hand is the designated Air Trackpad, route control entirely to mouse emulations
        let isTrackpadHand = SettingsManager.shared.enableTrackpad && 
                             ((isLeft && SettingsManager.shared.trackpadHand == "Left") || 
                              (!isLeft && SettingsManager.shared.trackpadHand == "Right"))
        
        // 2. Compute scale- and rotation-invariant normalized joints
        let normalized = GestureNormalizer.normalize(points)
        
        if isTrackpadHand {
            // Track Y movement for 3-finger swipes and 2-finger scrolls
            let wrist = points[0]
            state.historyY.append(wrist.y)
            if state.historyY.count > state.historyLimit {
                state.historyY.removeFirst()
            }
            
            _ = evaluateAirTrackpad(points, normalized: normalized, state: state)
            return
        }
        
        // 3. Track motion velocity using raw Wrist coordinates (index 0)
        let wrist = points[0]
        state.historyX.append(wrist.x)
        state.historyY.append(wrist.y)
        if state.historyX.count > state.historyLimit {
            state.historyX.removeFirst()
            state.historyY.removeFirst()
        }
        
        // 4. Process custom trained gestures FIRST
        let matchedCustom = evaluateCustomGestures(normalized, state: state)
        if matchedCustom {
            return
        }
        
        // 5. Process default actions only if no custom gesture is active
        var activeText = "Tracking Hand..."
        
        let handAction = isLeft ? SettingsManager.shared.leftHandAction : SettingsManager.shared.rightHandAction
        
        var isScrolling = false
        if SettingsManager.shared.enableScroll {
            isScrolling = evaluateVerticalScrolling(normalized, state: state)
        }
        
        let isSwiping = evaluateHorizontalSwipes(state: state)
        
        // Evaluate dynamic Flat Hand Elevation and Pinch Control based on settings
        var isElevating = false
        var isPinching = false
        
        if handAction != "None" {
            isElevating = evaluateFlatHandElevation(points, normalized: normalized, action: handAction, state: state)
            if !isElevating {
                isPinching = evaluatePinchControl(normalized, action: handAction, state: state)
            }
        }
        
        if isScrolling {
            activeText = "Scrolling..."
        } else if isSwiping {
            activeText = "Desktop Swipe"
        } else if isElevating {
            activeText = "\(handAction) Elevate"
        } else if isPinching {
            activeText = "\(handAction) Pinch"
        }
        
        let targetText = activeText
        DispatchQueue.main.async {
            HandTracker.shared.activeGestureName = targetText
        }
    }
    
    /// Resets history buffers (e.g. when camera starts or stops).
    public func resetHistory() {
        leftHandState.reset()
        rightHandState.reset()
    }
    
    // MARK: - Gesture Heuristic Classifiers
    
    private func evaluateAirTrackpad(_ points: [Point3D], normalized: [Point3D], state: HandState) -> Bool {
        // Evaluate finger curl lengths
        let indexLen = normalized[8].distance(to: normalized[5])
        let middleLen = normalized[12].distance(to: normalized[9])
        let ringLen = normalized[16].distance(to: normalized[13])
        let littleLen = normalized[20].distance(to: normalized[17])
        
        let thumbTipNorm = normalized[4]
        let indexTipNorm = normalized[8]
        let middleTipNorm = normalized[12]
        
        let d1 = thumbTipNorm.distance(to: indexTipNorm)   // Index to Thumb
        let d2 = thumbTipNorm.distance(to: middleTipNorm)  // Middle to Thumb
        
        // Right Click: Index and Middle are BOTH pinched with the thumb, and Middle is extended (not curled)
        let isRightClick = d1 < 0.12 && d2 < 0.14 && middleLen > 0.26
        
        // Left Click: Index is pinched with the thumb, but Middle is NOT pinched or is curled
        let isLeftClick = d1 < 0.12 && !isRightClick
        
        // 1. Check for 3-finger circular or vertical swipe (Mission Control / App Exposé)
        // Extend index, middle, ring. Allow pinky to be slightly relaxed (anatomical constraint)
        let threeFingersExtended = indexLen > 0.34 && middleLen > 0.34 && ringLen > 0.34 && (littleLen < ringLen - 0.05 || littleLen < 0.35)
        
        if threeFingersExtended {
            state.threeFingerFrameCount += 1
            
            // Only trigger and block cursor if the user holds this pose persistently (debounce ~166ms)
            if state.threeFingerFrameCount >= 5 {
                state.lastIndexX = nil
                state.lastIndexY = nil
                
                // A. Linear Vertical Swipe Detection (swiping hand physically up or down)
                let wrist = points[0]
                let currentY = wrist.y
                if let lastY = state.lastSwipeY {
                    let dy = currentY - lastY
                    state.swipeAccumulatorY += dy
                    
                    let now = Date()
                    let translationThreshold: Float = 0.12
                    
                    if now.timeIntervalSince(state.spaceSwitchCooldown) > 1.2 {
                        if state.swipeAccumulatorY > translationThreshold {
                            print("[Trackpad] 3-finger linear UP: Mission Control")
                            ActionBinder.triggerMissionControl()
                            state.spaceSwitchCooldown = now
                            state.swipeAccumulatorY = 0
                            state.swipeAccumulator = 0
                            DispatchQueue.main.async {
                                HandTracker.shared.activeGestureName = "Mission Control"
                            }
                        } else if state.swipeAccumulatorY < -translationThreshold {
                            print("[Trackpad] 3-finger linear DOWN: App Exposé")
                            ActionBinder.triggerAppExpose()
                            state.spaceSwitchCooldown = now
                            state.swipeAccumulatorY = 0
                            state.swipeAccumulator = 0
                            DispatchQueue.main.async {
                                HandTracker.shared.activeGestureName = "App Exposé"
                            }
                        }
                    }
                } else {
                    state.swipeAccumulatorY = 0
                }
                state.lastSwipeY = currentY
                
                // B. Circular Wheel Swipe Detection (Fallback rotation)
                let indexTip = points[8]
                let dx = indexTip.x - wrist.x
                let dy = indexTip.y - wrist.y
                let currentAngle = atan2(dy, dx)
                
                if let lastAngle = state.swipeAngle {
                    var diff = currentAngle - lastAngle
                    if diff > Float.pi  { diff -= 2.0 * Float.pi }
                    if diff < -Float.pi { diff += 2.0 * Float.pi }
                    
                    state.swipeAccumulator += diff
                    state.swipeAngle = currentAngle
                    
                    let now = Date()
                    let rotationThreshold: Float = 0.45
                    if now.timeIntervalSince(state.spaceSwitchCooldown) > 1.2 {
                        if state.swipeAccumulator > rotationThreshold {
                            print("[Trackpad] 3-finger circle CCW: Mission Control")
                            ActionBinder.triggerMissionControl()
                            state.spaceSwitchCooldown = now
                            state.swipeAccumulator = 0
                            state.swipeAccumulatorY = 0
                            DispatchQueue.main.async {
                                HandTracker.shared.activeGestureName = "Mission Control"
                            }
                        } else if state.swipeAccumulator < -rotationThreshold {
                            print("[Trackpad] 3-finger circle CW: App Exposé")
                            ActionBinder.triggerAppExpose()
                            state.spaceSwitchCooldown = now
                            state.swipeAccumulator = 0
                            state.swipeAccumulatorY = 0
                            DispatchQueue.main.async {
                                HandTracker.shared.activeGestureName = "App Exposé"
                            }
                        }
                    }
                } else {
                    state.swipeAngle = currentAngle
                    state.swipeAccumulator = 0
                }
                
                DispatchQueue.main.async {
                    HandTracker.shared.activeGestureName = "Swipe Mode"
                }
                return true // Pause cursor movement while holding 3-finger pose
            }
        } else {
            // Reset accumulator and state when fingers leave 3-finger pose
            state.threeFingerFrameCount = 0
            state.swipeAngle = nil
            state.swipeAccumulator = 0
            state.lastSwipeY = nil
            state.swipeAccumulatorY = 0
        }
        
        // 2. Check for 2-finger circular pivot scroll (Index & Middle open, Ring & Little curled)
        let twoFingersScroll = indexLen > 0.35 && middleLen > 0.35 && ringLen < 0.35 && littleLen < 0.35 && !isLeftClick && !isRightClick
        
        if twoFingersScroll {
            state.twoFingerFrameCount += 1
            
            // Only trigger and block cursor if the user holds this pose persistently (debounce ~133ms)
            if state.twoFingerFrameCount >= 4 {
                state.lastIndexX = nil
                state.lastIndexY = nil
                
                let wrist = points[0]
                let indexTip = points[8]
                let dx = indexTip.x - wrist.x
                let dy = indexTip.y - wrist.y
                let currentAngle = atan2(dy, dx)
                
                if let lastAngle = state.lastScrollAngle {
                    var diff = currentAngle - lastAngle
                    if diff > Float.pi { diff -= 2.0 * Float.pi }
                    if diff < -Float.pi { diff += 2.0 * Float.pi }
                    
                    if abs(diff) > 0.03 {
                        let sensitivity = SettingsManager.shared.scrollSensitivity
                        let scrollSpeed = Int32(diff * Float(sensitivity) * 8.0)
                        if scrollSpeed != 0 {
                            print("[Trackpad] Circular Scroll: speed \(scrollSpeed)")
                            ActionBinder.simulateScroll(deltaY: scrollSpeed)
                        }
                        state.lastScrollAngle = currentAngle
                    }
                } else {
                    state.lastScrollAngle = currentAngle
                }
                
                DispatchQueue.main.async {
                    HandTracker.shared.activeGestureName = "Trackpad Scroll (Pivot)"
                }
                return true // Pause cursor movement while scrolling
            }
        } else {
            state.twoFingerFrameCount = 0
            state.lastScrollAngle = nil
        }
        
        // 3. Pointer Movement constraints
        let isFist = isHandClenched(normalized)
        
        // Relaxed Pointer Detection: Index is extended (length > 0.35) and middle is curled (length < 0.35)
        let isPointing = indexLen > 0.35 && middleLen < 0.35
        
        // We only drive cursor when pointing one finger, or performing a pinch click/drag
        let wrist = points[0] // Track wrist coordinate for stable relative displacement offsets
        let currentRawX = wrist.x
        let currentRawY = wrist.y
        
        let activeTracking = (isPointing || isLeftClick || isRightClick) && !isFist
        
        if activeTracking {
            if let lastX = state.lastIndexX, let lastY = state.lastIndexY {
                let dxRaw = currentRawX - lastX
                let dyRaw = currentRawY - lastY
                let rawSpeed = sqrt(dxRaw * dxRaw + dyRaw * dyRaw)

                
                // Dynamic EMA alpha: heavier smoothing (0.12) at low speeds, low smoothing (0.70) at high speeds
                let alpha = max(0.12, min(0.70, 0.12 + rawSpeed * 15.0))
                state.smoothDeltaX = (alpha * dxRaw) + ((1.0 - alpha) * state.smoothDeltaX)
                state.smoothDeltaY = (alpha * dyRaw) + ((1.0 - alpha) * state.smoothDeltaY)
                
                let smoothSpeed = sqrt(state.smoothDeltaX * state.smoothDeltaX + state.smoothDeltaY * state.smoothDeltaY)
                
                // Get current cursor location
                guard let src = CGEventSource(stateID: .combinedSessionState),
                      let currentEvent = CGEvent(source: src) else { return true }
                let currentCursor = currentEvent.location
                
                // Acceleration Multiplier: slow movements are dampened, fast movements are accelerated
                let baseSensitivity = CGFloat(SettingsManager.shared.trackpadSpeed * 1300.0)
                let acceleration = 1.0 + CGFloat(smoothSpeed * 22.0)
                let targetX = currentCursor.x + CGFloat(state.smoothDeltaX) * baseSensitivity * acceleration
                let targetY = currentCursor.y - CGFloat(state.smoothDeltaY) * baseSensitivity * acceleration // subtract dy since Vision origin is bottom-left
                
                // Clamp target point to active screen dimensions
                guard let screen = NSScreen.main else { return true }
                let clampedX = max(0.0, min(screen.frame.width, targetX))
                let clampedY = max(0.0, min(screen.frame.height, targetY))
                let targetPoint = CGPoint(x: clampedX, y: clampedY)
                
                // Process Right Click events
                if isRightClick {
                    if !state.wasRightPinching {
                        print("[Trackpad] Right Mouse Down at \(targetPoint)")
                        ActionBinder.rightMouseDown(at: targetPoint)
                        state.wasRightPinching = true
                    }
                } else {
                    if state.wasRightPinching {
                        print("[Trackpad] Right Mouse Up at \(targetPoint)")
                        ActionBinder.rightMouseUp(at: targetPoint)
                        state.wasRightPinching = false
                    }
                }
                
                // Process Left Click & Drag events
                if isLeftClick {
                    if !state.wasPinchingForMouse {
                        print("[Trackpad] Left Mouse Down at \(targetPoint)")
                        ActionBinder.mouseDown(at: targetPoint)
                        state.wasPinchingForMouse = true
                        state.pinchStartCursorLocation = targetPoint
                        state.isDragActive = false
                    } else {
                        // Only transition to drag if the user moves past 1/25 of typical screen size (~60 pixels)
                        if state.isDragActive {
                            ActionBinder.moveMouse(to: targetPoint, drag: true)
                        } else if let startLoc = state.pinchStartCursorLocation {
                            let dx = targetPoint.x - startLoc.x
                            let dy = targetPoint.y - startLoc.y
                            let dist = sqrt(dx*dx + dy*dy)
                            
                            if dist > 60.0 {
                                state.isDragActive = true
                                print("[Trackpad] Drag threshold crossed. Drag started.")
                                ActionBinder.moveMouse(to: targetPoint, drag: true)
                            }
                        }
                    }
                } else {
                    if state.wasPinchingForMouse {
                        // If they never dragged, release at the original pinch-start position to guarantee a clean click
                        let releasePoint = state.isDragActive ? targetPoint : (state.pinchStartCursorLocation ?? targetPoint)
                        print("[Trackpad] Left Mouse Up at \(releasePoint)")
                        ActionBinder.mouseUp(at: releasePoint)
                        state.wasPinchingForMouse = false
                        state.pinchStartCursorLocation = nil
                        state.isDragActive = false
                    } else {
                        // Only move cursor if we are not right clicking or holding right click drag
                        if !isRightClick && !state.wasRightPinching {
                            ActionBinder.moveMouse(to: targetPoint, drag: false)
                        }
                    }
                }
                
                // Update HUD state text
                var actionText = "Trackpad Hover"
                if isRightClick {
                    actionText = "Trackpad Right Click"
                } else if isLeftClick {
                    actionText = state.isDragActive ? "Trackpad Drag" : "Trackpad Click"
                }
                
                DispatchQueue.main.async {
                    HandTracker.shared.activeGestureName = actionText
                }
            } else {
                // Initialize tracking references on the first active frame to prevent jump
                state.smoothDeltaX = 0.0
                state.smoothDeltaY = 0.0
            }
            
            // Record last coordinates for relative tracking offset in next frame
            state.lastIndexX = currentRawX
            state.lastIndexY = currentRawY
        } else {
            // Disengaged (fist, scroll, swipe, or relaxed hand). Reset relative tracking references.
            state.lastIndexX = nil
            state.lastIndexY = nil
            state.smoothDeltaX = 0.0
            state.smoothDeltaY = 0.0
            
            // If disengaged, ensure clicks are released
            if state.wasPinchingForMouse {
                if let src = CGEventSource(stateID: .combinedSessionState),
                   let currentEvent = CGEvent(source: src) {
                    ActionBinder.mouseUp(at: currentEvent.location)
                }
                state.wasPinchingForMouse = false
            }
            if state.wasRightPinching {
                if let src = CGEventSource(stateID: .combinedSessionState),
                   let currentEvent = CGEvent(source: src) {
                    ActionBinder.rightMouseUp(at: currentEvent.location)
                }
                state.wasRightPinching = false
            }
            
            var HUDText = "Trackpad Standby"
            if isFist {
                HUDText = "Trackpad Clutch (Fist)"
            }
            
            let finalHUDText = HUDText
            DispatchQueue.main.async {
                HandTracker.shared.activeGestureName = finalHUDText
            }
        }
        
        return true
    }
    
    private func evaluateHorizontalSwipes(state: HandState) -> Bool {
        guard state.historyX.count >= 6 else { return false }
        
        let currentX = state.historyX.last!
        let previousX = state.historyX[state.historyX.count - 6]
        let deltaX = currentX - previousX
        
        let now = Date()
        let threshold = Float(SettingsManager.shared.swipeThreshold)
        let cooldown = SettingsManager.shared.swipeCooldown
        
        guard now.timeIntervalSince(state.spaceSwitchCooldown) > cooldown else { return false }
        
        if deltaX > threshold {
            print("[Gesture] Fast swipe right: Next Space")
            ActionBinder.simulateSwitchSpaceRight()
            state.spaceSwitchCooldown = now
            return true
        } else if deltaX < -threshold {
            print("[Gesture] Fast swipe left: Previous Space")
            ActionBinder.simulateSwitchSpaceLeft()
            state.spaceSwitchCooldown = now
            return true
        }
        
        return false
    }
    
    private func evaluateVerticalScrolling(_ normalized: [Point3D], state: HandState) -> Bool {
        guard state.historyY.count >= 4 else { return false }
        
        let currentY = state.historyY.last!
        let previousY = state.historyY[state.historyY.count - 4]
        let deltaY = currentY - previousY
        
        // Grab-to-Scroll: Only trigger scrolling if hand is clenched into a fist
        if isHandClenched(normalized) {
            let sensitivity = SettingsManager.shared.scrollSensitivity
            if abs(deltaY) > 0.02 {
                // Negative scroll speed for natural scroll direction matching
                let scrollSpeed = Int32(-deltaY * Float(sensitivity))
                if scrollSpeed != 0 {
                    print("[Gesture] Clenched Scroll: Speed \(scrollSpeed)")
                    ActionBinder.simulateScroll(deltaY: scrollSpeed)
                }
            }
            return true
        }
        
        return false
    }
    
    private func evaluateFlatHandElevation(_ points: [Point3D], normalized: [Point3D], action: String, state: HandState) -> Bool {
        guard SettingsManager.shared.enableFlatHandControl else {
            state.isCurrentlyElevating = false
            return false
        }
        
        let thumbTip = normalized[4]
        let indexTip = normalized[8]
        let isPinching = thumbTip.distance(to: indexTip) < 0.12
        
        // Flat hand gesture + no pinching active
        if isHandFlat(normalized) && !isPinching {
            let currentY = points[0].y // Use raw wrist Y position
            let threshold = Float(SettingsManager.shared.elevationThreshold)
            
            if !state.isCurrentlyElevating {
                state.isCurrentlyElevating = true
                state.elevationStartY = currentY
            } else {
                let diff = currentY - state.elevationStartY
                if diff > threshold {
                    triggerAction(action, up: true)
                    state.elevationStartY = currentY
                } else if diff < -threshold {
                    triggerAction(action, up: false)
                    state.elevationStartY = currentY
                }
            }
            return true
        } else {
            state.isCurrentlyElevating = false
        }
        
        return false
    }
    
    private func evaluatePinchControl(_ normalized: [Point3D], action: String, state: HandState) -> Bool {
        let thumbTip = normalized[4]
        let indexTip = normalized[8]
        let distance = thumbTip.distance(to: indexTip)
        let isPinching = distance < 0.12
        
        if isPinching {
            let currentY = normalized[8].y // Track index tip vertical height
            let threshold = Float(SettingsManager.shared.pinchVolumeThreshold)
            
            if !state.isCurrentlyPinching {
                state.isCurrentlyPinching = true
                state.pinchStartY = currentY
            } else {
                let diff = currentY - state.pinchStartY
                
                if diff > threshold {
                    triggerAction(action, up: true)
                    state.pinchStartY = currentY
                } else if diff < -threshold {
                    triggerAction(action, up: false)
                    state.pinchStartY = currentY
                }
            }
            return true
        } else {
            state.isCurrentlyPinching = false
        }
        
        return false
    }
    
    private func triggerAction(_ action: String, up: Bool) {
        switch action {
        case "Volume":
            if up {
                print("[Gesture] Triggering Volume Up")
                ActionBinder.volumeUp()
            } else {
                print("[Gesture] Triggering Volume Down")
                ActionBinder.volumeDown()
            }
        case "Brightness":
            if up {
                print("[Gesture] Triggering Brightness Up")
                ActionBinder.brightnessUp()
            } else {
                print("[Gesture] Triggering Brightness Down")
                ActionBinder.brightnessDown()
            }
        default:
            break
        }
    }
    
    private func evaluateCustomGestures(_ normalized: [Point3D], state: HandState) -> Bool {
        let now = Date()
        let templates = SettingsManager.shared.customTemplates
        guard !templates.isEmpty else { return false }
        
        // Detect if the hand matches any registered templates (lowered threshold to 0.82)
        if let match = GestureClassifier.classify(livePoints: normalized, against: templates, threshold: 0.82) {
            let label = match.name
            
            // Set active feedback text
            DispatchQueue.main.async {
                HandTracker.shared.activeGestureName = label
            }
            
            // Suppress default gestures if we are currently holding a trained gesture
            if now.timeIntervalSince(state.customGestureCooldown) > 1.5 {
                print("[Gesture] Matched Custom Gesture: \(match.name) -> Triggering \(match.actionType.rawValue)")
                executeCustomAction(match.actionType, actionData: match.actionData)
                state.customGestureCooldown = now
            }
            return true
        }
        
        return false
    }
    
    private func executeCustomAction(_ actionType: GestureActionType, actionData: String?) {
        switch actionType {
        case .toggleMute:
            ActionBinder.toggleMute()
        case .volumeUp:
            ActionBinder.volumeUp()
        case .volumeDown:
            ActionBinder.volumeDown()
        case .launchApp:
            if let appName = actionData {
                print("[Gesture] Launching app: \(appName)")
                ActionBinder.launchApplication(named: appName)
            }
        case .menuSearch:
            print("[Gesture] Triggering Active App Menu Search")
            ActionBinder.simulateMenuSearch()
        default:
            break
        }
    }
    
    private func isHandClenched(_ normalized: [Point3D]) -> Bool {
        let indexLen = normalized[8].distance(to: normalized[5])
        let middleLen = normalized[12].distance(to: normalized[9])
        let ringLen = normalized[16].distance(to: normalized[13])
        let littleLen = normalized[20].distance(to: normalized[17])
        let thumbLen = normalized[4].distance(to: normalized[1]) // Check thumb tip to base
        
        // Balanced fist detection: fingers must be curled (< 0.25) and thumb must be curled (< 0.36)
        return indexLen < 0.25 && middleLen < 0.25 && ringLen < 0.25 && littleLen < 0.25 && thumbLen < 0.36
    }
    
    private func isHandFlat(_ normalized: [Point3D]) -> Bool {
        let indexLen = normalized[8].distance(to: normalized[5])
        let middleLen = normalized[12].distance(to: normalized[9])
        let ringLen = normalized[16].distance(to: normalized[13])
        let littleLen = normalized[20].distance(to: normalized[17])
        let thumbLen = normalized[4].distance(to: normalized[1]) // Check thumb tip to base
        
        // Open flat palm: all fingers must be fully extended (length > 0.40) and thumb extended (> 0.35)
        return indexLen > 0.40 && middleLen > 0.40 && ringLen > 0.40 && littleLen > 0.40 && thumbLen > 0.35
    }
}
