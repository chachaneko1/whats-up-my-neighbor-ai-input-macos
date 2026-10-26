import AppKit

/// Transparent hit surface over the existing VNC viewer. Only the painted cat
/// receives mouse events, so the rest of the remote desktop stays usable.
final class VPSCatHostView: NSView {
    let artwork: DesktopPetView
    var acceptsCatInput = false {
        didSet { isHidden = !acceptsCatInput }
    }
    var followsRemoteDrag = false {
        didSet { artwork.alphaValue = followsRemoteDrag ? 0.001 : 1 }
    }

    init(appearance: CatAppearance) {
        artwork = DesktopPetView(appearance: appearance)
        super.init(frame: CGRect(origin: .zero, size: DesktopPetView.panelSize))
        wantsLayer = true
        artwork.frame = bounds
        artwork.autoresizingMask = [.width, .height]
        addSubview(artwork)
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard acceptsCatInput else { return nil }
        let local = artwork.convert(point, from: superview)
        return artwork.containsCat(local) ? artwork : nil
    }
}
