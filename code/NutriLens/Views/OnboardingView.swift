import SwiftUI
// MARK: modello preferenze utente
struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var selectedAllergens: Set<Allergen> = []
    @State private var selectedDietary: Set<DietaryNeed> = []
    @State private var showValidationAlert = false
    @State private var shakeAllergens = false
    @State private var shakeDietary = false

    private let allergenColor = Color(red: 0.85, green: 0.24, blue: 0.19)
    private let dietaryColor  = Color(red: 0.16, green: 0.62, blue: 0.38)
    private var allergensMissing: Bool { selectedAllergens.isEmpty }
    private var dietaryMissing: Bool   { selectedDietary.isEmpty }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    
                    // header
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Ciao!👋🏼")
                            .font(.system(size: 32, weight: .bold))
                        Text("Prima di iniziare, seleziona le tue esigenze così NutriLens potrà avvisarti in tempo reale.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 20)
                    
                    // sezione Allergeni
                    SectionCard(
                        title: "Allergeni",
                        subtitle: "Seleziona tutti quelli che ti riguardano",
                        accentColor: allergenColor,
                        hasError: allergensMissing && shakeAllergens
                    ) {
                        ChipGrid(
                            items: Allergen.allCases,
                            selected: $selectedAllergens,
                            exclusiveItem: .none,
                            accentColor: allergenColor,
                            label: { "\($0.emoji) \($0.rawValue)" }
                        )
                    }
                    .modifier(ShakeEffect(trigger: shakeAllergens))
                    
                    // sezione esigenze dietetiche
                    SectionCard(
                        title: "Esigenze dietetiche",
                        subtitle: "Seleziona le diete che segui",
                        accentColor: dietaryColor,
                        hasError: dietaryMissing && shakeDietary
                    ) {
                        ChipGrid(
                            items: DietaryNeed.allCases,
                            selected: $selectedDietary,
                            exclusiveItem: .none,
                            accentColor: dietaryColor,
                            label: { "\($0.emoji) \($0.rawValue)" }
                        )
                    }
                    .modifier(ShakeEffect(trigger: shakeDietary))
                    // info footer
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                        Text("Dati forniti da Open Food Facts.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    
                    // bottone
                    Button(action: saveAndContinue) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Salva")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 20)
            }
            // controlli
            .alert("Attenzione", isPresented: $showValidationAlert) {
                Button("Ok", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
        }
    }

    // MARK: messaggio dinamico dell’alert
    private var validationMessage: String {
        if allergensMissing && dietaryMissing {
            return "Seleziona almeno un'opzione per gli allergeni e per le esigenze dietetiche. Se non hai bisogni particolari, scegli \"Nessuno\"."
        } else if allergensMissing {
            return "Seleziona almeno un'opzione per gli allergeni. Se non hai allergie, scegli \"Nessuno\"."
        } else {
            return "Seleziona almeno un'opzione per le esigenze dietetiche. Se non ne hai, scegli \"Nessuno\"."
        }
    }
    
    private func saveAndContinue() {
        guard !allergensMissing && !dietaryMissing else {
            // anima le sezioni mancanti con shake
            if allergensMissing {
                shakeAllergens = false
                withAnimation { shakeAllergens = true }
            }
            if dietaryMissing {
                shakeDietary = false
                withAnimation { shakeDietary = true }
            }
            showValidationAlert = true
            return
        }
        // salva preferenze utente
        let prefs = UserPreferences(allergens: selectedAllergens, dietaryNeeds: selectedDietary)
        prefs.save()
        onComplete()
    }
}

// MARK: compilazione onboarding
struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let accentColor: Color
    var hasError: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(hasError ? .red : accentColor)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(hasError ? Color.red.opacity(0.8) : .secondary)
            }
            content
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hasError ? Color.red : Color.clear, lineWidth: 1.5)
        )
    }
}

struct ShakeEffect: ViewModifier {
    var trigger: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: trigger ? 6 : 0)
            .animation(
                trigger
                    ? .interpolatingSpring(stiffness: 600, damping: 8).repeatCount(1, autoreverses: true)
                    : .default,
                value: trigger
            )
    }
}


struct ChipGrid<T: Hashable & CaseIterable & Identifiable>: View where T.AllCases: RandomAccessCollection {
    let items: T.AllCases
    @Binding var selected: Set<T>
    let exclusiveItem: T
    let accentColor: Color
    let label: (T) -> String

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                let isSelected = selected.contains(item)
                Button(action: { toggle(item) }) {
                    Text(label(item))
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(isSelected ? accentColor.opacity(0.15) : Color(.systemGray6))
                        .foregroundStyle(isSelected ? accentColor : .primary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? accentColor : Color.clear, lineWidth: 1.5)
                        )
                }
                .animation(.spring(duration: 0.2), value: isSelected)
            }
        }
    }

    private func toggle(_ item: T) {
        if item == exclusiveItem {
            // "Nessuno" deseleziona tutto il resto
            selected = selected.contains(item) ? [] : [item]
        } else {
            // Selezionare altro rimuove "Nessuno"
            selected.remove(exclusiveItem)
            if selected.contains(item) {
                selected.remove(item)
            } else {
                selected.insert(item)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
