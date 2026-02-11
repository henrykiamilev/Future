import SwiftUI
import AVFoundation
import UIKit

// MARK: - Camera Coordinator (AVFoundation Bridge)

final class CameraCoordinator: NSObject, AVCapturePhotoCaptureDelegate {

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var onCapture: ((UIImage) -> Void)?

    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    func configure() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }

        captureSession.addInput(input)

        guard captureSession.canAddOutput(photoOutput) else {
            captureSession.commitConfiguration()
            return
        }

        captureSession.addOutput(photoOutput)
        captureSession.commitConfiguration()
    }

    func start() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
            captureSession.startRunning()
        }
    }

    func stop() {
        guard captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
            captureSession.stopRunning()
        }
    }

    func capture(completion: @escaping (UIImage) -> Void) {
        onCapture = completion

        var settings = AVCapturePhotoSettings()
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(image)
        }
    }
}

// MARK: - UIViewRepresentable for Camera Preview

struct CameraPreviewView: UIViewRepresentable {

    let coordinator: CameraCoordinator

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let preview = coordinator.previewLayer
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}
