import SwiftUI
import AVFoundation

// MARK: animation
enum BookConst {
    static let flipDuration: Double   = 0.68
    static let swipeThreshold: CGFloat = 45
}

struct BackfaceCullingModifier: AnimatableModifier {
    var degrees: Double
    var isFront: Bool
    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }
    func body(content: Content) -> some View {
        let isFacingViewer = cos(degrees * .pi / 180) > 0
        content.opacity(isFront ? (isFacingViewer ? 1 : 0) : (isFacingViewer ? 0 : 1))
    }
}
extension View {
    func culled(degrees: Double, isFront: Bool) -> some View {
        self.modifier(BackfaceCullingModifier(degrees: degrees, isFront: isFront))
    }
}

// MARK: AR History Book View
// schermata principale del registro storico in Realtà Aumentata
struct ARHistoryBookView: View {

    @Environment(\.dismiss)    private var dismiss
    @StateObject private var historyManager = ScanHistoryManager.shared
    @StateObject private var cameraSession  = CameraSessionManager()

    // stato libro
    @State private var isOpen         = false
    @State private var currentPage    = 0
    @State private var isFlipping     = false
    @State private var appeared       = false
    @State private var cameraAuthorized = false

    // dettaglio
    @State private var showDetail    = false
    @State private var selectedEntry: ScanHistoryEntry? = nil

    @State private var sceneCoordinator: RealBookSceneView.Coordinator?

    // filtra la cronologia per mostrare solo un prodotto per pagina (niente duplicati)
    private var entries: [ScanHistoryEntry] {
        var seen = Set<String>()
        return historyManager.entries.filter { seen.insert($0.productID).inserted }
    }
    private var totalPages: Int { max(1, entries.count) }

    var body: some View {
        ZStack {
            if cameraAuthorized {
                CameraPreviewView(session: cameraSession.session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            ARGridOverlay().opacity(0.18).ignoresSafeArea()
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.82)],
                center: .center, startRadius: 100, endRadius: 480
            ).ignoresSafeArea()

            // libro 3D
            RealBookSceneView(
                entries: entries,
                isOpen: $isOpen,
                currentPage: $currentPage,
                isFlipping: $isFlipping,
                onCoordinatorReady: { coordinator in
                    DispatchQueue.main.async { sceneCoordinator = coordinator }
                },
                onTapLeft:  { flipPage(forward: false) },
                onTapRight: { flipPage(forward: true) },
                onTapEntry: {
                    guard isOpen, currentPage < entries.count else { return }
                    selectedEntry = entries[currentPage]
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                        showDetail = true
                    }
                }
            )
            .ignoresSafeArea()

            // header
            VStack(spacing: 0) {
                header
                    .padding(.top, 100)
                    .padding(.bottom, 24)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.04), value: appeared)
                Spacer()
            }

            // tasto chiudi
            VStack {
                HStack { Spacer(); closeButton }
                    .padding(.top, 54).padding(.trailing, 18)
                Spacer()
            }

            // bottom bar
            VStack {
                Spacer()
                bottomBar
                    .padding(.bottom, 36)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.1), value: appeared)
            }

            // overlay dettaglio
            if showDetail, let e = selectedEntry {
                StickerDetailOverlay(entry: e) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { showDetail = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) { selectedEntry = nil }
                }
                .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.88)))
                .zIndex(10)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            checkCamera()
            withAnimation(.spring(response: 0.72, dampingFraction: 0.68).delay(0.12)) {
                appeared = true
            }
        }
        .onDisappear { cameraSession.stop() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.20)).frame(width: 34, height: 34).blur(radius: 5)
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.63, green: 1.0, blue: 0.78))
                        .shadow(color: Color(red: 0.63, green: 1.0, blue: 0.78).opacity(0.8), radius: 8, y: 0)
                }
                Text("Registro NutriLens")
                    .font(.custom("Georgia", size: 20)).bold()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
            }
        }
        .scaleEffect(appeared ? 1 : 0.85)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(entries.isEmpty ? "Album vuoto" : "\(currentPage + 1) di \(totalPages)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.black.opacity(0.48), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .opacity(isOpen ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: isOpen)

            if isOpen && totalPages > 1 {
                dotsIndicator
            }

            Text(isOpen
                 ? "Tap sinistra/destra per sfogliare."
                 : "Tocca il libro per aprirlo")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.26))
                .animation(.easeInOut(duration: 0.3), value: isOpen)
        }
    }

    private var dotsIndicator: some View {
        let maxDots  = min(totalPages, 12)
        let activeDot = min(currentPage, maxDots - 1)
        return HStack(spacing: 4) {
            ForEach(0..<maxDots, id: \.self) { i in
                Circle()
                    .fill(i == activeDot ? Color.white : Color.white.opacity(0.22))
                    .frame(width: i == activeDot ? 6 : 4,
                           height: i == activeDot ? 6 : 4)
                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: currentPage)
                    .onTapGesture { jumpToPage(i) }
            }
        }
    }
    
    // MARK: navigazione - interazione libro
    private var canGoPrev: Bool { isOpen && currentPage > 0 }
    private var canGoNext: Bool { isOpen && currentPage < totalPages - 1 }

    private func flipPage(forward: Bool) {
        guard !isFlipping, let coordinator = sceneCoordinator else { return }
        guard forward ? canGoNext : canGoPrev else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isFlipping = true
        coordinator.animateFlip(forward: forward, entries: entries, currentPage: currentPage) { newPage in
            currentPage = newPage
            isFlipping  = false
        }
    }

    private func jumpToPage(_ index: Int) {
        guard !isFlipping, isOpen, index != currentPage, let coordinator = sceneCoordinator else { return }
        let forward = index > currentPage
        isFlipping = true
        coordinator.animateFlip(forward: forward, entries: entries, currentPage: currentPage) { newPage in
            currentPage = newPage
            isFlipping  = false
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.52), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
    }

    private func checkCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true; cameraSession.configure(); cameraSession.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.cameraAuthorized = granted
                    if granted { self.cameraSession.configure(); self.cameraSession.start() }
                }
            }
        default: break
        }
    }
}

