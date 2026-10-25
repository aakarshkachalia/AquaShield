//
//  DocumentCameraView.swift
//  AquaShield
//
//  VisionKit document camera: edge detection, perspective correction and multi-page capture.
//

import AVFoundation
import SwiftUI
import VisionKit

struct DocumentCameraView: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancel()
        }
    }

    /// Whether the camera can be used, and if not, why.
    enum Availability {
        case available, denied, unsupported
    }

    static func availability() async -> Availability {
        guard VNDocumentCameraViewController.isSupported else { return .unsupported }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .available
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video) ? .available : .denied
        default: return .denied
        }
    }
}

extension UIImage {
    /// CGImage plus the orientation Vision needs to read it upright.
    var visionPage: (image: CGImage, orientation: CGImagePropertyOrientation)? {
        guard let cg = cgImage else { return nil }
        let orientation: CGImagePropertyOrientation = switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
        return (cg, orientation)
    }
}
