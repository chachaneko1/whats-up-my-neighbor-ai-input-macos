import AppKit
import UniformTypeIdentifiers

@main final class AppearancePreview: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var pet: DesktopPetController?
    private var greeting: CatOverlay?
    private var hud: NekoRecordingHUD?
    private var configuration = CatConfiguration.defaults.replacingAppearance(CatAppearance.makePreset("tuxedo")!)
    private let presets = NSPopUpButton()
    private let parts = NSPopUpButton()
    private let patterns = NSPopUpButton()
    private let color = NSTextField(string: "#FFFFFF")
    private let secondary = NSTextField(string: "#C88C4E")
    private let status = NSTextField(wrappingLabelWithString: "")
    private var canvas: DesktopPetView?
    private var meter: NekoRecordingView?
    private var timer: Timer?
    private let stage = NSView(frame: CGRect(x: 0, y: 0, width: 620, height: 215))
    private var phase: Double = 0
    private var selectedPose = DesktopPetPose.sitting
    private let poses = NSPopUpButton()
    private var resources: URL { Bundle.main.resourceURL!.appendingPathComponent("DesktopPet") }

    private var examplesURL: URL {
        let local = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Examples/CatAppearance")
        return FileManager.default.fileExists(atPath: local.path) ? local : Bundle.main.resourceURL!.appendingPathComponent("Examples")
    }

    static func main() {
        let app = NSApplication.shared, delegate = AppearancePreview()
        app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "結束毛色預覽", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 690, height: 650),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "YUI Neko・部位毛色預覽"
        window.isReleasedWhenClosed = false; window.delegate = self
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "同一隻貓，不同的毛色")
        title.font = .systemFont(ofSize: 24, weight: .semibold); stack.addArrangedSubview(title)
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: "選毛色，或載入範例設定。桌面上的預覽貓可以點擊、抓起與放下。\n所有調整只在這個預覽中生效；關閉預覽即可結束。"))
        presets.addItems(withTitles: CatAppearance.presetNames); presets.selectItem(at: 5)
        presets.target = self; presets.action = #selector(selectPreset)
        let top = NSStackView(views: [NSTextField(labelWithString: "毛色"), presets,
            NSButton(title: "載入 JSON…", target: self, action: #selector(importConfig)),
            NSButton(title: "開啟範例資料夾", target: self, action: #selector(openExamples))])
        top.spacing = 10; stack.addArrangedSubview(top)
        stage.wantsLayer = true; stage.layer?.backgroundColor = NekoAppearance.background.cgColor
        stage.layer?.cornerRadius = 16
        stage.widthAnchor.constraint(equalToConstant: 620).isActive = true
        stage.heightAnchor.constraint(equalToConstant: 215).isActive = true
        stack.addArrangedSubview(stage)
        poses.addItems(withTitles: DesktopPetPose.allCases.map(\.description)); poses.target = self; poses.action = #selector(selectPose)
        let views = NSStackView(views: [NSTextField(labelWithString: "動作"), poses,
            NSButton(title: "看問候", target: self, action: #selector(showGreeting)),
            NSButton(title: "看錄音浮窗", target: self, action: #selector(showHUD))])
        views.spacing = 10; stack.addArrangedSubview(views)
        parts.addItems(withTitles: ["頭臉", "左耳", "右耳", "口鼻", "胸前", "腹部", "身體", "左前肢", "右前肢", "左後肢", "右後肢", "左前腳掌", "右前腳掌", "左後腳掌", "右後腳掌", "尾巴"]); parts.target = self; parts.action = #selector(selectPart)
        patterns.addItems(withTitles: ["無花紋", "虎斑", "拼色", "三花", "斑塊", "重點色"])
        color.widthAnchor.constraint(equalToConstant: 90).isActive = true
        secondary.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let edit = NSStackView(views: [parts, color, patterns, secondary,
            NSButton(title: "套用部位", target: self, action: #selector(applyPart))])
        edit.spacing = 7; stack.addArrangedSubview(edit)
        stack.addArrangedSubview(NSTextField(labelWithString: "依序為：部位、底色、花紋、花紋色。左右以正面畫面為準。"))
        status.textColor = .secondaryLabelColor; stack.addArrangedSubview(status)
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])
        rebuild(); selectPart()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 25, repeats: true) { [weak self] _ in self?.tick() }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func rebuild() {
        pet?.dispose(); greeting?.dispose(); hud?.hide()
        canvas?.removeFromSuperview(); meter?.removeFromSuperview()
        let appearance = configuration.appearance
        let view = DesktopPetView(resources: resources, appearance: appearance)
        view.frame.origin = CGPoint(x: 60, y: 12); stage.addSubview(view); canvas = view
        let source = configuration.imageData.flatMap(NSImage.init(data:)) ?? NekoAppearance.catImage
        let image = configuration.image == nil ? source.flatMap { CatAppearanceArtwork(appearance).image($0, layout: .hud) } : source
        let recording = NekoRecordingView(image: image)
        recording.frame.origin = CGPoint(x: 365, y: 50); recording.update(state: .recording)
        stage.addSubview(recording); meter = recording
        greeting = CatOverlay(configuration: configuration)
        hud = NekoRecordingHUD(image: image)
        hud?.onCancel = { [weak self] in self?.hud?.hide() }; hud?.onFinish = { [weak self] in self?.hud?.hide() }
        pet = DesktopPetController(resources: resources, appearance: appearance, world: {
            DesktopPetWorld(areas: NSScreen.screens.map(\.visibleFrame), cursor: NSEvent.mouseLocation, idleSeconds: 16,
                            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        })
        pet?.setReleased(true)
        status.stringValue = "\(appearance.title) · 本機預覽 · 沒有啟用麥克風或網路 · 不修改正式 App 設定"
    }
    private func tick() {
        phase += 1 / 25
        canvas?.pose = selectedPose; canvas?.phase = phase.truncatingRemainder(dividingBy: 3.2)
        canvas?.walkDistance = CGFloat(phase * 22)
        if selectedPose == .carried {
            let cycle = phase.truncatingRemainder(dividingBy: 3.0)
            canvas?.lift.spriteFrame = DesktopPetLift.travel(from: 0, to: 31, elapsed: cycle)
        } else { canvas?.lift = DesktopPetLift() }
        canvas?.needsDisplay = true
        meter?.updateMeter(decibels: Float(-24 + sin(phase * 4) * 10), elapsed: phase)
    }
    @objc private func selectPreset() {
        configuration = CatConfiguration.defaults.replacingAppearance(CatAppearance.makePreset(CatAppearance.presetIDs[presets.indexOfSelectedItem])!)
        rebuild(); selectPart()
    }
    @objc private func selectPose() { selectedPose = DesktopPetPose.allCases[poses.indexOfSelectedItem]; phase = 0 }
    @objc private func selectPart() {
        let style = configuration.appearance[CatBodyPart.allCases[parts.indexOfSelectedItem]]
        color.stringValue = style.color; secondary.stringValue = style.patternColor
        patterns.selectItem(at: CatPattern.allCases.firstIndex(of: style.pattern)!)
    }
    @objc private func applyPart() {
        var object = configuration.appearance.jsonObject
        var values = object["parts"] as! [String: [String: String]]
        values[CatBodyPart.allCases[parts.indexOfSelectedItem].rawValue] = ["color": color.stringValue, "pattern": CatPattern.allCases[patterns.indexOfSelectedItem].rawValue, "patternColor": secondary.stringValue]
        object["parts"] = values
        do { configuration = configuration.replacingAppearance(try CatAppearance.parse(object)); rebuild() }
        catch { status.stringValue = "請輸入 #RRGGBB 顏色，例如 #F4EFE5。" }
    }
    @objc private func importConfig() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = examplesURL
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let loaded = CatConfiguration.load(from: url)
        guard loaded.loadError == nil else { status.stringValue = loaded.loadError!; return }
        configuration = loaded
        presets.selectItem(at: CatAppearance.presetIDs.firstIndex(of: loaded.appearance.preset)!)
        rebuild(); selectPart()
    }
    @objc private func openExamples() { NSWorkspace.shared.open(examplesURL) }
    @objc private func showGreeting() { greeting?.showGreeting() }
    @objc private func showHUD() { hud?.showPreview(shortcut: "本機毛色預覽") }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); pet?.dispose(); greeting?.dispose(); hud?.hide()
    }
}
