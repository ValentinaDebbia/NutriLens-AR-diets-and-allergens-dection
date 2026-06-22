import AVFoundation
import UIKit
import Combine

//MARK: gestore della sessione di acquisizione della fotocamera
@MainActor
final class CameraSessionManager: NSObject, ObservableObject {

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.nutrilens.camera")

    @Published var sessionError: String? = nil

    override init() { super.init() }


    func configure() { sessionQueue.async { [weak self] in self?.buildSession() } }
    // avvia la sessione se non è già in esecuzione
    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }
    // ferma la sessione se è in esecuzione
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    //MARK: configura l'hardware della fotocamera e l'input della sessione
    private func buildSession() {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input  = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            DispatchQueue.main.async { self.sessionError = "Impossibile accedere alla fotocamera." }
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()

        session.commitConfiguration()
    }
}
