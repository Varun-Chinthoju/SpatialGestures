import AVFoundation
import Vision
import Combine

/// Error codes for joint classification
public enum HandTrackerError: Error {
    case lowConfidence
}

/// Manages camera capture session and translates video frames into 21-joint hand landmark structures and face yaw angles.
public class HandTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, ObservableObject {
    
    public static let shared = HandTracker()
    
    private var captureSession: AVCaptureSession?
    private let videoOutputQueue = DispatchQueue(label: "com.spatialgestures.VideoOutputQueue")
    
    /// Publishes all tracked hands in camera view (up to 2).
    @Published public var trackedHands: [[Point3D]] = []
    
    /// Publishes the first tracked hand (fallback for single-hand compatibility).
    @Published public var trackedHand: [Point3D]? = nil
    
    /// Publishes whether camera authorization is granted.
    @Published public var cameraAuthorized: Bool = false
    
    /// Publishes the active gesture description for HUD feedback.
    @Published public var activeGestureName: String = ""
    
    // Face tracking properties for head pose yaw/pitch estimation
    @Published public var faceYaw: Float? = nil
    @Published public var facePitch: Float? = nil
    
    // Timestamp to prevent HUD flickering on transient tracking losses
    private var lastHandSeenDate = Date.distantPast
    
    private override init() {
        super.init()
        checkCameraPermission()
    }
    
    /// Checks camera permissions and updates the state.
    public func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.cameraAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.cameraAuthorized = granted
                }
            }
        default:
            self.cameraAuthorized = false
        }
    }
    
    /// Starts capture session in the video queue.
    public func startSession() {
        GestureProcessor.shared.resetHistory()
        lastHandSeenDate = Date.distantPast
        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession == nil {
                self.setupCaptureSession()
            }
            
            guard self.cameraAuthorized else {
                print("Camera authorization not granted. Cannot start session.")
                return
            }
            
            if let session = self.captureSession, !session.isRunning {
                session.startRunning()
                print("Camera session started.")
            }
        }
    }
    
    /// Stops capture session in the video queue and resets tracked hand vector.
    public func stopSession() {
        videoOutputQueue.async { [weak self] in
            guard let self = self else { return }
            if let session = self.captureSession, session.isRunning {
                session.stopRunning()
                print("Camera session stopped.")
            }
            DispatchQueue.main.async {
                self.trackedHand = nil
                self.trackedHands = []
                self.faceYaw = nil
                self.facePitch = nil
                self.activeGestureName = ""
                GestureProcessor.shared.resetHistory()
            }
        }
    }
    
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .vga640x480 // VGA resolution is optimal for speed/CPU usage
        
        // Discover all video capture devices (built-in, external webcams, etc.)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        
        let devices = discoverySession.devices
        print("[Camera] Discovered video devices: \(devices.map { $0.localizedName })")
        
        guard !devices.isEmpty else {
            print("[Camera] Error: No video capture devices found.")
            return
        }
        
        // Try to open a device input, skipping any suspended built-in cameras (like closed MacBook lids)
        var selectedDevice: AVCaptureDevice? = nil
        var videoInput: AVCaptureDeviceInput? = nil
        
        for device in devices {
            if let input = try? AVCaptureDeviceInput(device: device) {
                selectedDevice = device
                videoInput = input
                break
            }
        }
        
        guard let camera = selectedDevice, let input = videoInput else {
            print("[Camera] Error: Failed to open any discovered camera devices.")
            return
        }
        
        print("[Camera] Successfully opened camera device: \(camera.localizedName)")
        
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        
        guard session.canAddOutput(videoOutput) else { return }
        session.addOutput(videoOutput)
        
        // Ensure orientation configuration matches portrait coordinates mapping
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }
        
        self.captureSession = session
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        // Perform both hand-pose request and face-rectangle requests
        let handRequest = VNDetectHumanHandPoseRequest()
        handRequest.maximumHandCount = 2
        
        let faceRequest = VNDetectFaceRectanglesRequest()
        
        do {
            try requestHandler.perform([handRequest, faceRequest])
            
            // 1. Process Face Gaze angle
            if let face = faceRequest.results?.first {
                let yaw = face.yaw?.floatValue ?? 0.0
                let pitch = face.pitch?.floatValue ?? 0.0
                
                // Convert yaw and pitch to degrees
                let yawDegrees = yaw * 180.0 / .pi
                let pitchDegrees = pitch * 180.0 / .pi
                
                DispatchQueue.main.async { [weak self] in
                    self?.faceYaw = yawDegrees
                    self?.facePitch = pitchDegrees
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.faceYaw = nil
                    self?.facePitch = nil
                }
            }
            
            // 2. Process Hand Joints
            guard let handResults = handRequest.results, !handResults.isEmpty else {
                // Hand lost. Wait 1 second (hysteresis) before dismissing HUD
                let now = Date()
                if now.timeIntervalSince(self.lastHandSeenDate) > 1.0 {
                    DispatchQueue.main.async { [weak self] in
                        self?.trackedHand = nil
                        self?.trackedHands = []
                        self?.activeGestureName = ""
                    }
                }
                return
            }
            
            var mappedHands: [(joints: [Point3D], size: Float, observation: VNHumanHandPoseObservation)] = []
            
            for observation in handResults {
                if let joints = try? mapHandJoints(from: observation) {
                    // Calculate size: distance between wrist (points[0]) and middle knuckle (points[9])
                    let wrist = joints[0]
                    let knuckle = joints[9]
                    let size = sqrt(pow(wrist.x - knuckle.x, 2) + pow(wrist.y - knuckle.y, 2))
                    
                    // Filter out background hands (size < 0.08 is typical for people walking in background)
                    if size >= 0.08 {
                        mappedHands.append((joints, size, observation))
                    }
                }
            }
            
            // Sort by proximity (largest size first) and take the closest 2 hands
            mappedHands.sort { $0.size > $1.size }
            let filteredHands = mappedHands.prefix(2)
            
            if filteredHands.isEmpty {
                // No close hands seen. Treat as hand lost
                let now = Date()
                if now.timeIntervalSince(self.lastHandSeenDate) > 1.0 {
                    DispatchQueue.main.async { [weak self] in
                        self?.trackedHand = nil
                        self?.trackedHands = []
                        self?.activeGestureName = ""
                    }
                }
                return
            }
            
            // Hand is seen! Update timestamp and publish coordinates
            self.lastHandSeenDate = Date()
            
            var hands: [[Point3D]] = []
            for item in filteredHands {
                hands.append(item.joints)
                let isLeft = (item.observation.chirality == .left)
                GestureProcessor.shared.processFrame(item.joints, isLeft: isLeft)
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.trackedHands = hands
                self?.trackedHand = hands.first
            }

        } catch {
            print("Error performing Vision requests: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.trackedHand = nil
                self?.trackedHands = []
                self?.faceYaw = nil
                self?.facePitch = nil
            }
        }
    }

    private func mapHandJoints(from observation: VNHumanHandPoseObservation) throws -> [Point3D] {
        let jointNames: [VNHumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]
        
        var points: [Point3D] = []
        for name in jointNames {
            let jointPoint = try observation.recognizedPoint(name)
            guard jointPoint.confidence > 0.3 else {
                throw HandTrackerError.lowConfidence
            }
            
            // Mirror X-coordinate for natural visual feedback (front camera mirror effect)
            let mirroredX = Float(1.0 - jointPoint.location.x)
            let y = Float(jointPoint.location.y)
            points.append(Point3D(x: mirroredX, y: y, z: 0.0))
        }
        
        return points
    }
}
