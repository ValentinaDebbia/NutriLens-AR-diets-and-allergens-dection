import SwiftUI
import ARKit

struct ScannerView: View {
    @StateObject private var arManager  = ARRecognitionManager()
    @State private var selectedTab: Tab = .scanner

    enum Tab { case scanner, compare, profile }

    var body: some View {
        TabView(selection: $selectedTab) {
            SingleScanTab(arManager: arManager)
                .tabItem { Label("Scanner", systemImage: "barcode.viewfinder") }
                .tag(Tab.scanner)
            CompareView()
                .tabItem { Label("Confronta", systemImage: "rectangle.split.2x1.fill") }
                .tag(Tab.compare)
            profileTab
                .tabItem { Label("Profilo", systemImage: "person.circle") }
                .tag(Tab.profile)
        }
        .onAppear { arManager.startSession() }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .scanner { arManager.startSession() } else { arManager.pauseSession() }
        }
    }

    private var profileTab: some View {
        ProfileView()
    }
}


struct SingleScanTab: View {
    // MARK: schermata AR principale per la scansione singola
    @ObservedObject var arManager: ARRecognitionManager
    @State private var showNutriPanel: Bool = false
    @State private var showAlertPanel: Bool = false
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    
    @State private var lastPlayedStatus: Product.SafetyStatus? = nil

    var body: some View {
        ZStack {
            ARCameraView(arSession: arManager.arSession).ignoresSafeArea()

            if let status = arManager.safetyStatus {
                safetyOverlay(for: status)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: arManager.safetyStatus)

                // hint "tieni premuto" per tutti i casi (verde, rosso, giallo)
                if !showNutriPanel && !showAlertPanel {
                    longPressHint(for: status)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(duration: 0.45), value: showNutriPanel)
                        .animation(.spring(duration: 0.45), value: showAlertPanel)
                }
            }

            VStack(spacing: 0) {
                topGradient; Spacer()
                if arManager.isScanning { scanningOverlay }
                Spacer()
            }

            if let err = arManager.sessionError { errorBanner(err) }

            // overlay AR verde: NutriScore
            if showNutriPanel, let product = arManager.detectedProduct {
                ARNutriScore3DOverlay(product: product) {
                    withAnimation(.spring(duration: 0.4)) { showNutriPanel = false }
                }
                .zIndex(10)
            }

            // overlay AR rosso/giallo: allerta con dettagli
            if showAlertPanel, let product = arManager.detectedProduct,
               let status = arManager.safetyStatus, status != .safe {
                ARAlertOverlay(
                    product: product,
                    status: status,
                    details: arManager.alertDetails ?? Product.AlertDetails()
                ) {
                    withAnimation(.spring(duration: 0.4)) { showAlertPanel = false }
                }
                .zIndex(10)
            }
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                guard arManager.detectedProduct != nil else { return }
                haptic.impactOccurred()
                withAnimation(.spring(duration: 0.45)) {
                    if arManager.safetyStatus == .safe {
                        showNutriPanel = true
                    } else {
                        showAlertPanel = true
                    }
                }
            }
        )
        .onChange(of: arManager.detectedProduct) { _, newVal in
            if newVal == nil {
                withAnimation { showNutriPanel = false; showAlertPanel = false }
            }
        }
        .onChange(of: arManager.safetyStatus) { _, newStatus in
            withAnimation { showNutriPanel = false; showAlertPanel = false }
            if let status = newStatus, let product = arManager.detectedProduct {
                let details = arManager.alertDetails ?? Product.AlertDetails()
                let entry = ScanHistoryEntry(
                    product: product,
                    status: status,
                    details: details,
                    source: .scanner
                )
                ScanHistoryManager.shared.add(entry)

                // suona solo se lo stato è diverso dall'ultimo riprodotto
                if status != lastPlayedStatus {
                    lastPlayedStatus = status
                    ScanSoundManager.shared.play(for: status)
                }
            } else if newStatus == nil {
                // reset quando il prodotto sparisce
                lastPlayedStatus = nil
            }
        }
    }

    @ViewBuilder
    private func safetyOverlay(for status: Product.SafetyStatus) -> some View {
        let color: Color = {
            switch status {
            case .danger:  return Color(red: 1.0, green: 0.35, blue: 0.35)
            case .warning: return Color(red: 1.0, green: 0.88, blue: 0.20)
            case .safe:    return Color(red: 0.30, green: 0.85, blue: 0.45)
            }
        }()
        color.opacity(0.55)
    }

    private func longPressHint(for status: Product.SafetyStatus) -> some View {
        let message: String
       message = "Tieni premuto per dettagli"
        return VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill").font(.footnote)
                Text(message).font(.footnote.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 110)
        }
    }

    private var topGradient: some View {
        LinearGradient(colors: [Color.black.opacity(0.55), Color.clear], startPoint: .top, endPoint: .bottom)
            .frame(height: 120).ignoresSafeArea(edges: .top)
            .overlay(alignment: .topLeading) {
                Text("NutriLens").font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.top, 58)
            }
    }

    private var scanningOverlay: some View {
        VStack(spacing: 16) {
            ViewfinderFrame(size: UIScreen.main.bounds.width * 0.82, cornerLength: 36, lineWidth: 3)
            Text("Inquadra un prodotto").font(.callout.weight(.medium)).foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message).font(.footnote).padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 100)
        }
    }
}

