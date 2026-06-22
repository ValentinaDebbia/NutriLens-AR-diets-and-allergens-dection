import SwiftUI
import ARKit

func compareNutriscoreHex(_ grade: String) -> String {
    switch grade.uppercased() {
    case "A": return "038141"; case "B": return "85BB2F"; case "C": return "FECB02"
    case "D": return "EE8100"; case "E": return "E63312"; default: return "AAAAAA"
    }
}

// MARK: restituisce il rango numerico del Nutri-Score: A=1 (migliore), ..., E=5 (peggiore).
func nutriscoreRank(_ grade: String) -> Int {
    switch grade.uppercased() {
    case "A": return 1; case "B": return 2; case "C": return 3
    case "D": return 4; case "E": return 5; default: return 99
    }
}

struct CompareView: View {

    @StateObject private var arManager = ARCompareManager()
    private let prefs = UserPreferences.load() ?? UserPreferences(allergens: [], dietaryNeeds: [])
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    @State private var showAROverlays: Bool = false

    private func statusColor(_ status: Product.SafetyStatus) -> Color {
        switch status {
        case .safe:    return Color(red: 0.30, green: 0.85, blue: 0.45)
        case .warning: return Color(red: 1.0,  green: 0.88, blue: 0.20)
        case .danger:  return Color(red: 1.0,  green: 0.35, blue: 0.35)
        }
    }

    // sfondo quando entrambi i prodotti sono stati inquadrati.
    @ViewBuilder
    private func compareBackgroundOverlay(a: Product, b: Product) -> some View {
        let sA = a.safetyStatus(for: prefs)
        let sB = b.safetyStatus(for: prefs)
        let cA = statusColor(sA)
        let cB = statusColor(sB)

        if sA == sB {
            // stesso stato → colore uniforme
            cA.opacity(0.45).ignoresSafeArea()
        } else {
            // stato diverso → schermo diviso a metà
            GeometryReader { geo in
                HStack(spacing: 0) {
                    cA.opacity(0.45).frame(width: geo.size.width / 2)
                    cB.opacity(0.45).frame(width: geo.size.width / 2)
                }
            }
            .ignoresSafeArea()
        }
    }

