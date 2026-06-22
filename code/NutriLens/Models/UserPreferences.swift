import Foundation

// MARK: allergeni basati sui 14 allergeni obbligatori EU (Open Food Facts taxonomy)
enum Allergen: String, CaseIterable, Identifiable, Codable {
    case none       = "Nessuno"
    case gluten     = "Glutine"
    case milk       = "Latte"
    case eggs       = "Uova"
    case peanuts    = "Arachidi"
    case nuts       = "Frutta a guscio"
    case fish       = "Pesce"
    case shellfish  = "Crostacei"
    case soy        = "Soia"
    case celery     = "Sedano"
    case mustard    = "Senape"
    case sesame     = "Sesamo"
    case sulphites  = "Solfiti"
    case lupin      = "Lupini"
    case molluscs   = "Molluschi"

    var id: String { rawValue }

    // tag ufficiale Open Food Facts
    var openFoodFactsTag: String? {
        switch self {
        case .none:      return nil
        case .gluten:    return "en:gluten"
        case .milk:      return "en:milk"
        case .eggs:      return "en:eggs"
        case .peanuts:   return "en:peanuts"
        case .nuts:      return "en:nuts"
        case .fish:      return "en:fish"
        case .shellfish: return "en:crustaceans"
        case .soy:       return "en:soybeans"
        case .celery:    return "en:celery"
        case .mustard:   return "en:mustard"
        case .sesame:    return "en:sesame-seeds"
        case .sulphites: return "en:sulphur-dioxide-and-sulphites"
        case .lupin:     return "en:lupin"
        case .molluscs:  return "en:molluscs"
        }
    }

    var emoji: String {
        switch self {
        case .none:      return "✓"
        case .gluten:    return "🌾"
        case .milk:      return "🥛"
        case .eggs:      return "🥚"
        case .peanuts:   return "🥜"
        case .nuts:      return "🌰"
        case .fish:      return "🐟"
        case .shellfish: return "🦐"
        case .soy:       return "🫘"
        case .celery:    return "🥬"
        case .mustard:   return "🌼"
        case .sesame:    return "🫙"
        case .sulphites: return "🍷"
        case .lupin:     return "🌿"
        case .molluscs:  return "🐚"
        }
    }
}

// MARK: esigenze dietetiche (rappresentano le preferenze alimentari dell’utente.)
enum DietaryNeed: String, CaseIterable, Identifiable, Codable {
    case none           = "Nessuno"
    case vegetarian     = "Vegetariano"
    case vegan          = "Vegano"
    case glutenFree     = "Senza glutine"
    case lactoseFree    = "Senza lattosio"
    case lowSugar       = "Basso contenuto di zuccheri"
    case lowSalt        = "Basso contenuto di sale"
    case organic        = "Biologico"
    case halal          = "Halal"
    case kosher         = "Kosher"

    var id: String { rawValue }

    // tag ufficiale Open Food Facts (campo labels_tags)
    var openFoodFactsTag: String? {
        switch self {
        case .none:         return nil
        case .vegetarian:   return "en:vegetarian"
        case .vegan:        return "en:vegan"
        case .glutenFree:   return "en:gluten-free"
        case .lactoseFree:  return "en:lactose-free"
        case .lowSugar:     return "en:low-sugar"
        case .lowSalt:      return "en:low-salt"
        case .organic:      return "en:organic"
        case .halal:        return "en:halal"
        case .kosher:       return "en:kosher"
        }
    }

    var emoji: String {
        switch self {
        case .none:         return "✓"
        case .vegetarian:   return "🌱"
        case .vegan:        return "🌿"
        case .glutenFree:   return "🚫🌾"
        case .lactoseFree:  return "🚫🥛"
        case .lowSugar:     return "🍬"
        case .lowSalt:      return "🧂"
        case .organic:      return "♻️"
        case .halal:        return "☪️"
        case .kosher:       return "✡️"
        }
    }
}

// MARK: modello utente con preferenze - esigenze
struct UserPreferences: Codable {
    var allergens: Set<Allergen>
    var dietaryNeeds: Set<DietaryNeed>

    static let defaultKey = "nutrilens_user_preferences"

    static func load() -> UserPreferences? {
        guard let data = UserDefaults.standard.data(forKey: defaultKey),
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
            return nil
        }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: UserPreferences.defaultKey)
        }
    }
}