// MARK: AR 3D NutriScore overlay
struct ARNutriScore3DOverlay: View {
    let product: Product
    let onDismiss: () -> Void

    @State private var rotationX: Double = -12
    @State private var rotationY: Double = 8
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 0.5
    @State private var pinchScale: CGFloat = 1.0
    @State private var lastPinchScale: CGFloat = 1.0
    @State private var opacity: Double = 0
    @State private var currentFace: ARFace = .front
    @State private var flipAngle: Double = 0
    @State private var particlesVisible: Bool = false
    @State private var glowPulse: Bool = false

    enum ARFace: CaseIterable {
        case front, nutrition
        var label: String {
            switch self { case .front: return "Nutri-Score"; case .nutrition: return "Valori"}
        }
        var icon: String {
            switch self { case .front: return "star.fill"; case .nutrition: return "chart.bar.fill" }
        }
    }

    private let accentColor: Color
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    init(product: Product, onDismiss: @escaping () -> Void) {
        self.product = product; self.onDismiss = onDismiss
        self.accentColor = Color(hex: nutriscoreHex(product.nutriscore))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { dismiss() }
            ARParticleField(color: accentColor, isVisible: particlesVisible).ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Ellipse()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 260, height: 28)
                        .blur(radius: 16)
                        .offset(y: 178)
                        .scaleEffect(x: scale * pinchScale * 0.88, y: scale * pinchScale * 0.88)

                    ARCard3D(
                        product: product, currentFace: currentFace,
                        accentColor: accentColor, flipAngle: flipAngle,
                        onLetterTap: {
                            haptic.impactOccurred()
                            let next: ARFace = currentFace == .front ? .nutrition : .front
                            flipToFace(next)
                        }
                    )
                    .frame(width: 300, height: 340)
                    .rotation3DEffect(
                        .degrees(rotationX + dragOffset.height * 0.3),
                        axis: (x: 1, y: 0, z: 0), perspective: 0.45
                    )
                    .rotation3DEffect(
                        .degrees(rotationY + dragOffset.width * 0.4),
                        axis: (x: 0, y: 1, z: 0), perspective: 0.45
                    )
                    .scaleEffect(scale * pinchScale)
                    .shadow(color: accentColor.opacity(0.3), radius: 30, y: 14)
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = $0.translation }
                            .onEnded { v in
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    rotationY += v.translation.width * 0.4
                                    rotationX = max(-38, min(38, rotationX + v.translation.height * 0.3))
                                    dragOffset = .zero
                                }
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastPinchScale
                                lastPinchScale = value
                                pinchScale = max(0.4, min(2.2, pinchScale * delta))
                            }
                            .onEnded { _ in
                                lastPinchScale = 1.0
                            }
                    )
                }
                .opacity(opacity)
            }
        }
        .onAppear { animateIn() }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
            scale = 1.0; opacity = 1.0
        }
        withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true).delay(0.4)) {
            glowPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { particlesVisible = true }
    }

    private func flipToFace(_ face: ARFace) {
        guard face != currentFace else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { flipAngle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            currentFace = face
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { flipAngle = 0 }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { scale = 0.55; opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) { onDismiss() }
    }
}


