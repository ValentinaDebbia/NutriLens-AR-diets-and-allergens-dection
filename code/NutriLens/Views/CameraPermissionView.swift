import SwiftUI

struct CameraPermissionView: View {
    // MARK: gestore dei permessi fotocamera
    @ObservedObject var permissionManager: CameraPermissionManager
    let isDenied: Bool
    // indica se l’utente ha esplicitamente negato il permesso
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            // icona dinamica: diversa se il permesso è negato o solo non ancora richiesto
            Image(systemName: isDenied ? "camera.fill.badge.ellipsis" : "camera.viewfinder")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .foregroundStyle(isDenied ? .red : .accentColor)
            
            VStack(spacing: 10) {
                Text(isDenied ? "Accesso fotocamera negato" : "Accesso alla fotocamera")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(isDenied
                     ? "NutriLens ha bisogno della fotocamera per scansionare i prodotti. Puoi abilitarla in Impostazioni > NutriLens > Fotocamera."
                     : "NutriLens usa la fotocamera per riconoscere i prodotti alimentari e mostrarne il Nutri-Score in tempo reale.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            // bottone dinamico:
            // - se negato → porta alle Impostazioni
            // - se non ancora deciso → richiede il permesso
            if isDenied {
                Button("Apri Impostazioni") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button("Consenti accesso fotocamera") {
                    Task { await permissionManager.request() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding(28)
    }
}
