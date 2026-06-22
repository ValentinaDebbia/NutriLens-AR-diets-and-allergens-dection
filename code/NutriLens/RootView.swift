import SwiftUI
// MARK: vista radice dell'applicazione
struct RootView: View {
    // indica se l’utente ha già completato l’onboarding.
    // se UserPreferences.load() restituisce un valore → onboarding già fatto.
    @State private var hasCompletedOnboarding: Bool = UserPreferences.load() != nil

    // controlla se mostrare la schermata di successo dopo l’onboarding
    @State private var showSuccess = false

    var body: some View {
        // se l’utente ha appena finito l’onboarding → mostra la success screen.
        if showSuccess {
            SuccessView {
                // Quando l’utente chiude la success screen:
                showSuccess = false          // nascondi la success screen
                hasCompletedOnboarding = true // segna l’onboarding come completato
            }

        // se l’onboarding è già stato completato in passato → vai allo scanner.
        } else if hasCompletedOnboarding {
            ScannerView()

        // altrimenti → l’utente è nuovo, quindi mostra l’onboarding.
        } else {
            OnboardingView {
                // quando l’onboarding termina → attiva la success screen.
                showSuccess = true
            }
        }
    }
}