// MARK: AR Card 3D

struct ARCard3D: View {
    let product: Product
    let currentFace: ARNutriScore3DOverlay.ARFace
    let accentColor: Color
    let flipAngle: Double
    let onLetterTap: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(colors: [accentColor.opacity(0.18), Color.black.opacity(0.4)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(LinearGradient(colors: [accentColor.opacity(0.85), accentColor.opacity(0.18)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                )

            ARGridLines(accentColor: accentColor).clipShape(RoundedRectangle(cornerRadius: 24))
            ARCornerDecorations(accentColor: accentColor)

            Group {
                switch currentFace {
                case .front:
                    ARFaceFront(product: product, accentColor: accentColor, onLetterTap: onLetterTap)
                case .nutrition:
                    ARFaceNutrition(values: product.nutritional_values, accentColor: accentColor, onLetterTap: onLetterTap)
                }
            }
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0))
            .padding(22)
        }
    }
}

// faccia principale
struct ARFaceFront: View {
    let product: Product
    let accentColor: Color
    let onLetterTap: () -> Void
    @State private var ringProgress: Double = 0
    @State private var badgePulse: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(accentColor.opacity(0.15)).frame(width: 130, height: 130).blur(radius: 22)
                Circle().trim(from: 0, to: ringProgress)
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 110, height: 110).rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.3).delay(0.3), value: ringProgress)
                Button(action: onLetterTap) {
                    RoundedRectangle(cornerRadius: 22).fill(accentColor).frame(width: 80, height: 80)
                        .shadow(color: accentColor.opacity(0.65), radius: badgePulse ? 28 : 20, y: 5)
                        .overlay(
                            Text(product.nutriscore.uppercased())
                                .font(.system(size: 44, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        )
                        .scaleEffect(badgePulse ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: badgePulse)
                }
                .buttonStyle(.plain)
            }

            Text(product.nome)
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)

            HStack(spacing: 8) {
                ForEach(["A","B","C","D","E"], id: \.self) { letter in
                    let isActive = letter == product.nutriscore.uppercased()
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: nutriscoreHex(letter)).opacity(isActive ? 1.0 : 0.28))
                            .frame(width: isActive ? 42 : 30, height: isActive ? 42 : 30)
                            .shadow(color: Color(hex: nutriscoreHex(letter)).opacity(isActive ? 0.55 : 0), radius: 9)
                        Text(letter).font(.system(size: isActive ? 19 : 13, weight: .black, design: .rounded)).foregroundStyle(.white)
                    }
                    .animation(.spring(duration: 0.35), value: isActive)
                }
            }

            // hint visivo
            HStack(spacing: 4) {
                Image(systemName: "arrow.2.squarepath").font(.system(size: 9))
                Text("Tocca la lettera per sapere i valori nutrizionali").font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(accentColor.opacity(0.7))
        }
        .onAppear {
            let grades = ["A": 1.0, "B": 0.8, "C": 0.6, "D": 0.4, "E": 0.2]
            ringProgress = grades[product.nutriscore.uppercased()] ?? 0.5
            badgePulse = true
        }
    }
}

// faccia valori nutrizionali
struct ARFaceNutrition: View {
    let values: Product.NutritionalValues
    let accentColor: Color
    let onLetterTap: () -> Void

    private var items: [(String, String?, String, Double)] {[
        ("bolt.fill",        values.energia,  "Energia",  0.70),
        ("drop.fill",        values.grassi,   "Grassi",   0.42),
        ("cube.fill",        values.zuccheri, "Zuccheri", 0.50),
        ("waveform",         values.sale,     "Sale",     0.30),
        ("figure.strengthtraining.traditional", values.proteine, "Proteine", 0.60),
        ("leaf.fill",        values.fibra,    "Fibre",    0.55),
    ]}

