import AVFoundation
import Combine
// MARK: gestore reattivo dei permessi per la fotocamera.
@MainActor
final class CameraPermissionManager: ObservableObject {
    enum Status {
        // stato interno del permesso fotocamera
        case notDetermined
        case granted
        case denied
        case restricted
    }

    @Published var status: Status = .notDetermined

    init() {
        refresh() // legge lo stato attuale all’avvio
    }
    // MARK: sincronizza la proprietà `status` con il reale stato di autorizzazione del sistema operativo
    func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:             status = .granted
        case .denied:                 status = .denied
        case .restricted:             status = .restricted
        case .notDetermined:          status = .notDetermined
        @unknown default:             status = .denied
        }
    }
    // richiede esplicitamente l'accesso alla fotocamera mostrando il pop-up di sistema di iOS
    func request() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        status = granted ? .granted : .denied
    }
}
