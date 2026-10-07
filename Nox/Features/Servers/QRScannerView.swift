import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import CoreImage

/// Full-screen QR scanner (camera) with "from photo" fallback.
struct QRScannerView: View {
    let onCode: (String) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var denied = false
    @State private var message: String?
    @State private var found = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(onCode: handle, onDenied: { denied = true })
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(settings.accentColor, lineWidth: 3)
                .frame(width: 252, height: 252)
                .shadow(color: settings.accentColor.opacity(0.55), radius: 14)
                .opacity(denied ? 0.25 : 1)

            VStack(spacing: 16) {
                HStack {
                    CircleButton(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Ink.primary)
                    }
                    Spacer()
                }
                Text(settings.t("Наведите камеру на QR-код", "Point the camera at a QR code"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                    .padding(.top, 8)
                Spacer()
                if denied {
                    Text(settings.t("Нет доступа к камере. Разрешите его в Настройках iOS или выберите фото с QR-кодом.",
                                    "No camera access. Allow it in iOS Settings or pick a photo with a QR code."))
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.center)
                }
                if let message {
                    Text(message)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PingColor.bad.color)
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(settings.t("Выбрать из фото", "Choose from photos"), systemImage: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                        .padding(.horizontal, 20)
                        .frame(height: 48)
                        .background(Capsule().fill(settings.elevatedColor))
                        .overlay(Capsule().strokeBorder(Ink.stroke, lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await scanPhoto(item) }
        }
    }

    private func handle(_ code: String) {
        guard !found else { return }
        found = true
        Haptics.success()
        onCode(code)
    }

    private func scanPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        if let code = QRDecoder.decode(data) {
            handle(code)
        } else {
            Haptics.error()
            message = settings.t("На фото не нашлось QR-кода", "No QR code in this photo")
        }
    }
}

enum QRDecoder {
    static func decode(_ data: Data) -> String? {
        guard let image = CIImage(data: data) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: image) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}

/// AVFoundation camera with a QR metadata output.
struct CameraPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onDenied: () -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        controller.onDenied = onDenied
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let queue = DispatchQueue(label: "nox.qr.session")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { self.configure() } else { self.onDenied?() }
                }
            }
        default:
            onDenied?()
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onDenied?()
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        let session = self.session
        queue.async { session.startRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = self.session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        MainActor.assumeIsolated {
            self.onCode?(code)
        }
    }
}