    var body: some View {
        VStack(spacing: 9) {
            // Pulsante torna al NutriScore (tap sulla lettera)
            Button(action: onLetterTap) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left").font(.system(size: 10, weight: .bold))
                    Text("VALORI NUTRIZIONALI")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)

            ForEach(items, id: \.2) { icon, value, label, frac in
                if let val = value {
                    ARNutritionBar(icon: icon, value: val, label: label, fraction: frac, accentColor: accentColor)
                }
            }
        }
    }
}

struct ARNutritionBar: View {
    let icon: String; let value: String; let label: String; let fraction: Double; let accentColor: Color
    @State private var filled = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(accentColor).frame(width: 16)
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).frame(width: 62, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [accentColor.opacity(0.8), accentColor], startPoint: .leading, endPoint: .trailing))
                        .frame(width: filled ? geo.size.width * fraction : 0)
                        .animation(.easeOut(duration: 0.85).delay(Double.random(in: 0...0.35)), value: filled)
                }
            }.frame(height: 6)
            Text(value).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                .frame(width: 44, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.6)
        }
        .onAppear { filled = true }
    }
}

struct ARFaceSelector: View {
    @Binding var currentFace: ARNutriScore3DOverlay.ARFace
    let accentColor: Color
    let onSelect: (ARNutriScore3DOverlay.ARFace) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ARNutriScore3DOverlay.ARFace.allCases, id: \.self) { face in
                let isSelected = face == currentFace
                Button { onSelect(face) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: face.icon).font(.system(size: 14))
                        Text(face.label).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(isSelected ? accentColor.opacity(0.8) : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? accentColor : Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .animation(.spring(duration: 0.3), value: isSelected)
            }
        }
        .padding(6).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ARGridLines: View {
    let accentColor: Color
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 30
            let c = GraphicsContext.Shading.color(accentColor.opacity(0.065))
            var y: CGFloat = 0
            while y < size.height { var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); ctx.stroke(p, with: c, lineWidth: 0.5); y += spacing }
            var x: CGFloat = 0
            while x < size.width { var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); ctx.stroke(p, with: c, lineWidth: 0.5); x += spacing }
        }
    }
}

struct ARCornerDecorations: View {
    let accentColor: Color
    let len: CGFloat = 18; let lw: CGFloat = 2
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height
            Canvas { ctx, _ in
                let c = GraphicsContext.Shading.color(accentColor.opacity(0.8))
                let corners: [(CGPoint, CGPoint, CGPoint)] = [
                    (CGPoint(x: 12, y: 12+len), CGPoint(x: 12, y: 12), CGPoint(x: 12+len, y: 12)),
                    (CGPoint(x: w-12-len, y: 12), CGPoint(x: w-12, y: 12), CGPoint(x: w-12, y: 12+len)),
                    (CGPoint(x: 12, y: h-12-len), CGPoint(x: 12, y: h-12), CGPoint(x: 12+len, y: h-12)),
                    (CGPoint(x: w-12-len, y: h-12), CGPoint(x: w-12, y: h-12), CGPoint(x: w-12, y: h-12-len)),
                ]
                for (a, mid, b) in corners { var p = Path(); p.move(to: a); p.addLine(to: mid); p.addLine(to: b); ctx.stroke(p, with: c, style: StrokeStyle(lineWidth: lw, lineCap: .round)) }
            }
        }
    }
}

struct ARParticleField: View {
    let color: Color; let isVisible: Bool
    private let particles: [(CGFloat, CGFloat, CGFloat, Double, Double)] =
        (0..<22).map { _ in (CGFloat.random(in: 0.05...0.95), CGFloat.random(in: 0.05...0.95),
                             CGFloat.random(in: 2...5), Double.random(in: 2.5...5.0), Double.random(in: 0...2.5)) }
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<particles.count, id: \.self) { i in
                let p = particles[i]
                ARParticle(color: color, size: p.2, speed: p.3, delay: p.4, isVisible: isVisible)
                    .position(x: geo.size.width * p.0, y: geo.size.height * p.1)
            }
        }
    }
}

