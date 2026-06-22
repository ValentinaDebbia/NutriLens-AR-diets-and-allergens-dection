import ARKit
import Combine

// MARK: gestore principale per il riconoscimento di immagini
@MainActor
final class ARRecognitionManager: NSObject, ObservableObject {

    @Published var detectedProduct: Product?           = nil
    @Published var safetyStatus: Product.SafetyStatus? = nil
    @Published var alertDetails: Product.AlertDetails? = nil
    @Published var isScanning: Bool                    = true
    @Published var sessionError: String?               = nil

    let arSession = ARSession()
    // memorizza l'identificativo dell'ultimo marker rilevato con successo
    private var lastDetectedMarkerID: String? = nil

    override init() {
        super.init()
        arSession.delegate = self
    }

    // MARK: avvia la sessione AR con tracciamento di 1 immagine
    func startSession() {
        guard ARImageTrackingConfiguration.isSupported else {
            sessionError = "ARImageTracking non è supportato su questo dispositivo."
            return
        }
        // carica i marker da Assets › ProductMarkers
        guard
            let referenceImages = ARReferenceImage.referenceImages(
                inGroupNamed: "ProductMarkers",
                bundle: .main
            ), !referenceImages.isEmpty
        else {
            sessionError = "Nessun marcatore trovato in Assets › ProductMarkers."
            return
        }

        let config = ARImageTrackingConfiguration()
        config.trackingImages               = referenceImages
        config.maximumNumberOfTrackedImages = 1

        // avvio sessione
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        isScanning   = true
        sessionError = nil
        print("▶️ Sessione AR avviata – \(referenceImages.count) marcatori caricati.")
    }

    func pauseSession() {
        arSession.pause()
        isScanning = false
    }
    // MARK: ripristina lo stato di scansione eliminando i dati dell'ultimo prodotto rilevato.
    func resetDetection() {
        detectedProduct      = nil
        safetyStatus         = nil
        alertDetails         = nil
        lastDetectedMarkerID = nil
        isScanning           = true
    }
}

// MARK: gestisce il riconoscimento del marker e aggiorna lo stato UI
extension ARRecognitionManager: ARSessionDelegate {
    // chiamato quando ARKit rileva per la prima volta una nuova ancora
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        process(anchors)
    }
    // chiamato ad ogni frame in cui ARKit aggiorna la posizione o lo stato di tracciamento delle ancore esistenti
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        process(anchors)
    }
    // MARK: analizza le ancore trovate per identificare i marker d'immagine e aggiornare lo stato dell'app
    nonisolated private func process(_ anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor,
                  let markerName  = imageAnchor.referenceImage.name
            else { continue }

            let tracked = imageAnchor.isTracked

            Task { @MainActor in
                if tracked {
                    guard markerName != self.lastDetectedMarkerID else { return }
                    self.lastDetectedMarkerID = markerName
                    // interroga il database locale per vedere se il codice del marker corrisponde a un prodotto reale.
                    if let product = ProductDatabase.shared.product(forMarkerID: markerName) {
                        let prefs  = UserPreferences.load() ?? UserPreferences(allergens: [], dietaryNeeds: [])
                        // calcola lo stato di sicurezza alimentare (es. sicuro, attenzione, pericolo)
                        let status = product.safetyStatus(for: prefs)
                        self.detectedProduct = product
                        self.safetyStatus    = status
                        self.alertDetails    = product.alertDetails(for: prefs)
                        self.isScanning      = false
                        // riproduce un feedback sonoro differenziato in base alla sicurezza
                        SoundManager.shared.play(for: status)
                        print("✅ Prodotto riconosciuto: \(product.nome)")
                    } else {
                        print("⚠️ Marcatore '\(markerName)' non trovato nel database.")
                    }
                } else {
                    // oggetto uscito dall'inquadratura → reset immediato
                    self.resetDetection()
                    print("👁 Marcatore '\(markerName)' perso – overlay rimosso.")
                }
            }
        }
    }
    
    // MARK: - error handling & interruptions
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let msg = (error as NSError).localizedDescription
        Task { @MainActor in
            self.sessionError = "Errore AR: \(msg)"
            print("❌ AR session error: \(msg)")
        }
    }
    // chiamato quando la sessione viene interrotta (es. l'utente riceve una chiamata telefonica o l'app va in background)
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in self.isScanning = false }
    }
    // chiamato quando l'interruzione termina (es. l'utente torna sull'app), viene riavviata la sessione
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in self.startSession() }
    }
}
