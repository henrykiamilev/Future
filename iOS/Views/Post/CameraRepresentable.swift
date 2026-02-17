import SwiftUI
import AVFoundation
import UIKit

// ============================================================================
// CAMERA CAPTURE PIPELINE
// ============================================================================
// - AVFoundation capture session with proper lifecycle management
// - HEVC (HEIC source) codec preferred, JPEG fallback
// - Front/back camera switching
// - Flash control
// - Orientation-aware capture
// - Continuation-based async bridge (no callback pyramids)
// - Session runs on a dedicated serial queue to avoid main-thread stalls
// ============================================================================

// MARK: - Camera Error

enum CameraError: LocalizedError {
    case noCameraAvailable
    case inputConfigurationFailed(underlying: String)
    case outputConfigurationFailed
    case captureFailed(underlying: String)
    case sessionNotRunning
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable:            return "No camera available on this device."
        case .inputConfigurationFailed(let e): return "Camera configuration failed: \(e)"
        case .outputConfigurationFailed:    return "Could not configure photo output."
        case .captureFailed(let e):         return "Photo capture failed: \(e)"
        case .sessionNotRunning:            return "Camera session is not running."
        case .authorizationDenied:          return "Camera access was denied."
        }
    }
}

// MARK: - Camera Position

enum CameraPosition: Sendable {
    case back, front

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .back: return .back
        case .front: return .front
        }
    }

    mutating func toggle() {
        self = (self == .back) ? .front : .back
    }
}

// MARK: - Camera Coordinator

final class CameraCoordinator: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {

    // Published state (read on main thread)
    @Published private(set) var isSessionRunning = false
    @Published private(set) var currentPosition: CameraPosition = .back
    @Published var flashMode: AVCaptureDevice.FlashMode = .off

    // Capture session — all access serialized on sessionQueue
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.curated.camera.session", qos: .userInitiated)

    private var currentInput: AVCaptureDeviceInput?
    private var activeContinuation: CheckedContinuation<UIImage, Error>?

    deinit {
        // Fail any outstanding continuation to prevent a leaked coroutine.
        // This avoids a crash if the coordinator is deallocated while a capture is in-flight.
        if let continuation = activeContinuation {
            activeContinuation = nil
            continuation.resume(throwing: CameraError.sessionNotRunning)
        }
        captureSession.stopRunning()
    }

    // MARK: - Public: Session Lifecycle

    /// Configures and starts the capture session. Call once when the camera view appears.
    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                try self.configureSession()
                self.captureSession.startRunning()

                DispatchQueue.main.async {
                    self.isSessionRunning = self.captureSession.isRunning
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                }
            }
        }
    }

    /// Stops the capture session. Call when the camera view disappears.
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.stopRunning()

            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    // MARK: - Public: Capture (async/await)

    /// Captures a single photo. Returns a correctly-oriented UIImage.
    /// Throws `CameraError` on failure.
    func capturePhoto() async throws -> UIImage {
        guard captureSession.isRunning else {
            throw CameraError.sessionNotRunning
        }

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.sessionNotRunning)
                    return
                }

                self.activeContinuation = continuation

                let settings = self.buildPhotoSettings()

                // Connection orientation must match device orientation for correct EXIF
                if let connection = self.photoOutput.connection(with: .video) {
                    connection.videoRotationAngle = self.currentVideoRotationAngle()
                }

                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // MARK: - Public: Switch Camera

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            var newPosition = self.currentPosition
            newPosition.toggle()

            guard let newDevice = self.cameraDevice(for: newPosition.avPosition) else { return }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)

                self.captureSession.beginConfiguration()
                defer { self.captureSession.commitConfiguration() }

                if let existing = self.currentInput {
                    self.captureSession.removeInput(existing)
                }

                guard self.captureSession.canAddInput(newInput) else { return }
                self.captureSession.addInput(newInput)
                self.currentInput = newInput

                DispatchQueue.main.async {
                    self.currentPosition = newPosition
                }
            } catch {
                // Switching failed — stay on current camera
            }
        }
    }

    // MARK: - AVCaptureVideoPreviewLayer (for UIViewRepresentable)

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    // MARK: - Session Configuration (called on sessionQueue)

    private func configureSession() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .photo

        // Remove existing inputs
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }

        // Add camera input
        guard let camera = cameraDevice(for: currentPosition.avPosition) else {
            throw CameraError.noCameraAvailable
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: camera)
        } catch {
            throw CameraError.inputConfigurationFailed(underlying: error.localizedDescription)
        }

        guard captureSession.canAddInput(input) else {
            throw CameraError.inputConfigurationFailed(underlying: "Session rejected input")
        }
        captureSession.addInput(input)
        currentInput = input

        // Add photo output (if not already added)
        if !captureSession.outputs.contains(photoOutput) {
            guard captureSession.canAddOutput(photoOutput) else {
                throw CameraError.outputConfigurationFailed
            }
            captureSession.addOutput(photoOutput)
        }

        // Configure output for max resolution (iOS 16+ API)
        if let maxDimensions = currentInput?.device.activeFormat.supportedMaxPhotoDimensions.last {
            photoOutput.maxPhotoDimensions = maxDimensions
        }
    }

    // MARK: - Photo Settings

    private func buildPhotoSettings() -> AVCapturePhotoSettings {
        // Prefer HEVC (produces HEIC data) — JPEG fallback
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        }

        // Flash
        if photoOutput.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        }

        // Use max resolution available (iOS 16+ API)
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

        return settings
    }

    // MARK: - Camera Device Lookup

    private func cameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Prefer wide-angle for consistent results
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }

    // MARK: - Orientation

    private func currentVideoRotationAngle() -> CGFloat {
        // Map UIDevice orientation to video rotation angle
        // This ensures the captured photo has correct EXIF orientation
        let deviceOrientation = UIDevice.current.orientation
        switch deviceOrientation {
        case .portrait:            return 90
        case .portraitUpsideDown:  return 270
        case .landscapeLeft:       return 0
        case .landscapeRight:      return 180
        default:                   return 90   // default to portrait
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // Dispatch to sessionQueue to synchronize access to activeContinuation
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let continuation = self.activeContinuation
            self.activeContinuation = nil

            if let error {
                continuation?.resume(throwing: CameraError.captureFailed(underlying: error.localizedDescription))
                return
            }

            guard let data = photo.fileDataRepresentation() else {
                continuation?.resume(throwing: CameraError.captureFailed(underlying: "No image data"))
                return
            }

            guard let image = UIImage(data: data) else {
                continuation?.resume(throwing: CameraError.captureFailed(underlying: "Invalid image data"))
                return
            }

            continuation?.resume(returning: image)
        }
    }
}

// MARK: - SwiftUI Camera Preview (UIViewRepresentable)

struct CameraPreviewView: UIViewRepresentable {

    let coordinator: CameraCoordinator

    func makeUIView(context: Context) -> CameraHostView {
        let view = CameraHostView()
        view.previewLayer = coordinator.makePreviewLayer()
        return view
    }

    func updateUIView(_ uiView: CameraHostView, context: Context) {
        // Layout is handled in layoutSubviews
    }
}

/// UIView subclass that auto-resizes its AVCaptureVideoPreviewLayer.
final class CameraHostView: UIView {

    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let previewLayer {
                previewLayer.frame = bounds
                layer.addSublayer(previewLayer)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - Camera Authorization Helper

enum CameraAuthorization {

    static var currentStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess() async -> Bool {
        switch currentStatus {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}