struct ARParticle: View {
    let color: Color; let size: CGFloat; let speed: Double; let delay: Double; let isVisible: Bool
    @State private var offset: CGFloat = 0; @State private var opacity: Double = 0
    var body: some View {
        Circle().fill(color.opacity(0.55)).frame(width: size, height: size).blur(radius: size * 0.4)
            .offset(y: offset).opacity(opacity)
            .onAppear {
                guard isVisible else { return }
                withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true).delay(delay)) {
                    offset = CGFloat.random(in: -22...22); opacity = Double.random(in: 0.3...0.8)
                }
            }
    }
}

struct ViewfinderFrame: View {
    var size: CGFloat; var cornerLength: CGFloat = 28; var lineWidth: CGFloat = 3
    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height, cl = cornerLength
            let corners: [Path] = [
                Path { p in p.move(to: .init(x: 0, y: cl)); p.addLine(to: .zero); p.addLine(to: .init(x: cl, y: 0)) },
                Path { p in p.move(to: .init(x: w-cl, y: 0)); p.addLine(to: .init(x: w, y: 0)); p.addLine(to: .init(x: w, y: cl)) },
                Path { p in p.move(to: .init(x: 0, y: h-cl)); p.addLine(to: .init(x: 0, y: h)); p.addLine(to: .init(x: cl, y: h)) },
                Path { p in p.move(to: .init(x: w-cl, y: h)); p.addLine(to: .init(x: w, y: h)); p.addLine(to: .init(x: w, y: h-cl)) },
            ]
            for path in corners { ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)) }
        }
        .frame(width: size, height: size)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: NutriScore badge

struct NutriScoreBadge: View {
    let grade: String; var size: CGFloat = 56
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.21).fill(Color(hex: nutriscoreHex(grade))).frame(width: size, height: size)
            Text(grade.uppercased()).font(.system(size: size * 0.5, weight: .black, design: .rounded)).foregroundStyle(.white)
        }
    }
}

// NutriScore Scale
struct NutriScoreScale: View {
    let grade: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(["A","B","C","D","E"], id: \.self) { letter in
                let isActive = letter == grade.uppercased()
                Text(letter).font(.system(size: 11, weight: isActive ? .black : .regular))
                    .foregroundStyle(isActive ? .white : .secondary)
                    .frame(width: 20, height: 20)
                    .background(isActive ? Color(hex: nutriscoreHex(letter)) : Color.secondary.opacity(0.15), in: Circle())
            }
        }
    }
}

private func nutriscoreHex(_ grade: String) -> String {
    switch grade.uppercased() {
    case "A": return "038141"; case "B": return "85BB2F"; case "C": return "FECB02"
    case "D": return "EE8100"; case "E": return "E63312"; default: return "AAAAAA"
    }
}

// MARK: AR Alert Overlay (rosso / giallo)

// variante dell'overlay AR mostrata automaticamente quando il prodotto
// non è sicuro per l'utente (.danger = rosso, .warning = giallo).
struct ARAlertOverlay: View {
    let product: Product
    let status: Product.SafetyStatus
    let details: Product.AlertDetails
    let onDismiss: () -> Void

    @State private var rotationX: Double = -12
    @State private var rotationY: Double = 8
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 0.5
    @State private var pinchScale: CGFloat = 1.0
    @State private var lastPinchScale: CGFloat = 1.0
    @State private var opacity: Double = 0
    @State private var particlesVisible: Bool = false
    @State private var glowPulse: Bool = false
    @State private var shakeOffset: CGFloat = 0
    @State private var currentFace: ARAlertFace = .alert
    @State private var flipAngle: Double = 0

    enum ARAlertFace { case alert, details }

    private var accentColor: Color {
        status == .danger
            ? Color(hex: "E63312")
            : Color(hex: "FECB02")
    }

    private var alertIcon: String {
        status == .danger ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
    }

    private var alertTitle: String {
        status == .danger ? "ATTENZIONE" : "POSSIBILI TRACCE"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { dismiss() }
            ARParticleField(color: accentColor, isVisible: particlesVisible).ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    // Ombra proiettata
                    Ellipse()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 260, height: 28)
                        .blur(radius: 16)
                        .offset(y: 178)
                        .scaleEffect(x: scale * pinchScale * 0.88, y: scale * pinchScale * 0.88)

