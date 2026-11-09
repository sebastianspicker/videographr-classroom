import SwiftUI
import AVFoundation

/// SwiftUI bridge to `AVCaptureVideoPreviewLayer` for the Live camera pane.
///
/// Uses aspect fit so the operator can inspect the complete active camera image.
/// The pure guidance engine still analyzes the raw sample buffer separately.
struct CameraPreviewView: UIViewRepresentable {
    /// Running capture session owned by `LiveStore`.
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer?.session = session
        view.videoPreviewLayer?.videoGravity = .resizeAspect
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Live-Kameravorschau"
        view.accessibilityHint = "Die technischen Aufnahmesignale stehen im Prüfbereich."
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer?.session = session
    }

    /// UIView whose backing layer is always a video preview layer.
    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer? {
            layer as? AVCaptureVideoPreviewLayer
        }
    }
}
