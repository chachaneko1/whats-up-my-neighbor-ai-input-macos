import Foundation
import Network

/// Where a person takes over the agent's desktop. Hosts and ports are fixed here;
/// the only user input is an existing ssh_config alias, validated by SSHTunnelConfiguration.
enum RemoteDesktopTarget: Equatable {
    case linuxVPS(hostAlias: String)
    case macSecondUser

    static let vpsLocalPort = 15901
    static let remoteVNCPort = 5901
    static let secondUserPort = 5901

    var probePort: Int {
        switch self {
        case .linuxVPS: return Self.vpsLocalPort
        case .macSecondUser: return Self.secondUserPort
        }
    }

    var viewerURL: URL { URL(string: "vnc://127.0.0.1:\(probePort)")! }

    var tunnelConfiguration: SSHTunnelConfiguration? {
        guard case .linuxVPS(let alias) = self else { return nil }
        return SSHTunnelConfiguration(hostAlias: alias, localPort: Self.vpsLocalPort, remotePort: Self.remoteVNCPort)
    }

    /// Loopback only, one of our fixed ports, no credentials, path or query.
    static func isAllowedViewerURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "vnc" && parts.host == "127.0.0.1"
            && [vpsLocalPort, secondUserPort].contains(parts.port ?? -1)
            && parts.user == nil && parts.password == nil
            && parts.path.isEmpty && parts.query == nil && parts.fragment == nil
    }
}

/// The 12-byte ProtocolVersion message every RFB (VNC) server sends first: "RFB xxx.yyy\n".
enum RFBBanner {
    static let length = 12

    static func isValid(_ data: Data) -> Bool {
        let bytes = Array(data)
        guard bytes.count == length, Array(bytes[0...3]) == Array("RFB ".utf8),
              bytes[7] == UInt8(ascii: "."), bytes[11] == UInt8(ascii: "\n") else { return false }
        return [4, 5, 6, 8, 9, 10].allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[$0]) }
    }
}

protocol VNCServerProbing: AnyObject {
    /// One attempt. Completion runs on the main thread at most once; the returned
    /// closure cancels the attempt without calling completion.
    func probe(port: Int, timeout: TimeInterval, completion: @escaping (Bool) -> Void) -> () -> Void
}

/// Connects to 127.0.0.1 only, reads the server's banner and disconnects.
/// Sends nothing and never authenticates.
final class SystemVNCProbe: VNCServerProbing {
    private let queue = DispatchQueue(label: "tw.panh.neighbor.vnc-probe")

    private final class Attempt {
        let connection: NWConnection
        var finished = false // queue-confined
        init(connection: NWConnection) { self.connection = connection }
    }

    func probe(port: Int, timeout: TimeInterval, completion: @escaping (Bool) -> Void) -> () -> Void {
        guard (1024...65535).contains(port), let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            DispatchQueue.main.async { completion(false) }
            return {}
        }
        let attempt = Attempt(connection: NWConnection(host: "127.0.0.1", port: endpointPort, using: .tcp))
        let finish: (Bool?) -> Void = { result in // nil = cancelled, no callback
            guard !attempt.finished else { return }
            attempt.finished = true
            attempt.connection.stateUpdateHandler = nil
            attempt.connection.cancel()
            if let result { DispatchQueue.main.async { completion(result) } }
        }
        attempt.connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                attempt.connection.receive(minimumIncompleteLength: RFBBanner.length,
                                           maximumLength: RFBBanner.length) { data, _, _, error in
                    finish(error == nil && data.map(RFBBanner.isValid) == true)
                }
            // Refused connections surface as .waiting; do not let NWConnection retry.
            case .waiting, .failed, .cancelled: finish(false)
            default: break
            }
        }
        attempt.connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        return { [queue] in queue.async { finish(nil) } }
    }
}

protocol RemoteViewerLaunching: AnyObject {
    /// Completion runs on the main thread exactly once.
    func open(_ url: URL, completion: @escaping (Bool) -> Void)
}

/// Opens the built-in Screen Sharing app. No shell, no credentials in the URL.
final class ScreenSharingLauncher: RemoteViewerLaunching {
    static let bundleIdentifier = "com.apple.ScreenSharing"

    func open(_ url: URL, completion: @escaping (Bool) -> Void) {
        guard RemoteDesktopTarget.isAllowedViewerURL(url) else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", Self.bundleIdentifier, url.absoluteString]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { ended in
            let succeeded = ended.terminationStatus == 0
            DispatchQueue.main.async { completion(succeeded) }
        }
        do { try process.run() }
        catch { DispatchQueue.main.async { completion(false) } }
    }
}

enum RemoteDesktopHandoffState: Equatable {
    case idle, openingTunnel, probing, openingViewer, viewerOpened, stopped, failed(String)

    var isActive: Bool {
        switch self {
        case .openingTunnel, .probing, .openingViewer, .viewerOpened: return true
        case .idle, .stopped, .failed: return false
        }
    }
}

enum RemoteDesktopHandoffError: LocalizedError {
    case alreadyActive
    var errorDescription: String? { "接手控制已在進行中，請先結束。" }
}

/// Opens a viewer only after the forwarded port answers with an RFB banner.
/// A running SSH process alone never counts as a reachable VNC server.
final class RemoteDesktopHandoffController {
    static let probeDeadline: TimeInterval = 10
    static let probeInterval: TimeInterval = 0.5
    static let probeAttemptTimeout: TimeInterval = 2

