import SwiftUI

struct SuccessView: View {
    var onContinue: () -> Void

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var checkScale: CGFloat = 0.1
    @State private var textOffset: CGFloat = 30

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 110, height: 110)

                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .frame(width: 72, height: 72)
                    .foregroundStyle(.green)
                    .scaleEffect(checkScale)
            }
            .scaleEffect(scale)
            .opacity(opacity)

            VStack(spacing: 10) {
                // testo di conferma post "registrazione"
                Text("Ottimo!🎉")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Le tue preferenze sono salvate.\nNutriLens è pronto a scansionare i tuoi prodotti.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .offset(y: textOffset)
            .opacity(opacity)

            Spacer()

            // bottone continua
            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                    Text("Inizia a scansionare")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
            .opacity(opacity)
            .offset(y: textOffset)
        }
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
            scale = 1.0
            opacity = 1.0
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.15)) {
            checkScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.2)) {
            textOffset = 0
        }
    }
}

#Preview {
    SuccessView(onContinue: {})
}