    // sfondo quando solo il primo prodotto è stato inquadrato.
    @ViewBuilder
    private func singleProductBackground(product: Product) -> some View {
        let status = product.safetyStatus(for: prefs)
        statusColor(status).opacity(0.45).ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            ARCameraView(arSession: arManager.arSession)
                .ignoresSafeArea()

            // sfondo colorato: appare già dal primo prodotto inquadrato
            if let a = arManager.productA, let b = arManager.productB {
                // entrambi inquadrati → sfondo split (o uniforme se stesso stato)
                compareBackgroundOverlay(a: a, b: b)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.5), value: arManager.isComplete)
            } else if let a = arManager.productA {
                // solo il primo → sfondo uniforme basato sullo stato del primo
                singleProductBackground(product: a)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: arManager.productA?.id)
            }

            // tap fuori dagli overlay → chiude e resetta
            if showAROverlays {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { resetAll() }
                    .zIndex(9)
            }

            topGradient

            // mirini + hint
            VStack(spacing: 0) {
                Spacer()
                if !showAROverlays { scanningOverlay }
                Spacer()
            }
            .animation(.spring(duration: 0.4), value: arManager.isComplete)
            .animation(.spring(duration: 0.4), value: showAROverlays)

            if let err = arManager.sessionError { errorBanner(err) }

            if showAROverlays, let a = arManager.productA, let b = arManager.productB {
                let bothSafeAR = a.safetyStatus(for: prefs) == .safe && b.safetyStatus(for: prefs) == .safe
                let crownA = bothSafeAR && nutriscoreRank(a.nutriscore) < nutriscoreRank(b.nutriscore)
                let crownB = bothSafeAR && nutriscoreRank(b.nutriscore) < nutriscoreRank(a.nutriscore)

                CompareAROverlay(
                    product: a,
                    status: a.safetyStatus(for: prefs),
                    details: a.alertDetails(for: prefs),
                    side: .left,
                    showCrown: crownA
                )
                .zIndex(10)
                .transition(.opacity.combined(with: .scale(scale: 0.88, anchor: .bottom)))
                .allowsHitTesting(true)

                CompareAROverlay(
                    product: b,
                    status: b.safetyStatus(for: prefs),
                    details: b.alertDetails(for: prefs),
                    side: .right,
                    showCrown: crownB
                )
                .zIndex(10)
                .transition(.opacity.combined(with: .scale(scale: 0.88, anchor: .bottom)))
                .allowsHitTesting(true)
            } else if showAROverlays, let a = arManager.productA {
                CompareAROverlay(
                    product: a,
                    status: a.safetyStatus(for: prefs),
                    details: a.alertDetails(for: prefs),
                    side: .left
                )
                .zIndex(10)
                .transition(.opacity.combined(with: .scale(scale: 0.88, anchor: .bottom)))
                .allowsHitTesting(true)
            }
        }
        .onAppear  { arManager.startSession() }
        .onDisappear { arManager.pauseSession() }
        .gesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                guard arManager.isComplete else { return }
                haptic.impactOccurred()
                withAnimation(.spring(duration: 0.45)) { showAROverlays = true }
            }
        )
        .onChange(of: arManager.isComplete) { _, complete in
            if !complete { resetAll() }
            // salva entrambi i prodotti in cronologia quando il confronto è completo
            if complete {
                let prefs = UserPreferences.load() ?? UserPreferences(allergens: [], dietaryNeeds: [])
                if let a = arManager.productA {
                    let entry = ScanHistoryEntry(
                        product: a,
                        status: a.safetyStatus(for: prefs),
                        details: a.alertDetails(for: prefs),
                        source: .compare
                    )
                    ScanHistoryManager.shared.add(entry)
                }
                if let b = arManager.productB {
                    let entry = ScanHistoryEntry(
                        product: b,
                        status: b.safetyStatus(for: prefs),
                        details: b.alertDetails(for: prefs),
                        source: .compare
                    )
                    ScanHistoryManager.shared.add(entry)
                }
            }
        }
    }

    private func resetAll() {
        withAnimation(.spring(duration: 0.35)) {
            showAROverlays = false
            arManager.resetAll()
        }
    }

    private var topGradient: some View {
        VStack {
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 120)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .topLeading) {
                Text("NutriLens")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 58)
            }
            Spacer()
        }
    }


    private var scanningOverlay: some View {
        VStack(spacing: 20) {
            HStack(spacing: 24) {
                let bothSafe: Bool = {
                    guard let a = arManager.productA, let b = arManager.productB else { return false }
                    return a.safetyStatus(for: prefs) == .safe && b.safetyStatus(for: prefs) == .safe
                }()
                let crownA: Bool = bothSafe && {
                    guard let a = arManager.productA, let b = arManager.productB else { return false }
                    return nutriscoreRank(a.nutriscore) < nutriscoreRank(b.nutriscore)
                }()
                let crownB: Bool = bothSafe && {
                    guard let a = arManager.productA, let b = arManager.productB else { return false }
                    return nutriscoreRank(b.nutriscore) < nutriscoreRank(a.nutriscore)
                }()

                slotViewfinder(product: arManager.productA, label: "Prodotto 1", color: .blue,  showCrown: crownA)
                slotViewfinder(product: arManager.productB, label: "Prodotto 2", color: .orange, showCrown: crownB)
            }
            .padding(.horizontal, 20)

            let hint: String = {
                if arManager.productA == nil {
                    return "Inquadra il primo prodotto"
                } else if arManager.productB == nil {
                    return "Ora inquadra il secondo"
                } else {
                    return "Tieni premuto per i dettagli"
                }
            }()

            let showHandIcon = arManager.productA != nil && arManager.productB != nil

            HStack(spacing: 8) {
                if showHandIcon {
                    Image(systemName: "hand.tap.fill").font(.footnote)
                }
                Text(hint).font(.footnote.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .animation(.default, value: arManager.productA?.id)
            .animation(.default, value: arManager.productB?.id)
        }
    }

    private func slotViewfinder(product: Product?, label: String, color: Color, showCrown: Bool = false) -> some View {
        let size = (UIScreen.main.bounds.width - 64) / 2
        return ZStack {
            if let product {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: product.nutriscoreColor).opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(hex: product.nutriscoreColor), lineWidth: 2.5)
                    )
                    .overlay {
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                NutriScoreBadge(grade: product.nutriscore, size: 48)
                                if showCrown {
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.system(size: 18))
                                        .offset(x: 10, y: -12)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showCrown)
                            Text(product.nome)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 6)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        color.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2.5, dash: [8, 5])
                    )
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 28))
                                .foregroundStyle(color.opacity(0.8))
                            Text(label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
            }
        }
        .frame(width: size, height: size * 1.15)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.footnote)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 100)
        }
    }
}

