import Foundation
// MARK: struttura principale che rappresenta un prodotto alimentare.
struct Product: Identifiable, Codable, Equatable {
    // attributi di prodotto P
    let id: String
    let nome: String
    let nutriscore: String
    let nutritional_values: NutritionalValues
    let allergeni: [String: Bool]
    let tracce: [String: Bool]
    let dieta: [String: Bool]
    
    //valori nutrizionali di prodotto P
    struct NutritionalValues: Codable, Equatable {
        let energia: String?
        let zuccheri: String?
        let grassi: String?
        let sale: String?
        let proteine: String?
        let fibra: String?
        let frutta_verdura: String?
    }

    // Colore associato al Nutri-Score (A=verde scuro, B=verde chiaro, …, E=rosso)
    var nutriscoreColor: String {
        switch nutriscore.uppercased() {
        case "A": return "#038141"
        case "B": return "#85BB2F"
        case "C": return "#FECB02"
        case "D": return "#EE8100"
        case "E": return "#E63312"
        default:  return "#888888" //feedback neutro
        }
    }

    
    // valutazione rispetto alle esigenze o preferenze utente
    private static let allergenKeyMap: [Allergen: String] = [
        .gluten:    "glutine",
        .milk:      "latte",
        .eggs:      "uova",
        .peanuts:   "arachidi",
        .nuts:      "frutta_guscio",
        .fish:      "pesce",
        .shellfish: "crostacei",
        .soy:       "soia",
        .celery:    "sedano",
        .mustard:   "senape",
        .sesame:    "sesamo",
        .sulphites: "solfiti",
        .lupin:     "lupini",
        .molluscs:  "molluschi"
    ]

    private static let dietKeyMap: [DietaryNeed: String] = [
        .vegetarian:  "vegetariano",
        .vegan:       "vegano",
        .glutenFree:  "senza_glutine",
        .lactoseFree: "senza_lattosio",
        .lowSugar:    "basso_zucchero",
        .lowSalt:     "basso_sale",
        .organic:     "biologico",
        .halal:       "halal",
        .kosher:      "kosher"
    ]

    // MARK: validazione dello stato di sicurezza del prodotto P rispetto a utente
    enum SafetyStatus { case danger, warning, safe }

    // dettaglio degli allergeni/tracce/diete che causano un alert.
    struct AlertDetails {
        var presentAllergens: [Allergen] = []
        var traceAllergens: [Allergen] = []
        var unsatisfiedDiets: [DietaryNeed] = []

        var isEmpty: Bool { presentAllergens.isEmpty && traceAllergens.isEmpty && unsatisfiedDiets.isEmpty }
    }

    // restituisce lo stato sicurezza rispetto alle preferenze dell'utente
    func safetyStatus(for prefs: UserPreferences) -> SafetyStatus {
        // 1. Allergeni diretti → ROSSO
        for allergen in prefs.allergens where allergen != .none {
            if let key = Self.allergenKeyMap[allergen], allergeni[key] == true {
                return .danger
            }
        }
        // 2. tracce → GIALLO
        for allergen in prefs.allergens where allergen != .none {
            if let key = Self.allergenKeyMap[allergen], tracce[key] == true {
                return .warning
            }
        }
        // 3. dieta non rispettata → ROSSO
        for need in prefs.dietaryNeeds where need != .none {
            if let key = Self.dietKeyMap[need], dieta[key] != true {
                return .danger
            }
        }
        // nessun problema → VERDE
        return .safe
    }
    
    // restituisce il dettaglio di tutti i problemi rilevati rispetto alle preferenze utente.
    func alertDetails(for prefs: UserPreferences) -> AlertDetails {
        // allergeni e tracce
        var details = AlertDetails()
        for allergen in prefs.allergens where allergen != .none {
            if let key = Self.allergenKeyMap[allergen] {
                if allergeni[key] == true { details.presentAllergens.append(allergen) }
                else if tracce[key] == true { details.traceAllergens.append(allergen) }
            }
        }
        // diete non rispettate
        for need in prefs.dietaryNeeds where need != .none {
            if let key = Self.dietKeyMap[need], dieta[key] != true {
                details.unsatisfiedDiets.append(need)
            }
        }
        return details
    }
}

// MARK: carica in memoria sincrona all'avvio dell'applicazione il file JSON contenente l'intero catalogo prodotti.
final class ProductDatabase {
    static let shared = ProductDatabase()
    // dizionario dei prodotti
    private(set) var products: [String: Product] = [:]

    private init() { load() }
    // carica products.json
    private func load() {
        guard
            let url  = Bundle.main.url(forResource: "products", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            print("⚠️ products.json non trovato nel bundle.")
            return
        }

        if let dict = try? JSONDecoder().decode([String: Product].self, from: data) {
            products = dict
            print("✅ Database caricato: \(products.count) prodotti.")
        } else {
            print("⚠️ Impossibile decodificare products.json.")
        }
    }
    // dato l'ID restituisce il prodotto corrispondente
    func product(forMarkerID id: String) -> Product? {
        products[id]
    }
}
