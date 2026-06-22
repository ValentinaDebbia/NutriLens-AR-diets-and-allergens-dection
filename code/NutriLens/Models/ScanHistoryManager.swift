import Foundation
import SwiftUI
import Combine

// MARK: rappresenta una singola voce della cronologia delle scansioni.
// ogni volta che l’utente scansiona un prodotto, viene creato un nuovo entry.
struct ScanHistoryEntry: Identifiable, Codable {
    let id: UUID
    let productName: String
    let productID: String
    let nutriscore: String
    let safetyStatus: SafetyStatusCodable
    let alertSummary: String
    let date: Date
    let source: ScanSource      // scanner singolo o confronto

    enum ScanSource: String, Codable {
        case scanner = "Scanner"
        case compare = "Confronto"
    }

    enum SafetyStatusCodable: String, Codable {
        case safe, warning, danger

        var color: Color {
            switch self {
            case .safe:    return Color(red: 0.04, green: 0.51, blue: 0.26)
            case .warning: return Color(red: 0.93, green: 0.64, blue: 0.0)
            case .danger:  return Color(red: 0.85, green: 0.14, blue: 0.10)
            }
        }

        var icon: String {
            switch self {
            case .safe:    return "checkmark.seal.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .danger:  return "xmark.octagon.fill"
            }
        }

        var label: String {
            switch self {
            case .safe:    return "Sicuro"
            case .warning: return "Attenzione"
            case .danger:  return "Allerta"
            }
        }
    }

    // MARK: inizializzatore personalizzato che trasforma un oggetto `Product` e il suo responso di sicurezza
    init(product: Product, status: Product.SafetyStatus, details: Product.AlertDetails, source: ScanSource) {
        self.id = UUID()
        self.productName = product.nome
        self.productID = product.id
        self.nutriscore = product.nutriscore
        self.source = source
        self.date = Date()

        switch status {
        case .safe:    self.safetyStatus = .safe
        case .warning: self.safetyStatus = .warning
        case .danger:  self.safetyStatus = .danger
        }

        // costruisce il riepilogo degli avvisi
        var parts: [String] = []
        if !details.presentAllergens.isEmpty {
            let names = details.presentAllergens.map { "\($0.rawValue)" }.joined(separator: ", ")
            parts.append("Allergeni: \(names)")
        }
        if !details.traceAllergens.isEmpty {
            let names = details.traceAllergens.map { "\($0.rawValue)" }.joined(separator: ", ")
            parts.append("Tracce: \(names)")
        }
        if !details.unsatisfiedDiets.isEmpty {
            let names = details.unsatisfiedDiets.map { "\($0.rawValue)" }.joined(separator: ", ")
            parts.append("Dieta: \(names)")
        }
        // se non ci sono problemi → "Nessun avviso"
        self.alertSummary = parts.isEmpty ? "Nessun avviso" : parts.joined(separator: " • ")
    }
}

// MARK: gestisce l’intera cronologia delle scansioni.
final class ScanHistoryManager: ObservableObject {
    static let shared = ScanHistoryManager()
    // array reattivo contenente l'elenco cronologico delle scansioni
    @Published private(set) var entries: [ScanHistoryEntry] = []

    private let storageKey = "nutrilens_scan_history"
    private let maxEntries = 50

    private init() { load() } //carica la cronologia all'avvio dell'app

    // aggiunge una nuova voce alla cronologia
    func add(_ entry: ScanHistoryEntry) {
        // evita duplicati ravvicinati (stesso prodotto entro 5 secondi → ignora)
        if let last = entries.first, last.productID == entry.productID,
           abs(last.date.timeIntervalSince(entry.date)) < 5 { return }

        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        save()
    }

    func clearAll() {
        entries = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ScanHistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }
}
