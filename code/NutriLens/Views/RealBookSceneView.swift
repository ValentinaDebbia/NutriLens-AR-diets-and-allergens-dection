import SceneKit
import SwiftUI

struct RealBookSceneView: UIViewRepresentable {
    // MARK: libro e interazioni iniziali
    let entries:     [ScanHistoryEntry]
    @Binding var isOpen:     Bool
    @Binding var currentPage: Int
    @Binding var isFlipping:  Bool
    var onCoordinatorReady: ((Coordinator) -> Void)? = nil
    var onTapLeft:  (() -> Void)? = nil
    var onTapRight: (() -> Void)? = nil
    var onTapEntry: (() -> Void)? = nil
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene           = buildScene(coordinator: context.coordinator)
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl    = true
        scnView.autoenablesDefaultLighting = false
        scnView.antialiasingMode       = .multisampling4X
        
        // tap per aprire/chiudere il libro
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        scnView.addGestureRecognizer(tap)
        
        context.coordinator.scnView = scnView
        return scnView
    }
    
    func updateUIView(_ scnView: SCNView, context: Context) {
        context.coordinator.updateCover(isOpen: isOpen)
        context.coordinator.updatePages(entries: entries, currentPage: currentPage)
        // propaga le callback al coordinator ad ogni update
        context.coordinator.onTapLeft  = onTapLeft
        context.coordinator.onTapRight = onTapRight
        context.coordinator.isOpenBinding = isOpen
        context.coordinator.isFlippingBinding = isFlipping
        context.coordinator.onTapEntry = onTapEntry
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(parent: self)
        onCoordinatorReady?(coordinator)
        return coordinator
    }
    
    // MARK: costruzione scena
    private func buildScene(coordinator: Coordinator) -> SCNScene {
        let scene = SCNScene()
        
        let W: CGFloat = 8.0
        let H: CGFloat = 12.0
        let D: CGFloat = 2.0
        
        // corpo libro
        let bookBody = SCNBox(width: W, height: H, length: D, chamferRadius: 0.05)
        bookBody.materials = [
            pageFaceMaterial(entries: entries, page: 0),
            makePageEdgeMaterial(horizontal: false),
            makeCoverMaterial(isBack: true),
            makeSpineMaterial(),
            makePageEdgeMaterial(horizontal: true),
            makePageEdgeMaterial(horizontal: true)
        ]
        let bodyNode = SCNNode(geometry: bookBody)
        bodyNode.name = "body"
        scene.rootNode.addChildNode(bodyNode)
        
        // pagina che "vola" durante il flip
        let pageGeom = SCNBox(width: W, height: H, length: 0.04, chamferRadius: 0.02)
        pageGeom.materials = [
            pageFaceMaterial(entries: entries, page: 0),
            makePageEdgeMaterial(horizontal: false),
            pageBackMaterial(page: 0),
            makePageEdgeMaterial(horizontal: false),
            makePageEdgeMaterial(horizontal: true),
            makePageEdgeMaterial(horizontal: true)
        ]
        let pagePivot = SCNNode()
        pagePivot.name   = "pagePivot"
        pagePivot.position = SCNVector3(-W / 2, 0, D / 2 + 0.03)
        pagePivot.opacity  = 0
        scene.rootNode.addChildNode(pagePivot)
        
        let pageNode = SCNNode(geometry: pageGeom)
        pageNode.name     = "flipPage"
        pageNode.position = SCNVector3(W / 2, 0, 0)
        pagePivot.addChildNode(pageNode)
        coordinator.flipPageGeom = pageGeom
        
        // copertina frontale
        let coverGeom = SCNBox(width: W, height: H, length: 0.12, chamferRadius: 0.04)
        coverGeom.materials = makeCoverMaterials(isBack: false)
        let coverPivot = SCNNode()
        coverPivot.name     = "coverPivot"
        coverPivot.position = SCNVector3(-W / 2, 0, D / 2)
        scene.rootNode.addChildNode(coverPivot)
        let coverNode = SCNNode(geometry: coverGeom)
        coverNode.name     = "cover"
        coverNode.position = SCNVector3(W / 2, 0, 0.06)
        coverPivot.addChildNode(coverNode)
        coverNode.renderingOrder = 0
        coverPivot.renderingOrder = 0
        
        // dorso
        let spineGeom = SCNBox(width: 0.15, height: H, length: D, chamferRadius: 0.03)
        spineGeom.materials = Array(repeating: makeSpineMaterial(), count: 6)
        let spineNode = SCNNode(geometry: spineGeom)
        spineNode.position = SCNVector3(-W / 2 - 0.07, 0, 0)
        scene.rootNode.addChildNode(spineNode)
        
        addLights(to: scene)
        
        let camera    = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear  = 0.01
        camera.zFar   = 100
        let camNode   = SCNNode()
        camNode.camera  = camera
        camNode.position = SCNVector3(2, 3, 20)
        camNode.eulerAngles = SCNVector3(-0.12, 0.10, 0)
        scene.rootNode.addChildNode(camNode)
        
        let floor = SCNFloor()
        floor.reflectivity = 0.04
        let floorMat = SCNMaterial()
        floorMat.diffuse.contents = UIColor.clear
        floor.materials = [floorMat]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, -H / 2, 0)
        scene.rootNode.addChildNode(floorNode)
        
        coordinator.bodyGeom = bookBody
        return scene
    }
    
    // MARK: configurazione luci, camera e ambiente + materiali 3D e 2D
    private func pageFaceMaterial(entries: [ScanHistoryEntry], page: Int) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = drawPageTexture(entries: entries, page: page)
        mat.lightingModel    = .phong
        mat.specular.contents = UIColor(white: 0.15, alpha: 1)
        mat.shininess = 0.2
        return mat
    }
    
    private func pageBackMaterial(page: Int) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = drawPageBackTexture(pageIndex: page)
        mat.lightingModel    = .lambert
        return mat
    }
    
    private func makeCoverMaterials(isBack: Bool) -> [SCNMaterial] {
        let front = SCNMaterial()
        front.diffuse.contents = isBack ? drawBackCoverImage() : drawFrontCoverImage()
        front.specular.contents = UIColor(white: 0.3, alpha: 1)
        front.shininess = 0.4
        front.lightingModel = .phong
        
        let inner = SCNMaterial()
        inner.diffuse.contents = drawCoverInnerImage()
        inner.lightingModel    = .phong
        
        let side = makeMaterial(color: UIColor(red: 0.04, green: 0.22, blue: 0.14, alpha: 1))
        return [front, side, inner, side, side, side]
    }
    
    private func makeCoverMaterial(isBack: Bool) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = isBack ? drawBackCoverImage() : drawFrontCoverImage()
        mat.specular.contents = UIColor(white: 0.3, alpha: 1)
        mat.shininess = 0.4
        mat.lightingModel = .phong
        return mat
    }
    
    func makePageEdgeMaterial(horizontal: Bool) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents  = drawPageEdgeImage(horizontal: horizontal)
        mat.lightingModel     = .lambert
        return mat
    }
    
    private func makeSpineMaterial() -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents  = drawSpineImage()
        mat.specular.contents = UIColor(white: 0.2, alpha: 1)
        mat.shininess = 0.3
        mat.lightingModel = .phong
        return mat
    }
    
    private func makeMaterial(color: UIColor) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel    = .phong
        return mat
    }
    
    // luci
    private func addLights(to scene: SCNScene) {
        let key = SCNLight(); key.type = .directional; key.intensity = 900
        key.color = UIColor.white; key.castsShadow = true
        key.shadowRadius = 8; key.shadowColor = UIColor.black.withAlphaComponent(0.4)
        let kn = SCNNode(); kn.light = key
        kn.eulerAngles = SCNVector3(-Float.pi/4, Float.pi/5, 0)
        scene.rootNode.addChildNode(kn)
        
        let fill = SCNLight(); fill.type = .directional; fill.intensity = 300
        fill.color = UIColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 1)
        let fn = SCNNode(); fn.light = fill
        fn.eulerAngles = SCNVector3(-Float.pi/8, -Float.pi/3, 0)
        scene.rootNode.addChildNode(fn)
        
        let amb = SCNLight(); amb.type = .ambient; amb.intensity = 200
        amb.color = UIColor(red: 0.9, green: 0.88, blue: 0.85, alpha: 1)
        let an = SCNNode(); an.light = amb
        scene.rootNode.addChildNode(an)
    }
    
    // pagina figurina
    private func drawPageTexture(entries: [ScanHistoryEntry], page: Int) -> UIImage {
        let size = CGSize(width: 512, height: 768)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            
            let bgGrad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.97, green: 0.94, blue: 0.89, alpha: 1).cgColor,
                    UIColor(red: 0.91, green: 0.87, blue: 0.81, alpha: 1).cgColor
                ] as CFArray,
                locations: [0, 1]
            )!
            cgCtx.drawLinearGradient(bgGrad,
                                     start: CGPoint(x: 0, y: 0),
                                     end:   CGPoint(x: 0, y: size.height),
                                     options: [])
            
            UIColor.black.withAlphaComponent(0.07).setStroke()
            let borderPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: 8)
            borderPath.lineWidth = 2
            borderPath.stroke()
            
            guard page < entries.count else {
                drawEmptyPage(ctx: cgCtx, size: size)
                return
            }
            
            let entry  = entries[page]
            let accent = uiColor(for: entry.safetyStatus)
            
            drawGridLines(ctx: cgCtx, size: size, color: accent.withAlphaComponent(0.22))
            drawCornerDecorations(ctx: cgCtx, size: size, color: accent)
            
            let headerY: CGFloat = 20
            let numLabel = "#\(String(format: "%03d", page + 1))" as NSString
            numLabel.draw(at: CGPoint(x: 20, y: headerY + 14),
                          withAttributes: [
                            .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .black),
                            .foregroundColor: accent
                          ])
            
            let figLabel = "FIGURINA" as NSString
            figLabel.draw(at: CGPoint(x: 20, y: headerY),
                          withAttributes: [
                            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .black),
                            .foregroundColor: accent.withAlphaComponent(0.6),
                            .kern: 3.0
                          ])
            
            let totalStr = "\(page + 1) / \(entries.count)" as NSString
            let totalAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.black.withAlphaComponent(0.28)
            ]
            let totalSize = totalStr.size(withAttributes: totalAttr)
            totalStr.draw(at: CGPoint(x: size.width - totalSize.width - 20, y: headerY + 8),
                          withAttributes: totalAttr)
            
            accent.withAlphaComponent(0.15).setFill()
            UIBezierPath(rect: CGRect(x: 20, y: 68, width: size.width - 40, height: 1)).fill()
            
            let circleCenter = CGPoint(x: size.width / 2, y: 200)
            let circleR: CGFloat = 72
            accent.withAlphaComponent(0.11).setFill()
            UIBezierPath(ovalIn: CGRect(x: circleCenter.x - circleR, y: circleCenter.y - circleR,
                                        width: circleR * 2, height: circleR * 2)).fill()
            accent.withAlphaComponent(0.32).setStroke()
            let strokePath = UIBezierPath(ovalIn: CGRect(x: circleCenter.x - circleR, y: circleCenter.y - circleR,
                                                         width: circleR * 2, height: circleR * 2))
            strokePath.lineWidth = 3
            strokePath.stroke()
            
            let iconChar = safetyStatusEmoji(entry.safetyStatus) as NSString
            let iconFont: UIFont = entry.safetyStatus == .danger
                ? UIFont.systemFont(ofSize: 58, weight: .black)
                : UIFont.systemFont(ofSize: 54, weight: .bold)
            let iconAttr: [NSAttributedString.Key: Any] = [
                .font: iconFont,
                .foregroundColor: accent
            ]
            let iconSize = iconChar.size(withAttributes: iconAttr)
            iconChar.draw(at: CGPoint(x: circleCenter.x - iconSize.width / 2,
                                      y: circleCenter.y - iconSize.height / 2),
                          withAttributes: iconAttr)
            
            let nameY: CGFloat = 300
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 26),
                .foregroundColor: UIColor(red: 0.15, green: 0.13, blue: 0.10, alpha: 1),
                .paragraphStyle: centeredParagraphStyle()
            ]
            let nameRect = CGRect(x: 24, y: nameY, width: size.width - 48, height: 100)
            (entry.productName as NSString).draw(in: nameRect, withAttributes: nameAttrs)
            
            let badgeY: CGFloat = 415
            let statusText = entry.safetyStatus.label.uppercased() as NSString
            let statusAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .black),
                .foregroundColor: accent,
                .kern: 2.0
            ]
            let statusSize = statusText.size(withAttributes: statusAttr)
            let badgePadH: CGFloat = 20; let badgePadV: CGFloat = 8
            let badgeW = statusSize.width + badgePadH * 2
            let badgeX = (size.width - badgeW) / 2
            let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeW, height: statusSize.height + badgePadV * 2)
            accent.withAlphaComponent(0.11).setFill()
            UIBezierPath(roundedRect: badgeRect, cornerRadius: 10).fill()
            accent.withAlphaComponent(0.32).setStroke()
            let badgeBorder = UIBezierPath(roundedRect: badgeRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10)
            badgeBorder.lineWidth = 1.5; badgeBorder.stroke()
            statusText.draw(at: CGPoint(x: badgeX + badgePadH, y: badgeY + badgePadV), withAttributes: statusAttr)
            
            drawDataGrid(ctx: cgCtx, size: size, entry: entry, accent: accent, y: 490)
        }
    }
    
    // retro pagina
    func drawPageBackTexture(pageIndex: Int) -> UIImage {
        let size = CGSize(width: 512, height: 768)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            
            let bgGrad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.92, green: 0.88, blue: 0.82, alpha: 1).cgColor,
                    UIColor(red: 0.86, green: 0.82, blue: 0.75, alpha: 1).cgColor
                ] as CFArray,
                locations: [0, 1]
            )!
            cgCtx.drawLinearGradient(bgGrad,
                                     start: CGPoint(x: 0, y: 0),
                                     end:   CGPoint(x: 0, y: size.height),
                                     options: [])
            
            UIColor.black.withAlphaComponent(0.04).setStroke()
            var y: CGFloat = 22
            while y < size.height {
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 20, y: y)); p.addLine(to: CGPoint(x: size.width - 20, y: y))
                p.lineWidth = 0.5; p.stroke()
                y += 22
            }
            
            let accent = UIColor(red: 0.05, green: 0.27, blue: 0.17, alpha: 1)
            let leafStr = "✿" as NSString
            let leafAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 58, weight: .ultraLight),
                .foregroundColor: accent.withAlphaComponent(0.12)
            ]
            let ls = leafStr.size(withAttributes: leafAttr)
            leafStr.draw(at: CGPoint(x: size.width/2 - ls.width/2, y: size.height/2 - ls.height/2 - 20),
                         withAttributes: leafAttr)
            
            let nlStr = "NutriLens" as NSString
            let nlAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia", size: 18) ?? .systemFont(ofSize: 18),
                .foregroundColor: accent.withAlphaComponent(0.14),
                .kern: 3.0
            ]
            let ns = nlStr.size(withAttributes: nlAttr)
            nlStr.draw(at: CGPoint(x: size.width/2 - ns.width/2, y: size.height/2 + 18),
                       withAttributes: nlAttr)
            
            if pageIndex >= 0 {
                let numStr = "\(pageIndex + 1)" as NSString
                let numAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont(name: "Georgia", size: 14) ?? .systemFont(ofSize: 14),
                    .foregroundColor: UIColor.black.withAlphaComponent(0.20)
                ]
                let numS = numStr.size(withAttributes: numAttr)
                numStr.draw(at: CGPoint(x: size.width/2 - numS.width/2, y: size.height - 36),
                            withAttributes: numAttr)
            }
        }
    }
    
    // MARK: elementi decorativi
    private func drawDataGrid(ctx: CGContext, size: CGSize, entry: ScanHistoryEntry, accent: UIColor, y: CGFloat) {
        let gridRect = CGRect(x: 20, y: y, width: size.width - 40, height: 100)
        UIColor.black.withAlphaComponent(0.04).setFill()
        UIBezierPath(roundedRect: gridRect, cornerRadius: 12).fill()

        let colW = gridRect.width / 3

        // separatori verticali
        UIColor.black.withAlphaComponent(0.10).setFill()
        UIBezierPath(rect: CGRect(x: gridRect.minX + colW,     y: gridRect.minY + 12, width: 1, height: gridRect.height - 24)).fill()
        UIBezierPath(rect: CGRect(x: gridRect.minX + colW * 2, y: gridRect.minY + 12, width: 1, height: gridRect.height - 24)).fill()

        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.black.withAlphaComponent(0.36),
            .kern: 1.5
        ]

        // colonna 1: Nutri-Score
        drawCenteredText("NUTRI-SCORE", attrs: labelAttr,
                         in: CGRect(x: gridRect.minX, y: gridRect.minY + 12, width: colW, height: 16))
        let nsText  = entry.nutriscore.uppercased() as NSString
        let nsColor = UIColor(hex: nutriHex(entry.nutriscore))
        let nsRect  = CGRect(x: gridRect.minX + colW / 2 - 22, y: gridRect.minY + 34, width: 44, height: 44)
        nsColor.setFill()
        UIBezierPath(roundedRect: nsRect, cornerRadius: 10).fill()
        let nsAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 22),
            .foregroundColor: UIColor.white
        ]
        let nsS = nsText.size(withAttributes: nsAttr)
        nsText.draw(at: CGPoint(x: nsRect.midX - nsS.width / 2,
                                y: nsRect.midY - nsS.height / 2), withAttributes: nsAttr)

        // colonna 2: data
        drawCenteredText("DATA", attrs: labelAttr,
                         in: CGRect(x: gridRect.minX + colW, y: gridRect.minY + 12, width: colW, height: 16))
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateFormat = "d MMM"                      // es. "3 mag"
        let dateText = df.string(from: entry.date) as NSString
        let dateAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor(red: 0.25, green: 0.25, blue: 0.22, alpha: 1)
        ]
        drawCenteredText(dateText as String, attrs: dateAttr,
                         in: CGRect(x: gridRect.minX + colW, y: gridRect.minY + 38, width: colW, height: 30))
        let yearAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.black.withAlphaComponent(0.28)
        ]
        let yearStr = Calendar.current.component(.year, from: entry.date)
        drawCenteredText("\(yearStr)", attrs: yearAttr,
                         in: CGRect(x: gridRect.minX + colW, y: gridRect.minY + 68, width: colW, height: 18))

        // colonna 3: dettagli — pill accent con "i" ─
        let col3X = gridRect.minX + colW * 2
        let rowCenterY = gridRect.midY

        let detLabelStr = "DETTAGLI" as NSString
        let detLabelAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: accent,
            .kern: 1.5
        ]
        let detLabelSize = detLabelStr.size(withAttributes: detLabelAttr)

        let iAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Georgia-Italic", size: 14) ?? UIFont.italicSystemFont(ofSize: 14),
            .foregroundColor: accent
        ]
        let iStr = "i" as NSString
        let iSize = iStr.size(withAttributes: iAttr)

        let pillSpacing: CGFloat = 6
        let pillPadH: CGFloat = 10
        let pillPadV: CGFloat = 7
        let pillH: CGFloat = detLabelSize.height + pillPadV * 2
        let pillW: CGFloat = pillPadH + detLabelSize.width + pillSpacing + iSize.width + pillPadH
        let pillX = col3X + (colW - pillW) / 2
        let pillY = rowCenterY - pillH / 2

        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
        accent.withAlphaComponent(0.13).setFill()
        UIBezierPath(roundedRect: pillRect, cornerRadius: pillH / 2).fill()

        accent.withAlphaComponent(0.35).setStroke()
        let borderPath = UIBezierPath(roundedRect: pillRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: pillH / 2)
        borderPath.lineWidth = 1.2
        borderPath.stroke()

        detLabelStr.draw(
            at: CGPoint(x: pillX + pillPadH,
                        y: pillY + (pillH - detLabelSize.height) / 2),
            withAttributes: detLabelAttr
        )

        accent.withAlphaComponent(0.25).setFill()
        UIBezierPath(rect: CGRect(
            x: pillX + pillPadH + detLabelSize.width + pillSpacing / 2 - 0.5,
            y: pillY + pillPadV,
            width: 1,
            height: pillH - pillPadV * 2
        )).fill()

        iStr.draw(
            at: CGPoint(x: pillX + pillPadH + detLabelSize.width + pillSpacing,
                        y: pillY + (pillH - iSize.height) / 2),
            withAttributes: iAttr
        )
    }
    
    // pagina vuota
    private func drawEmptyPage(ctx: CGContext, size: CGSize) {
        let iconStr = "⊙" as NSString
        let iconAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 68, weight: .ultraLight),
            .foregroundColor: UIColor.black.withAlphaComponent(0.18)
        ]
        let is_ = iconStr.size(withAttributes: iconAttr)
        iconStr.draw(at: CGPoint(x: size.width/2 - is_.width/2, y: size.height/2 - 70),
                     withAttributes: iconAttr)
        
        let t1 = "Album vuoto" as NSString
        let a1: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Georgia", size: 22) ?? .systemFont(ofSize: 22),
            .foregroundColor: UIColor.black.withAlphaComponent(0.32)
        ]
        let s1 = t1.size(withAttributes: a1)
        t1.draw(at: CGPoint(x: size.width/2 - s1.width/2, y: size.height/2), withAttributes: a1)
        
        let t2 = "Scansiona prodotti\nper raccogliere figurine" as NSString
        let ps  = NSMutableParagraphStyle(); ps.alignment = .center
        let a2: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.black.withAlphaComponent(0.22),
            .paragraphStyle: ps
        ]
        t2.draw(in: CGRect(x: 40, y: size.height/2 + 36, width: size.width - 80, height: 60),
                withAttributes: a2)
    }
    
    
    private func drawGridLines(ctx: CGContext, size: CGSize, color: UIColor) {
        color.setStroke()
        let step: CGFloat = 32
        var x: CGFloat = 0
        while x <= size.width {
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
            p.lineWidth = 0.3; p.stroke()
            x += step
        }
        var y: CGFloat = 0
        while y <= size.height {
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            p.lineWidth = 0.3; p.stroke()
            y += step
        }
    }
    
    
    private func drawCornerDecorations(ctx: CGContext, size: CGSize, color: UIColor) {
        color.setStroke()
        let len: CGFloat = 24; let lw: CGFloat = 2.0
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 12, y: 12 + len), CGPoint(x: 12, y: 12), CGPoint(x: 12 + len, y: 12)),
            (CGPoint(x: size.width - 12 - len, y: 12), CGPoint(x: size.width - 12, y: 12), CGPoint(x: size.width - 12, y: 12 + len)),
            (CGPoint(x: 12, y: size.height - 12 - len), CGPoint(x: 12, y: size.height - 12), CGPoint(x: 12 + len, y: size.height - 12)),
            (CGPoint(x: size.width - 12 - len, y: size.height - 12), CGPoint(x: size.width - 12, y: size.height - 12), CGPoint(x: size.width - 12, y: size.height - 12 - len))
        ]
        for (a, b, c) in corners {
            let p = UIBezierPath()
            p.move(to: a); p.addLine(to: b); p.addLine(to: c)
            p.lineWidth = lw; p.stroke()
        }
    }
    
    // copertine
    private func drawFrontCoverImage() -> UIImage {
        let size = CGSize(width: 512, height: 768)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let r = ctx.cgContext
            let grad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.05, green: 0.27, blue: 0.17, alpha: 1).cgColor,
                    UIColor(red: 0.02, green: 0.14, blue: 0.09, alpha: 1).cgColor
                ] as CFArray, locations: [0, 1])!
            r.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            
            UIColor(red: 0, green: 0.85, blue: 0.44, alpha: 0.28).setStroke()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: 8).stroke()
            
            drawGridLines(ctx: r, size: size, color: UIColor(red: 0, green: 0.85, blue: 0.44, alpha: 0.09))
            
            UIColor(red: 0.72, green: 0.90, blue: 0.55, alpha: 0.38).setStroke()
            let innerRect = UIBezierPath(roundedRect: CGRect(x: 16, y: 16, width: size.width - 32, height: size.height - 32), cornerRadius: 5)
            innerRect.lineWidth = 1; innerRect.stroke()
            
            let accentUI = UIColor(red: 0, green: 0.85, blue: 0.44, alpha: 1)
            
            accentUI.withAlphaComponent(0.55).setFill()
            UIBezierPath(rect: CGRect(x: 40, y: size.height * 0.35 - 14, width: size.width - 80, height: 1)).fill()
            
            let albumAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: accentUI.withAlphaComponent(0.55),
                .kern: 4.5
            ]
            drawCenteredText("SCANNERIZZAZIONI PRECEDENTI", attrs: albumAttr,
                             in: CGRect(x: 0, y: size.height * 0.35 - 34, width: size.width, height: 18))
            
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia-Bold", size: 72) ?? .boldSystemFont(ofSize: 72),
                .foregroundColor: UIColor.white
            ]
            let tStr = "NutriLens" as NSString
            let tSize = tStr.size(withAttributes: titleAttr)
            tStr.draw(at: CGPoint(x: (size.width - tSize.width)/2, y: size.height * 0.35 + 2), withAttributes: titleAttr)
            
            let subAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia-Italic", size: 38) ?? .italicSystemFont(ofSize: 38),
                .foregroundColor: UIColor(red: 0.72, green: 0.90, blue: 0.55, alpha: 0.90)
            ]
            let sStr = "Collection" as NSString
            let sSize = sStr.size(withAttributes: subAttr)
            sStr.draw(at: CGPoint(x: (size.width - sSize.width)/2, y: size.height * 0.35 + tSize.height + 8), withAttributes: subAttr)
            
            accentUI.withAlphaComponent(0.55).setFill()
            UIBezierPath(rect: CGRect(x: 40, y: size.height * 0.35 + tSize.height + sSize.height + 22, width: size.width - 80, height: 1)).fill()
            
            let edAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.38),
                .kern: 3.0
            ]
            drawCenteredText("★ PRIMA EDIZIONE ★", attrs: edAttr,
                             in: CGRect(x: 0, y: size.height - 66, width: size.width, height: 18))
            let yrAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .light),
                .foregroundColor: UIColor.white.withAlphaComponent(0.28),
                .kern: 6.0
            ]
            drawCenteredText("2026", attrs: yrAttr,
                             in: CGRect(x: 0, y: size.height - 42, width: size.width, height: 22))
        }
    }
    
    private func drawCoverInnerImage() -> UIImage {
        let size = CGSize(width: 512, height: 768)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(red: 0.04, green: 0.22, blue: 0.14, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let accent = UIColor(red: 0, green: 0.85, blue: 0.44, alpha: 1)
            let a1: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .ultraLight),
                .foregroundColor: accent.withAlphaComponent(0.22)
            ]
            let a2: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia-Italic", size: 18) ?? .italicSystemFont(ofSize: 18),
                .foregroundColor: UIColor.white.withAlphaComponent(0.18)
            ]
            let ls = ("" as NSString).size(withAttributes: a1)
            ("" as NSString).draw(at: CGPoint(x: size.width/2 - ls.width/2, y: size.height/2 - ls.height/2 - 20), withAttributes: a1)
            let ns = ("NutriLens" as NSString).size(withAttributes: a2)
            ("NutriLens" as NSString).draw(at: CGPoint(x: size.width/2 - ns.width/2, y: size.height/2 + 20), withAttributes: a2)
        }
    }
    
    private func drawBackCoverImage() -> UIImage {
        let size = CGSize(width: 512, height: 768)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let r = ctx.cgContext
            let grad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.05, green: 0.27, blue: 0.17, alpha: 1).cgColor,
                    UIColor(red: 0.02, green: 0.14, blue: 0.09, alpha: 1).cgColor
                ] as CFArray, locations: [0, 1])!
            r.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            
            UIColor(red: 0, green: 0.65, blue: 0.35, alpha: 0.16).setStroke()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), cornerRadius: 8).stroke()
            
            let ps = NSMutableParagraphStyle(); ps.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia-Italic", size: 28) ?? .italicSystemFont(ofSize: 28),
                .foregroundColor: UIColor.white.withAlphaComponent(0.22),
                .paragraphStyle: ps
            ]
            ("\"Ogni scansione\nè una scoperta.\"" as NSString)
                .draw(in: CGRect(x: 60, y: size.height/2 - 60, width: size.width - 120, height: 120),
                      withAttributes: attrs)
            
            UIColor(red: 0, green: 0.65, blue: 0.35, alpha: 0.18).setFill()
            UIBezierPath(rect: CGRect(x: size.width/2 - 30, y: size.height/2 + 70, width: 60, height: 1)).fill()
        }
    }
    
    private func drawPageEdgeImage(horizontal: Bool) -> UIImage {
        let size = horizontal ? CGSize(width: 512, height: 128) : CGSize(width: 128, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(red: 0.94, green: 0.91, blue: 0.85, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            UIColor.black.withAlphaComponent(0.08).setStroke()
            let step: CGFloat = 4
            if horizontal {
                var x: CGFloat = step
                while x < size.width {
                    let p = UIBezierPath(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                    p.lineWidth = 0.5; p.stroke(); x += step
                }
            } else {
                var y: CGFloat = step
                while y < size.height {
                    let p = UIBezierPath(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                    p.lineWidth = 0.5; p.stroke(); y += step
                }
            }
        }
    }
    
    private func drawSpineImage() -> UIImage {
        let size = CGSize(width: 128, height: 768)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let r = ctx.cgContext
            let grad = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.02, green: 0.16, blue: 0.10, alpha: 1).cgColor,
                    UIColor(red: 0.08, green: 0.45, blue: 0.27, alpha: 1).cgColor,
                    UIColor(red: 0.02, green: 0.16, blue: 0.10, alpha: 1).cgColor
                ] as CFArray, locations: [0, 0.5, 1])!
            r.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            
            r.saveGState()
            r.translateBy(x: size.width/2, y: size.height * 0.60)
            r.rotate(by: -.pi/2)
            let spAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia-Bold", size: 20) ?? .boldSystemFont(ofSize: 20),
                .foregroundColor: UIColor(red: 0.63, green: 1.0, blue: 0.78, alpha: 0.85),
                .kern: 5.0
            ]
            let spStr = "NutriLens" as NSString
            let spS = spStr.size(withAttributes: spAttr)
            spStr.draw(at: CGPoint(x: -spS.width/2, y: -spS.height/2), withAttributes: spAttr)
            r.restoreGState()
        }
    }
    
    private func drawCenteredText(_ text: String, attrs: [NSAttributedString.Key: Any], in rect: CGRect) {
        let ns = text as NSString
        let s  = ns.size(withAttributes: attrs)
        ns.draw(at: CGPoint(x: rect.midX - s.width/2, y: rect.midY - s.height/2), withAttributes: attrs)
    }
    
    private func centeredParagraphStyle() -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle(); ps.alignment = .center; return ps
    }
    
    private func nutriHex(_ g: String) -> String {
        switch g.uppercased() {
        case "A": return "#038141"; case "B": return "#85BB2F"
        case "C": return "#FECB02"; case "D": return "#EE8100"
        case "E": return "#E63312"; default: return "#888888"
        }
    }
    
    private func uiColor(for status: ScanHistoryEntry.SafetyStatusCodable) -> UIColor {
        switch status {
        case .safe:    return UIColor(red: 0.09, green: 0.56, blue: 0.32, alpha: 1)
        case .warning: return UIColor(red: 0.95, green: 0.60, blue: 0.00, alpha: 1)
        case .danger:  return UIColor(red: 0.90, green: 0.17, blue: 0.07, alpha: 1)
        }
    }
    
    private func safetyStatusEmoji(_ status: ScanHistoryEntry.SafetyStatusCodable) -> String {
        switch status {
        case .safe:    return "✓"
        case .warning: return "⚠"
        case .danger:  return "✗"
        }
    }
    
    // MARK: coordinatori
    class Coordinator: NSObject {
        var parent: RealBookSceneView
        weak var scnView: SCNView?
        var bodyGeom:     SCNBox?
        var flipPageGeom: SCNBox?

        var onTapLeft:  (() -> Void)?
        var onTapRight: (() -> Void)?
        var onTapEntry: (() -> Void)?
        
        var isOpenBinding:     Bool = false
        var isFlippingBinding: Bool = false

        private var isAnimatingFlip = false
        private var openLeaves: [SCNNode] = []
        
        init(parent: RealBookSceneView) {
            self.parent = parent
        }
        
        // tap singolo: se il libro è chiuso → apri/chiudi;
        // se è aperto → gira pagina sinistra/destra.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }

            if !isOpenBinding {
                parent.isOpen.toggle()
                return
            }

            guard !isFlippingBinding else { return }

            let loc = gesture.location(in: view)
            
            let hits = view.hitTest(loc, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .backFaceCulling: false
            ])

            if let hit = hits.first(where: { $0.node.name == "body" || $0.node.parent?.name == "body" }),
               hit.geometryIndex == 0 {

                let uv = hit.textureCoordinates(withMappingChannel: 0)

                let inCol3  = uv.x > 0.667
                let inRowV  = uv.y > 0.638 && uv.y < 0.768

                if inCol3 && inRowV {
                    DispatchQueue.main.async { self.onTapEntry?() }
                    return
                }
            }
            let x = loc.x
            if x < view.bounds.midX {
                onTapLeft?()
            } else {
                onTapRight?()
            }
        }
        
        func updateCover(isOpen: Bool) {
            guard let pivot = scnView?.scene?.rootNode.childNode(withName: "coverPivot", recursively: false)
            else { return }
            
            let angle = isOpen ? -Float.pi * 0.95 : 0
            let action = SCNAction.rotateTo(x: 0, y: CGFloat(angle), z: 0,
                                            duration: 0.85, usesShortestUnitArc: true)
            action.timingMode = .easeInEaseOut
            pivot.runAction(action)
            
            if !isOpen {
                openLeaves.forEach { $0.removeFromParentNode() }
                openLeaves.removeAll()
            }
        }
        
        private func makeOpenLeaf(
            entries: [ScanHistoryEntry],
            pageIndex: Int,
            W: CGFloat, H: CGFloat, D: CGFloat,
            stackOffset: Int
        ) -> SCNNode {
            let fW = Float(W)
            let fD = Float(D)

            let leafGeom = SCNBox(width: W, height: H, length: 0.04, chamferRadius: 0.02)

            let backMat = SCNMaterial()
            backMat.diffuse.contents = parent.drawPageBackTexture(pageIndex: pageIndex)
            backMat.lightingModel = .lambert

            let frontMat = SCNMaterial()
            frontMat.diffuse.contents = parent.drawPageTexture(entries: entries, page: pageIndex)
            frontMat.lightingModel = .phong
            frontMat.specular.contents = UIColor(white: 0.10, alpha: 1)

            let edgeMat  = parent.makePageEdgeMaterial(horizontal: false)
            let edgeMatH = parent.makePageEdgeMaterial(horizontal: true)
            leafGeom.materials = [frontMat, edgeMat, backMat, edgeMat, edgeMatH, edgeMatH]

            let leafPivot = SCNNode()
            leafPivot.position = SCNVector3(-fW / 2, 0, fD / 2 + 0.13 + Float(stackOffset) * 0.05)
            leafPivot.eulerAngles = SCNVector3(0, -Float.pi * 0.95, 0)
            leafPivot.renderingOrder = 100

            let leafNode = SCNNode(geometry: leafGeom)
            leafNode.position = SCNVector3(fW / 2, 0, 0)
            leafNode.renderingOrder = 100
            leafPivot.addChildNode(leafNode)

            return leafPivot
        }
        
        func updatePages(entries: [ScanHistoryEntry], currentPage: Int) {
            guard let box = bodyGeom else { return }
            box.materials[0].diffuse.contents = parent.drawPageTexture(
                entries: entries, page: currentPage)
        }
        
        func animateFlip(forward: Bool, entries: [ScanHistoryEntry], currentPage: Int, completion: @escaping (Int) -> Void) {
            guard !isAnimatingFlip else { return }
            guard let scene    = scnView?.scene,
                  let pivot    = scene.rootNode.childNode(withName: "pagePivot", recursively: false),
                  let pageGeom = flipPageGeom,
                  let bodyGeom = bodyGeom
            else { return }
            
            isAnimatingFlip = true
            let duration: TimeInterval = 0.68
            let newPage = currentPage + (forward ? 1 : -1)
            
            let W: CGFloat = 8.0
            let H: CGFloat = 12.0
            let D: CGFloat = 2.0
            
            if forward {
                pageGeom.materials[0].diffuse.contents = parent.drawPageTexture(
                    entries: entries, page: currentPage)
                pageGeom.materials[2].diffuse.contents = parent.drawPageBackTexture(
                    pageIndex: newPage)
            } else {
                pageGeom.materials[0].diffuse.contents = parent.drawPageTexture(
                    entries: entries, page: newPage)
                pageGeom.materials[2].diffuse.contents = parent.drawPageBackTexture(
                    pageIndex: currentPage)
            }
            
            let startY: Float = forward ? 0 : -Float.pi
            pivot.eulerAngles = SCNVector3(0, startY, 0)
            pivot.opacity = 1
            
            let endY: Float      = forward ? -Float.pi : 0
            let midY: CGFloat    = -CGFloat.pi / 2
            let halfDuration     = duration / 2
            
            let firstHalf = SCNAction.rotateTo(x: 0, y: midY, z: 0,
                                               duration: halfDuration,
                                               usesShortestUnitArc: true)
            firstHalf.timingMode = .easeIn
            
            let secondHalf = SCNAction.rotateTo(x: 0, y: CGFloat(endY), z: 0,
                                                duration: halfDuration,
                                                usesShortestUnitArc: true)
            secondHalf.timingMode = .easeOut
            
            let midAction = SCNAction.run { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    bodyGeom.materials[0].diffuse.contents = self.parent.drawPageTexture(
                        entries: entries, page: newPage)
                }
            }
            
            let finalAction = SCNAction.run { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    pivot.opacity = 0
                    if forward {
                        let leaf = self.makeOpenLeaf(
                            entries: entries,
                            pageIndex: currentPage,
                            W: W, H: H, D: D,
                            stackOffset: self.openLeaves.count
                        )
                        scene.rootNode.addChildNode(leaf)
                        self.openLeaves.append(leaf)
                    } else {
                        self.openLeaves.popLast()?.removeFromParentNode()
                    }
                    self.isAnimatingFlip = false
                    completion(newPage)
                }
            }
            
            let sequence = SCNAction.sequence([firstHalf, midAction, secondHalf, finalAction])
            pivot.runAction(sequence)
        }
    }
}

extension UIColor {
    convenience init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >>  8) & 0xFF) / 255
        let b = CGFloat( rgb        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
