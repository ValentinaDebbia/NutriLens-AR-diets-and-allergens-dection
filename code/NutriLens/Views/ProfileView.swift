import SwiftUI

// MARK: profilo

struct ProfileView: View {

    @State private var savedPrefs: UserPreferences = UserPreferences.load()
        ?? UserPreferences(allergens: [], dietaryNeeds: [])
    @State private var showEditSheet = false
    @State private var showHistoryBook = false
    @State private var appeared = false
    @State private var showARHistory = false
    @ObservedObject var historyManager = ScanHistoryManager.shared
    private let allergenColor  = Color(red: 0.85, green: 0.18, blue: 0.14)
    private let dietaryColor   = Color(red: 0.09, green: 0.56, blue: 0.32)
    private let accentGold     = Color(red: 0.82, green: 0.64, blue: 0.18)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                backgroundLayer.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroHeader
                            .padding(.top, 8)

                        VStack(spacing: 16) {
                            allergenCard
                            dietaryCard
                            dataSourceNote
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Profilo")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    editButton
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditPreferencesSheet(currentPrefs: savedPrefs) { updated in
                    savedPrefs = updated
                }
            }
            .fullScreenCover(isPresented: $showHistoryBook) {
                ARHistoryBookView()
            }
            // MARK: carico preferenze utente
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.1)) {
                    appeared = true
                }
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.05, green: 0.55, blue: 0.30).opacity(0.18), Color.clear],
                    center: .center, startRadius: 10, endRadius: 200
                ))
                .frame(width: 400, height: 400)
                .offset(x: -60, y: -120)
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.10, green: 0.65, blue: 0.38), Color(red: 0.03, green: 0.45, blue: 0.25)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 86, height: 86)
                .shadow(color: Color(red: 0.03, green: 0.45, blue: 0.25).opacity(0.6), radius: 30)
        }
    }

    // MARK: header
    private var heroHeader: some View {
        // foto profilo utente
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.85, blue: 0.58),
                                Color(red: 0.15, green: 0.70, blue: 0.42)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 96, height: 96)

                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.25, green: 0.80, blue: 0.52), Color(red: 0.10, green: 0.62, blue: 0.36)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 86, height: 86)
                    .shadow(color: Color(red: 0.10, green: 0.62, blue: 0.36).opacity(0.5), radius: 30)

                Image(systemName: "person.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            .padding(.bottom, 14)
            // recap esigenze utente
            VStack(spacing: 4) {
                Text("Le mie preferenze")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                let total = activeAllergenCount + activeDietaryCount
                let label = total == 1 ? "esigenza" : "esigenze"

                Text(total == 0
                     ? "Nessuna esigenza impostata"
                     : "\(total) \(label) configurate")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .offset(y: appeared ? 0 : 12)
            .opacity(appeared ? 1 : 0)

            HStack(spacing: 12) {
                // bottone cronologia
                Button {
                    showHistoryBook = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "book.pages.fill")
                            .font(.subheadline.weight(.semibold))
                        Text("Cronologia")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.05, green: 0.45, blue: 0.25), Color(red: 0.02, green: 0.30, blue: 0.16)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(red: 0.02, green: 0.30, blue: 0.16).opacity(0.4), radius: 8, y: 4)
                }
            }
            .padding(.top, 20)
            .offset(y: appeared ? 0 : 16)
            .opacity(appeared ? 1 : 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .animation(.spring(response: 0.65, dampingFraction: 0.75).delay(0.1), value: appeared)
    }

    private var allergenCard: some View {
        ProfileCard(
            title: "Allergeni",
            subtitle: activeAllergenCount == 0 ? "Nessuna allergia" : "\(activeAllergenCount) attivi",
            icon: "exclamationmark.triangle.fill",
            accentColor: allergenColor,
            appeared: appeared,
            delay: 0.15
        ) {
            FlowLayout(spacing: 8) {
                ForEach(allergenItems, id: \.label) { item in
                    PreferenceChip(emoji: item.emoji, label: item.label, color: allergenColor)
                }
            }
        }
    }

    private var dietaryCard: some View {
        ProfileCard(
            title: "Esigenze dietetiche",
            subtitle: activeDietaryCount == 0 ? "Nessuna esigenza" : "\(activeDietaryCount) attive",
            icon: "leaf.fill",
            accentColor: dietaryColor,
            appeared: appeared,
            delay: 0.25
        ) {
            FlowLayout(spacing: 8) {
                ForEach(dietaryItems, id: \.label) { item in
                    PreferenceChip(emoji: item.emoji, label: item.label, color: dietaryColor)
                }
            }
        }
    }

    private var dataSourceNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("Dati forniti da Open Food Facts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.4), value: appeared)
    }

    private var editButton: some View {
        Button { showEditSheet = true } label: {
            // pulsante matita — in editButton
            Image(systemName: "pencil.circle.fill")
                .font(.title3)
                .foregroundStyle(Color(red: 0.15, green: 0.72, blue: 0.44))
        }
    }

    private var activeAllergenCount: Int { savedPrefs.allergens.filter { $0 != .none }.count }
    private var activeDietaryCount: Int  { savedPrefs.dietaryNeeds.filter { $0 != .none }.count }

    private var allergenItems: [(emoji: String, label: String)] {
        let active = savedPrefs.allergens.filter { $0 != .none }.sorted { $0.rawValue < $1.rawValue }
        return active.isEmpty ? [("✓", "Nessuna allergia")] : active.map { ($0.emoji, $0.rawValue) }
    }

    private var dietaryItems: [(emoji: String, label: String)] {
        let active = savedPrefs.dietaryNeeds.filter { $0 != .none }.sorted { $0.rawValue < $1.rawValue }
        return active.isEmpty ? [("✓", "Nessuna esigenza dietetica")] : active.map { ($0.emoji, $0.rawValue) }
    }
}