                    ARAlertCard(
                        product: product,
                        accentColor: accentColor,
                        alertIcon: alertIcon,
                        alertTitle: alertTitle,
                        details: details,
                        currentFace: currentFace,
                        flipAngle: flipAngle,
                        glowPulse: glowPulse,
                        onIconTap: { flipToDetails() },
                        onDismiss: dismiss
                    )
                    .frame(width: 300, height: 340)
                    .rotation3DEffect(
                        .degrees(rotationX + dragOffset.height * 0.3),
                        axis: (x: 1, y: 0, z: 0), perspective: 0.45
                    )
                    .rotation3DEffect(
                        .degrees(rotationY + dragOffset.width * 0.4),
                        axis: (x: 0, y: 1, z: 0), perspective: 0.45
                    )
                    .scaleEffect(scale * pinchScale)
                    .offset(x: shakeOffset)
                    .shadow(color: accentColor.opacity(0.45), radius: 30, y: 14)
                    .gesture(
                        DragGesture()
                            .onChanged { dragOffset = $0.translation }
                            .onEnded { v in
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    rotationY += v.translation.width * 0.4
                                    rotationX = max(-38, min(38, rotationX + v.translation.height * 0.3))
                                    dragOffset = .zero
                                }
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastPinchScale
                                lastPinchScale = value
                                pinchScale = max(0.4, min(2.2, pinchScale * delta))
                            }
                            .onEnded { _ in lastPinchScale = 1.0 }
                    )
                }
                .opacity(opacity)
            }
        }
        .onAppear { animateIn() }
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
            scale = 1.0; opacity = 1.0
        }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(0.4)) {
            glowPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { particlesVisible = true }
        // shake di allerta all'entrata
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ì
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 8)) { shakeOffset = 12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.interpolatingSpring(stiffness: 600, damping: 8)) { shakeOffset = -10 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) { shakeOffset = 6 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.spring()) { shakeOffset = 0 }
                    }
                }
            }
        }
    }

    private func flipToDetails() {
        let next: ARAlertFace = currentFace == .alert ? .details : .alert
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { flipAngle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            currentFace = next
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { flipAngle = 0 }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { scale = 0.55; opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) { onDismiss() }
    }
}

// MARK: AR Alert Card

struct ARAlertCard: View {
    let product: Product
    let accentColor: Color
    let alertIcon: String
    let alertTitle: String
    let details: Product.AlertDetails
    let currentFace: ARAlertOverlay.ARAlertFace
    let flipAngle: Double
    let glowPulse: Bool
    let onIconTap: () -> Void
    let onDismiss: () -> Void

