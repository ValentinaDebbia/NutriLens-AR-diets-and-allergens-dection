import ARKit
import Combine

// MARK: variante dell'ARRecognitionManager che traccia fino a 2 marcatori simultaneamente, pubblicando i due prodotti rilevati separatamente.
@MainActor
final class ARCompareManager: NSObject, ObservableObject {
    // slot sinistro (primo prodotto riconosciuto)
    @Published var productA: Product? = nil
    // slot destro (secondo prodotto riconosciuto)
    @Published var productB: Product? = nil

    @Published var sessionError: String? = nil
    
    // true finché non sono stati rilevati entrambi i prodotti
    var isComplete: Bool { productA != nil && productB != nil }

    let arSession = ARSession()

    // tiene traccia degli id già assegnati agli slot
    private var assignedMarkers: Set<String> = []

    // lifecycle

    override init() {
        super.init()
        arSession.delegate = self
    }
    // MARK: configura e avvia la sessione AR abilitando il tracciamento simultaneo di due marker distinti
    func startSession() {
        guard ARImageTrackingConfiguration.isSupported else {
            sessionError = "ARImageTracking non è supportato su questo dispositivo."
            return
        }
        // tenta di caricare il set di immagini di riferimento (i marker) dagli Assets
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
        config.trackingImages = referenceImages
        // consente il tracciamento simultaneo di 2 immagini
        config.maximumNumberOfTrackedImages = 2

        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        sessionError = nil
        print("▶️ CompareSession avviata – max 2 marcatori simultanei.")
    }

    func pauseSession() {
        arSession.pause()
    }

    func resetAll() {
        productA = nil
        productB = nil
        assignedMarkers = []
        startSession()
    }
}
// MARK: implementazione
extension ARCompareManager: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        handle(anchors)
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        handle(anchors)
    }
    // gestisce il riconoscimento dei marker e assegna i prodotti agli slot A/B
    nonisolated private func handle(_ anchors: [ARAnchor]) {
        for anchor in anchors {
            guard
                let imageAnchor = anchor as? ARImageAnchor,
                imageAnchor.isTracked,
                let markerName  = imageAnchor.referenceImage.name
            else { continue }

            Task { @MainActor in
                // controllo anti-duplicazione: se questo specifico marker è già assegnato a uno dei due slot, ignorare l'evento per evitare conflitti o sovrascritture
                guard !self.assignedMarkers.contains(markerName) else { return }

                guard let product = ProductDatabase.shared.product(forMarkerID: markerName) else {
                    print("⚠️ Marcatore '\(markerName)' non nel database.")
                    return
                }

                self.assignedMarkers.insert(markerName)

                if self.productA == nil {
                    self.productA = product
                    print("✅ Slot A: \(product.nome)")
                } else if self.productB == nil {
                    self.productB = product
                    print("✅ Slot B: \(product.nome)")
                }
                // se entrambi gli slot sono pieni, ulteriori marker vengono ignorati
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let msg = (error as NSError).localizedDescription
        Task { @MainActor in self.sessionError = "Errore AR: \(msg)" }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in self.startSession() }
    }
}