// MARK: modifica preferenze utente 
struct ProfileCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let accentColor: Color
    let appeared: Bool
    let delay: Double
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(accentColor.opacity(0.8))
                }
                Spacer()
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: accentColor.opacity(0.5), radius: 4)
            }

            Divider().overlay(accentColor.opacity(0.15))

            content()
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(accentColor.opacity(0.10), lineWidth: 1)
        )
        .offset(y: appeared ? 0 : 20)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.55, dampingFraction: 0.78).delay(delay), value: appeared)
    }
}

struct PreferenceChip: View {
    let emoji: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(emoji).font(.caption)
            Text(label).font(.subheadline).foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.09))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1))
    }
}

// modifica preferenze
struct EditPreferencesSheet: View {
    let currentPrefs: UserPreferences
    let onSave: (UserPreferences) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedAllergens: Set<Allergen>
    @State private var selectedDietary: Set<DietaryNeed>
    @State private var showDiscardAlert = false
    @State private var showValidationAlert = false
    @State private var shakeAllergens = false
    @State private var shakeDietary = false

    private let allergenColor = Color(red: 0.85, green: 0.18, blue: 0.14)
    private let dietaryColor  = Color(red: 0.09, green: 0.56, blue: 0.32)

    init(currentPrefs: UserPreferences, onSave: @escaping (UserPreferences) -> Void) {
        self.currentPrefs = currentPrefs
        self.onSave = onSave
        _selectedAllergens = State(initialValue: currentPrefs.allergens)
        _selectedDietary   = State(initialValue: currentPrefs.dietaryNeeds)
    }

    private var hasChanges: Bool {
        selectedAllergens != currentPrefs.allergens || selectedDietary != currentPrefs.dietaryNeeds
    }
    private var allergensMissing: Bool { selectedAllergens.isEmpty }
    private var dietaryMissing: Bool   { selectedDietary.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary).font(.footnote)
                        Text("Dati forniti da Open Food Facts.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)

                    Button(action: trySave) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Salva modifiche").fontWeight(.semibold)
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
                .padding(.top, 8)
            }
            .navigationTitle("Modifica preferenze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") {
                        if hasChanges { showDiscardAlert = true } else { dismiss() }
                    }
                }
            }
            .alert("Scartare le modifiche?", isPresented: $showDiscardAlert) {
                Button("Scarta", role: .destructive) { dismiss() }
                Button("Continua a modificare", role: .cancel) { }
            } message: { Text("Le modifiche non salvate andranno perse.") }
            .alert("Attenzione", isPresented: $showValidationAlert) {
                Button("Ok", role: .cancel) { }
            } message: { Text(validationMessage) }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    private var validationMessage: String {
        if allergensMissing && dietaryMissing {
            return "Seleziona almeno un'opzione per gli allergeni e per le esigenze dietetiche. Se non hai bisogni particolari, scegli \"Nessuno\"."
        } else if allergensMissing {
            return "Seleziona almeno un'opzione per gli allergeni. Se non hai allergie, scegli \"Nessuno\"."
        } else {
            return "Seleziona almeno un'opzione per le esigenze dietetiche. Se non ne hai, scegli \"Nessuno\"."
        }
    }

    private func trySave() {
        guard !allergensMissing && !dietaryMissing else {
            if allergensMissing { shakeAllergens = false; withAnimation { shakeAllergens = true } }
            if dietaryMissing   { shakeDietary   = false; withAnimation { shakeDietary   = true } }
            showValidationAlert = true
            return
        }
        let updated = UserPreferences(allergens: selectedAllergens, dietaryNeeds: selectedDietary)
        updated.save()
        onSave(updated)
        dismiss()
    }
}

#Preview { ProfileView() }