// MARK: elementi decorativi
struct ARGridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let s: CGFloat = 40
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width  { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)); x += s }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)); y += s }
            context.stroke(path, with: .color(.green), lineWidth: 0.4)
        }
    }
}

// linee decorative per card e overlay
struct ARBookGridLines: View {
    let accentColor: Color
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 32
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)); x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)); y += step
            }
            context.stroke(path, with: .color(accentColor), lineWidth: 0.3)
        }
    }
}


struct ARBookCornerDecorations: View {
    let accentColor: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height
            let len: CGFloat = 16; let lw: CGFloat = 1.5
            ZStack {
                Path { p in p.move(to: CGPoint(x: 0, y: len)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: len, y: 0)) }.stroke(accentColor, lineWidth: lw)
                Path { p in p.move(to: CGPoint(x: w - len, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: len)) }.stroke(accentColor, lineWidth: lw)
                Path { p in p.move(to: CGPoint(x: 0, y: h - len)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: len, y: h)) }.stroke(accentColor, lineWidth: lw)
                Path { p in p.move(to: CGPoint(x: w - len, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - len)) }.stroke(accentColor, lineWidth: lw)
            }
        }
    }
}

// particelle animate: effetto “magia” quando apri il dettaglio
struct ARBookParticleField: View {
    let color: Color
    let isVisible: Bool
    @State private var particles: [(CGFloat, CGFloat, CGFloat, Double)] = (0..<28).map { _ in
        (CGFloat.random(in: 0...1), CGFloat.random(in: 0...1),
         CGFloat.random(in: 2...5), Double.random(in: 0.3...1.0))
    }
    @State private var animate = false
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<particles.count, id: \.self) { i in
                    let p = particles[i]
                    Circle()
                        .fill(color.opacity(animate ? 0 : p.3 * 0.6))
                        .frame(width: p.2, height: p.2)
                        .position(x: p.0 * geo.size.width,
                                  y: animate ? p.1 * geo.size.height - 80 : p.1 * geo.size.height)
                        .animation(.easeOut(duration: Double.random(in: 1.2...2.4))
                            .delay(Double.random(in: 0...0.8))
                            .repeatForever(autoreverses: false), value: animate)
                }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .onAppear { animate = true }
    }
}

// sezione per mostrare allergeni, tracce e/o diete non rispettate
struct AlertBookDetailSection: View {
    let label: String
    let color: Color
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.28), lineWidth: 1))
    }
}

// sticker detail overlay
struct StickerDetailOverlay: View {
    let entry:     ScanHistoryEntry
    let onDismiss: () -> Void

    @State private var rotationX:     Double  = -12
    @State private var rotationY:     Double  = 8
    @State private var dragOffset:    CGSize  = .zero
    @State private var scale:         CGFloat = 0.5
    @State private var pinchScale:    CGFloat = 1.0
    @State private var lastPinch:     CGFloat = 1.0
    @State private var opacity:       Double  = 0
    @State private var particlesVisible: Bool = false
    @State private var glowPulse:     Bool    = false
    @State private var shakeOffset:   CGFloat = 0
    @State private var currentFace:   CardFace = .front
    @State private var flipAngle:     Double  = 0

    enum CardFace { case front, back }

    private var accentColor: Color {
        switch entry.safetyStatus {
        case .safe:    return Color(hex: "038141")
        case .warning: return Color(hex: "FECB02")
        case .danger:  return Color(hex: "E63312")
        }
    }