    static let tunnelFailedMessage = "SSH 通道沒有建立成功或已結束。請檢查 SSH 別名、金鑰登入與主機指紋後，再按一次「接手控制」。"
    static let tunnelLostMessage = "SSH 通道已中斷，螢幕共享畫面會停止。請確認連線後再按一次「接手控制」。"
    static let viewerFailedMessage = "無法開啟「螢幕共享」。請確認系統內建 App 可用後再試。"
    static func probeTimeoutMessage(for target: RemoteDesktopTarget) -> String {
        let lead = "找不到 VNC 伺服器：127.0.0.1:\(target.probePort) 在 10 秒內沒有回應 VNC 訊號。"
        switch target {
        case .linuxVPS: return lead + "請確認遠端已啟動 VNC 伺服器，並檢查 SSH 別名與主機指紋。"
        case .macSecondUser: return lead + "請確認第二使用者已登入，且 VNC 伺服器已啟動並只允許本機連線。"
        }
    }

    private(set) var state: RemoteDesktopHandoffState = .idle
    private(set) var target: RemoteDesktopTarget?
    var onStateChange: ((RemoteDesktopHandoffState) -> Void)?

    private let makeTunnel: () -> SSHTunnelController
    private let prober: VNCServerProbing
    private let launcher: RemoteViewerLaunching
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private let now: () -> Date
    private var tunnel: SSHTunnelController?
    private var generation: UUID?
    private var cancelProbe: (() -> Void)?
    private var pendingRetry: DispatchWorkItem?

    init(makeTunnel: @escaping () -> SSHTunnelController = { SSHTunnelController() },
         prober: VNCServerProbing = SystemVNCProbe(),
         launcher: RemoteViewerLaunching = ScreenSharingLauncher(),
         schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = { delay, item in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
         },
         now: @escaping () -> Date = Date.init) {
        self.makeTunnel = makeTunnel
        self.prober = prober
        self.launcher = launcher
        self.schedule = schedule
        self.now = now
    }

    func start(_ target: RemoteDesktopTarget) throws {
        precondition(Thread.isMainThread)
        guard !state.isActive else { throw RemoteDesktopHandoffError.alreadyActive }
        let configuration = target.tunnelConfiguration
        // Reject a bad alias before any process exists or any state changes.
        if let configuration { _ = try configuration.arguments() }
        let token = UUID()
        generation = token
        self.target = target
        if let configuration {
            let next = makeTunnel()
            tunnel = next
            next.onStateChange = { [weak self] tunnelState in self?.tunnelChanged(tunnelState, generation: token) }
            transition(.openingTunnel)
            guard generation == token else { return }
            do { try next.start(configuration: configuration) }
            catch {
                if generation == token { end(.failed(Self.tunnelFailedMessage)) }
                return
            }
            guard generation == token, next.state == .processRunning else { return }
        }
        transition(.probing)
        attemptProbe(generation: token, deadline: now().addingTimeInterval(Self.probeDeadline))
    }

    func stop() {
        precondition(Thread.isMainThread)
        guard state.isActive else { return }
        end(.stopped)
    }

    private func attemptProbe(generation token: UUID, deadline: Date) {
        guard generation == token, state == .probing, let port = target?.probePort else { return }
        pendingRetry = nil
        let cancel = prober.probe(port: port, timeout: Self.probeAttemptTimeout) { [weak self] reachable in
            self?.probeFinished(reachable, generation: token, deadline: deadline)
        }
        // A probe may answer synchronously; keep the handle only while it is still pending.
        if generation == token, state == .probing, pendingRetry == nil { cancelProbe = cancel }
    }

    private func probeFinished(_ reachable: Bool, generation token: UUID, deadline: Date) {
        precondition(Thread.isMainThread)
        guard generation == token, state == .probing, let target else { return }
        cancelProbe = nil
        if reachable {
            openViewer(target.viewerURL, generation: token)
            return
        }
        guard now().addingTimeInterval(Self.probeInterval) < deadline else {
            end(.failed(Self.probeTimeoutMessage(for: target)))
            return
        }
        let retry = DispatchWorkItem { [weak self] in self?.attemptProbe(generation: token, deadline: deadline) }
        pendingRetry = retry
        schedule(Self.probeInterval, retry)
    }

    private func openViewer(_ url: URL, generation token: UUID) {
        transition(.openingViewer)
        launcher.open(url) { [weak self] opened in
            guard let self, self.generation == token, self.state == .openingViewer else { return }
            if opened { self.transition(.viewerOpened) } else { self.end(.failed(Self.viewerFailedMessage)) }
        }
    }

    private func tunnelChanged(_ tunnelState: SSHTunnelState, generation token: UUID) {
        guard generation == token, state.isActive else { return }
        switch tunnelState {
        case .failed, .stopped:
            end(.failed(state == .viewerOpened ? Self.tunnelLostMessage : Self.tunnelFailedMessage))
        case .idle, .starting, .processRunning:
            break
        }
    }

    private func end(_ next: RemoteDesktopHandoffState) {
        generation = nil
        pendingRetry?.cancel()
        pendingRetry = nil
        let cancel = cancelProbe
        cancelProbe = nil
        let previousTunnel = tunnel
        tunnel = nil
        previousTunnel?.onStateChange = nil
        cancel?()
        previousTunnel?.stop()
        transition(next)
    }

    private func transition(_ next: RemoteDesktopHandoffState) {
        state = next
        onStateChange?(next)
    }

    deinit {
        pendingRetry?.cancel()
        cancelProbe?()
        tunnel?.onStateChange = nil
        tunnel?.stop()
    }
}