    @State private var ringProgress: Double = 0
    @State private var badgePulse: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(
                            colors: [accentColor.opacity(0.22), Color.black.opacity(0.45)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accentColor.opacity(0.9), accentColor.opacity(0.2)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ), lineWidth: 1.5
                        )
                )

            ARGridLines(accentColor: accentColor).clipShape(RoundedRectangle(cornerRadius: 24))
            ARCornerDecorations(accentColor: accentColor)

            // contenuto — switcha tra le due facce (con flip)
            Group {
                switch currentFace {
                case .alert:
                    alertFace
                case .details:
                    detailsFace
                }
            }
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0))
            .padding(22)
        }
        .onAppear {
            ringProgress = 1.0
            badgePulse = true
        }
    }

    // faccia principale (icona + titolo + hint)

    private var alertFace: some View {
        VStack(spacing: 14) {
            // Icona pulsante
            ZStack {
                Circle()
                    .fill(accentColor.opacity(glowPulse ? 0.30 : 0.12))
                    .frame(width: 100, height: 100)
                    .blur(radius: glowPulse ? 18 : 8)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: glowPulse)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.2).delay(0.3), value: ringProgress)

                Button(action: onIconTap) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(accentColor)
                            .frame(width: 64, height: 64)
                            .shadow(color: accentColor.opacity(badgePulse ? 0.75 : 0.4), radius: badgePulse ? 22 : 14, y: 4)
                            .scaleEffect(badgePulse ? 1.06 : 1.0)
                            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: badgePulse)
                        Image(systemName: alertIcon)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }

            // nome prodotto
            Text(product.nome)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            // badge allerta
            Text(alertTitle)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(accentColor)
                .tracking(1.5)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accentColor.opacity(0.4), lineWidth: 1))

            // hint tocco
            HStack(spacing: 4) {
                Image(systemName: "arrow.2.squarepath").font(.system(size: 9))
                Text("Tocca il simbolo per vedere i dettagli").font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(accentColor.opacity(0.7))
        }
    }

    // faccia dettagli (allergeni / tracce / diete)

    private var detailsFace: some View {
        VStack(spacing: 9) {
            // pulsante torna (come ARFaceNutrition)
            Button(action: onIconTap) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left").font(.system(size: 10, weight: .bold))
                    Text("DETTAGLI")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)

            if !details.presentAllergens.isEmpty {
                AlertDetailSection(
                    label: "CONTIENE",
                    color: Color(hex: "E63312"),
                    items: details.presentAllergens.map { "\($0.rawValue)" }
                )
            }
            if !details.traceAllergens.isEmpty {
                AlertDetailSection(
                    label: "TRACCE DI",
                    color: Color(hex: "FECB02"),
                    items: details.traceAllergens.map { "\($0.rawValue)" }
                )
            }
            if !details.unsatisfiedDiets.isEmpty {
                AlertDetailSection(
                    label: "NON ADATTO A DIETE",
                    color: Color(hex: "888888"),
                    items: details.unsatisfiedDiets.map { "\($0.rawValue)" }
                )
            }
            if details.isEmpty {
                Text("Nessun dettaglio disponibile.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: Alert Detail Section

// riga con etichetta di categoria + chip degli elementi problematici.
struct AlertDetailSection: View {
    let label: String
    let color: Color
    let items: [String]

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(color)
                .tracking(1.2)

            WrappingHStack(items: items) { item in
                Text(item)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(color.opacity(0.22), in: Capsule())
                    .overlay(Capsule().strokeBorder(color.opacity(0.55), lineWidth: 1))
                    .scaleEffect(appeared ? 1 : 0.75)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            withAnimation(.spring(duration: 0.4).delay(0.1)) { appeared = true }
        }
    }
}

struct WrappingHStack<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content
    @State private var totalHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            self.buildRows(maxWidth: geo.size.width)
        }
        .frame(height: totalHeight)
    }

    private func buildRows(maxWidth: CGFloat) -> some View {
        var rows: [[Item]] = [[]]
        var rowWidths: [CGFloat] = [0]
        let spacing: CGFloat = 5
        let estimatedItemWidth: CGFloat = 90

        for item in items {
            let w = estimatedItemWidth
            if rowWidths[rows.count - 1] + w + spacing > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([item])
                rowWidths.append(w)
            } else {
                rows[rows.count - 1].append(item)
                rowWidths[rows.count - 1] += w + spacing
            }
        }

        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: spacing) {
                    ForEach(rows[i], id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
        .background(GeometryReader { geo in
            Color.clear.onAppear { totalHeight = geo.size.height }
        })
    }
}

// MARK: Sound Manager

import AVFoundation

final class ScanSoundManager {
    static let shared = ScanSoundManager()
    private var player: AVAudioPlayer?

    func play(for status: Product.SafetyStatus) {
        let fileName: String
        switch status {
        case .danger:  fileName = "wrong_sound"
        case .warning: fileName = "medium_sound"
        case .safe:    fileName = "good_sound"
        }
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()

        // Vibrazione in base allo stato
        switch status {
        case .danger:
            // vibrazione pesante + doppio colpo per allerta
            let heavy = UIImpactFeedbackGenerator(style: .heavy)
            heavy.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                heavy.impactOccurred()
            }
        case .warning:
            // vibrazione media singola
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .safe:
            // notifica di successo
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

#Preview { ScannerView() }