    private var alertIcon: String {
        switch entry.safetyStatus {
        case .safe:    return "checkmark.seal.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .danger:  return "exclamationmark.triangle.fill"
        }
    }

    private var alertTitle: String {
        entry.safetyStatus.label.uppercased()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { dismissCard() }
            ARParticleField(color: accentColor, isVisible: particlesVisible).ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Ellipse()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 260, height: 28)
                        .blur(radius: 16)
                        .offset(y: 178)
                        .scaleEffect(x: scale * pinchScale * 0.88, y: scale * pinchScale * 0.88)

                    StickerDetailCard(
                        entry: entry,
                        accentColor: accentColor,
                        alertIcon: alertIcon,
                        alertTitle: alertTitle,
                        currentFace: currentFace,
                        flipAngle: flipAngle,
                        glowPulse: glowPulse,
                        onIconTap: { flipToBack() },
                        onDismiss: dismissCard
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
                                let delta = value / lastPinch
                                lastPinch = value
                                pinchScale = max(0.4, min(2.2, pinchScale * delta))
                            }
                            .onEnded { _ in lastPinch = 1.0 }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 8))  { shakeOffset =  12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.interpolatingSpring(stiffness: 600, damping: 8))  { shakeOffset = -10 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) { shakeOffset = 6 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.spring()) { shakeOffset = 0 }
                    }
                }
            }
        }
    }

    private func flipToBack() {
        let next: CardFace = currentFace == .front ? .back : .front
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { flipAngle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            currentFace = next
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { flipAngle = 0 }
        }
    }

    private func dismissCard() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { scale = 0.55; opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) { onDismiss() }
    }
}

// MARK: sticker detail card
struct StickerDetailCard: View {
    let entry:       ScanHistoryEntry
    let accentColor: Color
    let alertIcon:   String
    let alertTitle:  String
    let currentFace: StickerDetailOverlay.CardFace
    let flipAngle:   Double
    let glowPulse:   Bool
    let onIconTap:   () -> Void
    let onDismiss:   () -> Void

    @State private var ringProgress: Double = 0
    @State private var badgePulse:   Bool   = false

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

            Group {
                switch currentFace {
                case .front: frontFace
                case .back:  backFace
                }
            }
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0))
            .padding(22)
        }
        .onAppear { ringProgress = 1.0; badgePulse = true }
    }
    // MARK: carta fronte
    private var frontFace: some View {
        VStack(spacing: 14) {
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
                            .shadow(color: accentColor.opacity(badgePulse ? 0.75 : 0.4),
                                    radius: badgePulse ? 22 : 14, y: 4)
                            .scaleEffect(badgePulse ? 1.06 : 1.0)
                            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: badgePulse)
                        Image(systemName: alertIcon)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }

            Text(entry.productName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(alertTitle)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(accentColor)
                .tracking(1.5)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(accentColor.opacity(0.4), lineWidth: 1))

            HStack(spacing: 4) {
                Image(systemName: "arrow.2.squarepath").font(.system(size: 9))
                Text("Tocca il simbolo per vedere i dettagli")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(accentColor.opacity(0.7))
        }
    }
    
    //MARK: carta retro
    private var backFace: some View {
        VStack(spacing: 9) {
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

            HStack(spacing: 6) {
                Image(systemName: "clock").font(.caption2).foregroundStyle(.white.opacity(0.50))
                Text(entry.date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier: "it_IT"))))
                    .font(.caption).foregroundStyle(.white.opacity(0.55)).italic()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)

            let segments = entry.alertSummary.components(separatedBy: " • ")
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                if seg.hasPrefix("Allergeni:") {
                    AlertDetailSection(label: "CONTIENE", color: Color(hex: "E63312"),
                                       items: [String(seg.dropFirst("Allergeni: ".count))])
                } else if seg.hasPrefix("Tracce:") {
                    AlertDetailSection(label: "TRACCE DI", color: Color(hex: "FECB02"),
                                       items: [String(seg.dropFirst("Tracce: ".count))])
                } else if seg.hasPrefix("Dieta:") {
                    AlertDetailSection(label: "NON ADATTO A DIETE", color: Color(hex: "888888"),
                                       items: [String(seg.dropFirst("Dieta: ".count))])
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.title3)
                        Text(seg).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.82))
                    }
                    .frame(maxWidth: .infinity).padding(.top, 8)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func nutriscoreHex(_ g: String) -> String {
        switch g.uppercased() {
        case "A": return "038141"; case "B": return "85BB2F"
        case "C": return "FECB02"; case "D": return "EE8100"
        case "E": return "E63312"; default: return "AAAAAA"
        }
    }
}