// MARK: card AR compatta posizionata a sinistra e destra dello schermo, con le stesse informazioni degli overlay singoli (Nutri-Score + dettagli allergeni/dieta).
struct CompareAROverlay: View {
    enum Side { case left, right }

    let product: Product
    let status: Product.SafetyStatus
    let details: Product.AlertDetails
    let side: Side
    var showCrown: Bool = false

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var rotationX: Double = -10
    @State private var rotationY: Double = 0
    @State private var dragOffset: CGSize = .zero
    @State private var pinchScale: CGFloat = 1.0
    @State private var lastPinchScale: CGFloat = 1.0
    @State private var glowPulse: Bool = false
    @State private var currentFace: Face = .front
    @State private var flipAngle: Double = 0

    enum Face { case front, details, nutrition }

    private var accentColor: Color {
        switch status {
        case .safe:    return Color(hex: compareNutriscoreHex(product.nutriscore))
        case .warning: return Color(hex: "FECB02")
        case .danger:  return Color(hex: "E63312")
        }
    }

    var body: some View {
        GeometryReader { geo in
            let cardW: CGFloat = min(geo.size.width * 0.46, 195)
            let cardH: CGFloat = cardW * 1.3
            let xPos: CGFloat = side == .left
                ? geo.size.width * 0.25
                : geo.size.width * 0.75
            let yPos: CGFloat = geo.size.height * 0.42

            ZStack {
                Ellipse()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: cardW * 0.85, height: 16)
                    .blur(radius: 10)
                    .scaleEffect(scale * pinchScale)
                    .offset(
                        x: xPos - geo.size.width / 2,
                        y: yPos - geo.size.height / 2 + cardH * 0.52 * scale * pinchScale
                    )

                card(width: cardW, height: cardH)
                    .rotation3DEffect(
                        .degrees(rotationX + dragOffset.height * 0.25),
                        axis: (x: 1, y: 0, z: 0), perspective: 0.5
                    )
                    .rotation3DEffect(
                        .degrees(rotationY + dragOffset.width * 0.35),
                        axis: (x: 0, y: 1, z: 0), perspective: 0.5
                    )
                    .scaleEffect(scale * pinchScale)
                    .shadow(color: accentColor.opacity(0.35), radius: 20, y: 8)
                    .opacity(opacity)
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = $0.translation }
                            .onEnded { v in
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    rotationY += v.translation.width * 0.35
                                    rotationX = max(-35, min(35, rotationX + v.translation.height * 0.25))
                                    dragOffset = .zero
                                }
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastPinchScale
                                lastPinchScale = value
                                pinchScale = max(0.4, min(2.0, pinchScale * delta))
                            }
                            .onEnded { _ in lastPinchScale = 1.0 }
                    )
            }
            .position(x: xPos, y: yPos)
        }
        .onAppear { animateIn() }
    }


    @ViewBuilder
    private func card(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(
                            colors: [accentColor.opacity(0.20), Color.black.opacity(0.40)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accentColor.opacity(0.85), accentColor.opacity(0.18)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ), lineWidth: 1.5
                        )
                )

            ARGridLines(accentColor: accentColor).clipShape(RoundedRectangle(cornerRadius: 18))
            ARCornerDecorations(accentColor: accentColor)

            Group {
                switch currentFace {
                case .front:     frontFace
                case .details:   detailsFace
                case .nutrition: nutritionFace
                }
            }
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0))
            .padding(14)
        }
        .frame(width: width, height: height)
    }

    // MARK: faccia frontale
    private var frontFace: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(glowPulse ? 0.28 : 0.10))
                    .frame(width: 76, height: 76)
                    .blur(radius: glowPulse ? 16 : 6)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: glowPulse)

                Button(action: { status == .safe ? flipTo(.nutrition) : flipTo(.details) }) {
                    ZStack(alignment: .topTrailing) {
                        NutriScoreBadge(grade: product.nutriscore, size: 50)
                            .scaleEffect(glowPulse ? 1.04 : 1.0)
                            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: glowPulse)
                        if showCrown {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 16))
                                .offset(x: 10, y: -10)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Text(product.nome)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            statusLabel

            HStack(spacing: 3) {
                Image(systemName: "arrow.2.squarepath").font(.system(size: 8))
                Text(status == .safe ? "Tocca per i valori nutrizionali" : "Tocca per dettagli")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(accentColor.opacity(0.7))

            Spacer(minLength: 0)
        }
    }

    private var statusText: String {
        switch status {
        case .safe:    return "SICURO"
        case .warning: return "POSSIBILI TRACCE"
        case .danger:  return "ATTENZIONE"
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        Text(statusText)
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundStyle(accentColor)
            .tracking(1.2)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(accentColor.opacity(0.4), lineWidth: 1))
    }

    // MARK: faccia dettagli
    private var detailsFace: some View {
        VStack(spacing: 6) {
            Button(action: { flipTo(.front) }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left").font(.system(size: 9, weight: .bold))
                    Text("DETTAGLI")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                }
                .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)

            if !details.presentAllergens.isEmpty {
                miniSection(label: "CONTIENE", color: Color(hex: "E63312"),
                            items: details.presentAllergens.map(\.rawValue))
            }
            if !details.traceAllergens.isEmpty {
                miniSection(label: "TRACCE DI", color: Color(hex: "FECB02"),
                            items: details.traceAllergens.map(\.rawValue))
            }
            if !details.unsatisfiedDiets.isEmpty {
                miniSection(label: "NON ADATTO", color: Color(hex: "888888"),
                            items: details.unsatisfiedDiets.map(\.rawValue))
            }
            if details.isEmpty {
                Text("Nessun problema rilevato.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
    }

    private func miniSection(label: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(color).tracking(1)
            // Chip in righe da 2
            let rows = stride(from: 0, to: items.count, by: 2)
                .map { Array(items[$0..<min($0 + 2, items.count)]) }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { item in
                            Text(item)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(color.opacity(0.20), in: Capsule())
                                .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 0.8))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }


    // MARK: faccia valori nutrizionali (solo se .safe)

    private var nutritionFace: some View {
        VStack(spacing: 7) {
            Button(action: { flipTo(.front) }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left").font(.system(size: 9, weight: .bold))
                    Text("VALORI NUTRIZIONALI")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                }
                .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 2)

            let items: [(String, String?, String, Double)] = [
                ("bolt.fill",        product.nutritional_values.energia,  "Energia",   0.70),
                ("drop.fill",        product.nutritional_values.grassi,   "Grassi",    0.42),
                ("cube.fill",        product.nutritional_values.zuccheri, "Zuccheri",  0.50),
                ("waveform",         product.nutritional_values.sale,     "Sale",      0.30),
                ("figure.strengthtraining.traditional",
                                     product.nutritional_values.proteine, "Proteine",  0.60),
                ("leaf.fill",        product.nutritional_values.fibra,    "Fibre",     0.55),
            ]

            ForEach(items, id: \.2) { icon, value, label, frac in
                if let val = value {
                    ARNutritionBar(
                        icon: icon, value: val, label: label,
                        fraction: frac, accentColor: accentColor
                    )
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
            scale = 1.0; opacity = 1.0
        }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true).delay(0.4)) {
            glowPulse = true
        }
        rotationY = side == .left ? -8 : 8
    }

    private func flipTo(_ target: Face) {
        guard target != currentFace else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { flipAngle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            currentFace = target
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { flipAngle = 0 }
        }
    }

}
 
