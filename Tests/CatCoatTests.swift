import AppKit

private final class CoatMenuTarget: NSObject {
    var opened = 0
    @objc func openDraw() { opened += 1 }
}

@main
struct CatCoatTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1; precondition(condition(), message)
    }
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let domain = "tw.panh.CatCoatTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = CatCoatStore(defaults: defaults)
        defaults.set("keep", forKey: "unrelated")
        expect(store.load() == .original, "first launch keeps original")
        expect(defaults.data(forKey: CatCoatStore.key) == nil, "reading does not save")
        let coat = CatCoat.generated(seed: 12345)
        store.adopt(coat)
        expect(CatCoatStore(defaults: defaults).load() == coat, "adopted genotype and seed survive reloading")
        store.restoreOriginal()
        expect(store.load() == .original && defaults.data(forKey: CatCoatStore.key) == nil, "original is always recoverable")
        for invalid in [Data("not-json".utf8), Data(repeating: 0, count: 9000), Data("{\"version\":999}".utf8)] {
            defaults.set(invalid, forKey: CatCoatStore.key)
            expect(store.load() == .original, "corrupt/unsupported storage falls back")
            expect(defaults.data(forKey: CatCoatStore.key) == invalid, "fallback does not rewrite old data")
        }
        expect(defaults.string(forKey: "unrelated") == "keep", "unrelated preference preserved")
        var rngA = CatCoatRandom(seed: 17), rngB = CatCoatRandom(seed: 17)
        for _ in 0..<100 {
            expect(CatCoat.draw(using: &rngA) == CatCoat.draw(using: &rngB), "draw sequence is reproducible")
        }
        let coats = (1...500).map { CatCoat.generated(seed: UInt64($0)) }
        expect(Set(coats.map(\.identifier)).count == 500, "each draw has its own seed")
        expect(coats.contains(where: \.isWhite) && coats.contains(where: \.isDilute) && coats.contains(where: \.isPoint), "natural coat loci mix")
        expect(coats.contains { $0.isMosaic && $0.whiteLevel > 0 } && coats.contains { $0.isMosaic && $0.whiteLevel == 0 }, "calico and tortoiseshell both occur")
        expect(coats.contains { $0.hasTabby && $0.whiteLevel > 0 }, "tabby and white spotting combine")
        let templates = try ["sit", "walk", "reply", "body", "tail", "walk-body", "walk-paws", "walk-front-face"].map {
            ($0, try String(contentsOf: resources.appendingPathComponent($0 + ".svg"), encoding: .utf8))
        }
        for (asset, source) in templates {
            expect(CatCoatArtwork(.original).svg(source, asset: asset) == source, "original SVG stays byte-for-byte identical")
            let regex = try NSRegularExpression(pattern: "<path\\b[^>]*id=\"[^\"]+\"[^>]*/>")
            let originalPaths = regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).map { (source as NSString).substring(with: $0.range) }
            for coat in coats.prefix(20) {
                let colored = CatCoatArtwork(coat).svg(source, asset: asset)
                expect(colored == CatCoatArtwork(coat).svg(source, asset: asset), "patch SVG deterministic")
                for tag in originalPaths {
                    let id = CatCoatArtwork.attribute("id", in: tag)!
                    let match = try NSRegularExpression(pattern: "<path\\b[^>]*id=\"" + id + "\"[^>]*/>").firstMatch(in: colored, range: NSRange(colored.startIndex..., in: colored))!
                    let modified = (colored as NSString).substring(with: match.range)
                    for attribute in ["d", "stroke-width", "stroke-linecap", "stroke-linejoin"] {
                        expect(CatCoatArtwork.attribute(attribute, in: modified) == CatCoatArtwork.attribute(attribute, in: tag), "original geometry and expression unchanged")
                    }
                }
            }
        }
        var samples = [CatCoat.original]
        for predicate: (CatCoat) -> Bool in [
            { $0.isWhite }, { $0.isDilute && !$0.isMosaic && !$0.isWhite && !$0.hasTabby && $0.whiteLevel == 0 },
            { $0.isOrange && !$0.isDilute && $0.whiteLevel == 0 && !$0.isPoint },
            { !$0.isMosaic && !$0.isOrange && !$0.isWhite && !$0.hasTabby && !$0.isPoint && $0.whiteLevel == 1 },
            { $0.isMosaic && $0.whiteLevel == 2 && !$0.isDilute },
            { $0.isMosaic && $0.whiteLevel == 0 && !$0.isDilute && !$0.isPoint },
            { $0.isPoint && !$0.isMosaic && $0.whiteLevel == 0 && !$0.isWhite }
        ] { samples.append(coats.first(where: predicate)!) }
        let originalView = DesktopPetView(resources: resources)
        let view = DesktopPetView(resources: resources)
        var firstColored = Data()
        for (index, coat) in samples.enumerated() {
            expect(view.setCoat(coat), "all required SVG assets load together")
            let image = view.renderPNG(pose: .sitting)
            try image.write(to: output.appendingPathComponent("coat-\(index).png"))
            if index == 1 { firstColored = image }
            for pose in DesktopPetPose.allCases {
                for facing in [false, true] {
                    let original = NSBitmapImageRep(data: originalView.renderPNG(pose: pose, phase: 1.6, facingLeft: facing, walkDistance: 12.6))!
                    let colored = NSBitmapImageRep(data: view.renderPNG(pose: pose, phase: 1.6, facingLeft: facing, walkDistance: 12.6))!
                    expect(original.pixelsWide == colored.pixelsWide && original.pixelsHigh == colored.pixelsHigh, "canvas fixed")
                    var changedExterior = 0, changedInterior = 0
                    for y in 0..<original.pixelsHigh { for x in 0..<original.pixelsWide {
                        let a = original.colorAt(x: x, y: y)!.alphaComponent
                        let b = colored.colorAt(x: x, y: y)!.alphaComponent
                        if a < 0.01 && b > 0.05 { changedExterior += 1 }
                        if a > 0.99 && b < 0.95 { changedInterior += 1 }
                    } }
                    // SVG clipping may change coverage of at most two antialiased edge pixels.
                    expect(changedExterior <= 2 && changedInterior == 0, "coat cannot alter silhouette in \(pose), direction \(facing), coat \(coat.title): \(changedExterior)/\(changedInterior)")
                }
            }
        }
        expect(view.setCoat(samples[1]), "reselect previous draw")
        expect(view.renderPNG(pose: .sitting) == firstColored, "same adoption has identical pixels after other draws")
        expect(view.setCoat(.original), "restore original artwork")
        expect(view.renderPNG(pose: .sitting) == originalView.renderPNG(pose: .sitting), "restored original pixels exactly match fresh original")
        let unavailable = DesktopPetView(resources: output.appendingPathComponent("missing"))
        expect(!unavailable.setCoat(samples[1]) && unavailable.coat == .original, "failed asset load cannot commit partial recoloring")
        // Adoption window uses the actual renderer; opening/drawing alone never saves.
        var drawIndex = 0, adopted: [CatCoat] = []
        let controller = CatAdoptionController(resources: resources, generate: {
            drawIndex += 1; return CatCoat.generated(seed: UInt64(drawIndex))
        })
        controller.onAdopt = { coat in adopted.append(coat); store.adopt(coat); return true }
        controller.testDraw()
        let first = controller.candidate
        controller.testDraw()
        expect(first != controller.candidate && adopted.isEmpty, "redraw is only a candidate")
        let candidate = controller.candidate
        controller.testAdopt()
        expect(adopted == [candidate] && store.load() == candidate, "adoption callback commits the displayed candidate")
        controller.testRestore()
        expect(adopted.last == .original && store.load() == .original, "original restoration follows explicit adoption path")
        controller.onAdopt = { _ in false }
        controller.testDraw(); controller.testAdopt()
        expect(store.load() == .original, "rejected adoption leaves stored selection unchanged")
        expect(controller.testButtons.map(\.title) == ["再抽一隻", "帶回桌面", "使用原版黑貓"], "all three choices exposed")
        controller.testDraw()
        let menu = StatusMenuController()
        let menuTarget = CoatMenuTarget()
        menu.configure(target: menuTarget, toggleTitle: "錄音", relayTitle: "手機", actions: ["showCatAdoption": #selector(CoatMenuTarget.openDraw)])
        menu.updateCatCoat(candidate, released: true)
        expect(menu.desktopPetMenuItem.title == "收回" + candidate.title, "release/recall uses the adopted coat")
        expect(menu.statusItem.menu!.items.allSatisfy { !$0.title.contains("抽一隻貓咪") && $0.action != #selector(CoatMenuTarget.openDraw) }, "website acquisition has no local draw menu or action")
        menu.updateCatCoat(.original, released: false)
        expect(menu.desktopPetMenuItem.title == "放出小黑貓", "restored original retains familiar menu")
        NSStatusBar.system.removeStatusItem(menu.statusItem)
        // Applying a coat cannot release a recalled pet or change the timer policy.
        let pet = DesktopPetController(resources: resources, automaticallyTicks: false,
            world: { DesktopPetWorld(areas: [CGRect(x: 0, y: 0, width: 900, height: 700)], perches: [], cursor: .zero, idleSeconds: 30) })
        expect(pet.setCoat(candidate) && !pet.isReleased && !pet.testPanel.isVisible, "preview color does not release pet")
        pet.setReleased(true)
        expect(pet.testPanel.isVisible && pet.testPanel.ignoresMouseEvents && !pet.testPanel.canBecomeKey, "adopted desktop remains click-through and nonactivating")
        pet.setReleased(false); pet.dispose()
        if let root = controller.window?.contentView {
            let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("adoption-window.png"))
        }
        controller.close()
        try renderBoard(samples, resources: resources, output: output)
        print("Cat coat: \(checks) checks passed; original paths, all poses/directions, persisted adoption and native window verified.")
    }
    static func renderBoard(_ coats: [CatCoat], resources: URL, output: URL) throws {
        let image = NSImage(size: NSSize(width: 1440, height: 900), flipped: true) { _ in
            CatCoatArtwork.color("#F6F2EB").setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1440, height: 900)).fill()
            let style = NSMutableParagraphStyle(); style.alignment = .center
            ("App 實際抽選花色 · 原始輪廓與表情" as NSString).draw(in: NSRect(x: 0, y: 25, width: 1440, height: 45), withAttributes: [.font: NSFont.systemFont(ofSize: 29, weight: .semibold), .foregroundColor: NSColor.darkGray, .paragraphStyle: style])
            for (i, coat) in coats.enumerated() {
                let x = CGFloat(30 + i % 4 * 352), y = CGFloat(100 + i / 4 * 390)
                NSColor.white.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 326, height: 365), xRadius: 22, yRadius: 22).fill()
                let pet = DesktopPetView(resources: resources); _ = pet.setCoat(coat); pet.reduceMotion = true
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform(); transform.translateX(by: x + 24, yBy: y + 12); transform.scale(by: 2.15); transform.concat()
                pet.draw(pet.bounds)
                NSGraphicsContext.restoreGraphicsState()
                (coat.title as NSString).draw(in: NSRect(x: x, y: y + 293, width: 326, height: 35), withAttributes: [.font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.darkGray, .paragraphStyle: style])
                (String(coat.identifier.suffix(8)) as NSString).draw(in: NSRect(x: x, y: y + 329, width: 326, height: 22), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.gray, .paragraphStyle: style])
            }
            return true
        }
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("natural-coat-draws.png"))
    }
}
