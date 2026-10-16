import AppKit
import ApplicationServices

/// Geometry only. Never captures pixels, reads file contents, or moves icons.
final class DesktopPetDesktopReader {
    struct Snapshot {
        var perches: [DesktopPetPerch] = []
        var fullScreen = false
    }
    private let queue = DispatchQueue(label: "tw.panh.FreeVoiceType.pet-geometry", qos: .utility)
    private var pending = false
    private var lastFolders: TimeInterval = -.infinity
    private var cachedFolders: [DesktopPetPerch] = []
    private var generation = 0

    func cancel() { generation += 1 }

    func refresh(screens: [CGRect], primaryTop: CGFloat, completion: @escaping (Snapshot) -> Void) {
        precondition(Thread.isMainThread)
        guard !pending else { return }
        pending = true
        let token = generation
        let finderPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let readFolders = ProcessInfo.processInfo.systemUptime - lastFolders > 8
        let trusted = AXIsProcessTrusted()
        queue.async { [self] in
            if readFolders {
                cachedFolders = trusted && finderPID != nil
                    ? Self.folders(pid: finderPID!, primaryTop: primaryTop) : []
                lastFolders = ProcessInfo.processInfo.systemUptime
            }
            let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]) ?? []
            var covered: [CGRect] = []
            var fullScreen = false
            for window in windows {
                guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                      let layer = window[kCGWindowLayer as String] as? Int, (0...3).contains(layer),
                      (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                      let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                      let topLeft = CGRect(dictionaryRepresentation: bounds) else { continue }
                let frame = DesktopPetModel.appKitFrame(topLeft: topLeft, primaryScreenTop: primaryTop)
                covered.append(frame)
                if pid == frontPID, pid != finderPID,
                   screens.contains(where: { frame.intersection($0).width >= $0.width - 2 &&
                       frame.intersection($0).height >= $0.height - 2 }) { fullScreen = true }
            }
            let available = cachedFolders.filter { item in
                let footprint = CGRect(x: item.frame.midX - DesktopPetModel.size.width / 2,
                                       y: item.frame.maxY - DesktopPetModel.feetInset,
                                       width: DesktopPetModel.size.width, height: DesktopPetModel.size.height)
                return !covered.contains { $0.intersects(item.frame) || $0.intersects(footprint) }
            }
            let snapshot = Snapshot(perches: available, fullScreen: fullScreen)
            DispatchQueue.main.async { [self] in
                pending = false
                guard token == generation else { return }
                completion(snapshot)
            }
        }
    }

    private static func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key, &value) == .success ? value : nil
    }

    private static func folders(pid: pid_t, primaryTop: CGFloat) -> [DesktopPetPerch] {
        let finder = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(finder, 0.04)
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath()
        var result: [DesktopPetPerch] = []
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int, onDesktop: Bool) {
            guard depth <= 6, visited < 256 else { return }
            visited += 1
            let role = attribute(element, kAXRoleAttribute as CFString) as? String ?? ""
            // Finder's desktop is an application child scroll area, outside AXWindow.
            // Never traverse an open Finder folder window or its file list.
            guard role != (kAXWindowRole as String), role != (kAXMenuBarRole as String),
                  role != (kAXMenuRole as String) else { return }
            guard depth == 0 || role != (kAXApplicationRole as String) else { return }
            let isDesktop = onDesktop || role == (kAXScrollAreaRole as String)
            if isDesktop, role == (kAXImageRole as String),
               let rawURL = attribute(element, kAXURLAttribute as CFString),
               let url = (rawURL as? URL) ?? (rawURL as? String).flatMap(URL.init(string:)),
               url.isFileURL, url.deletingLastPathComponent().resolvingSymlinksInPath() == desktop,
               (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               let rawPosition = attribute(element, kAXPositionAttribute as CFString),
               let rawSize = attribute(element, kAXSizeAttribute as CFString),
               CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() {
                var point = CGPoint.zero, size = CGSize.zero
                if AXValueGetValue(rawPosition as! AXValue, .cgPoint, &point),
                   AXValueGetValue(rawSize as! AXValue, .cgSize, &size),
                   size.width > 0, size.height > 0, size.width < 250, size.height < 250 {
                    let rect = DesktopPetModel.appKitFrame(topLeft: CGRect(origin: point, size: size), primaryScreenTop: primaryTop)
                    // Geometry is sufficient identity; names/paths never leave this read.
                    let id = "\(rect.minX),\(rect.minY),\(rect.width),\(rect.height)"
                    result.append(DesktopPetPerch(id: id, frame: rect))
                }
            }
            for child in attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] {
                walk(child, depth: depth + 1, onDesktop: isDesktop)
            }
        }
        walk(finder, depth: 0, onDesktop: false)
        return result
    }
}
