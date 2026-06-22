import SwiftUI
import ARKit
import SceneKit

// MARK: mostra il feed live della fotocamera tramite ARSCNView,
// condividendo la ARSession già gestita da ARRecognitionManager.
struct ARCameraView: UIViewRepresentable {

    let arSession: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView          = ARSCNView()
        // collega la sessione AR già configurata dal manager
        sceneView.session      = arSession
        sceneView.autoenablesDefaultLighting = false
        sceneView.automaticallyUpdatesLighting = false

        sceneView.scene        = SCNScene()

        sceneView.showsStatistics = false
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
    }
}
