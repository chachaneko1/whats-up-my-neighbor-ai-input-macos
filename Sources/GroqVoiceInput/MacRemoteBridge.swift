import Foundation
@preconcurrency import MultipeerConnectivity

final class MacRemoteBridge: NSObject, @unchecked Sendable {
    static let serviceType = "groq-voice"

    var onMessage: ((RemoteMessage) -> Void)?
    var onConnectionChange: ((String) -> Void)?
    var onPairingComplete: ((String) -> Void)?

    private let localPeerDefaultsKey = "remote.localPeerID"
    private let pairedPeerDefaultsKey = "remote.pairedPeerID"
    private let pairingLock = NSLock()
    private var pairingCode: String?
    private var pairingExpiresAt: Date?

    /// 接力模式狀態與連線物件，一律由 `relayLock` 保護。
    ///
    /// 需要鎖的原因有兩個。其一，光是停止廣播還不夠：`stopAdvertisingPeer()`
    /// 之後仍可能有已經在路上的邀請進來，delegate 要能無條件拒絕，「關閉」才是
    /// 真的關閉。其二，delegate 回呼是在 MultipeerConnectivity 自己的執行緒上跑，
    /// 而開關接力模式是在主執行緒，兩者會同時碰這幾個變數。
    private let relayLock = NSLock()
    private var relayEnabled = false
    /// 只在接力模式開啟時存在。MultipeerConnectivity 在 `disconnect()` 之後重複
    /// 使用同一個 session 重連並不可靠，每次開啟都重建最單純也最好推理。
    private var relaySession: MCSession?
    private var relayAdvertiser: MCNearbyServiceAdvertiser?

    private lazy var localPeerID: MCPeerID = loadPeer(forKey: localPeerDefaultsKey) ?? makeAndSaveLocalPeer()

    override init() {
        super.init()
    }

    func start() {
        let newSession = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        newSession.delegate = self
        let newAdvertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: ["protocol": String(RemoteMessage.currentVersion)],
            serviceType: Self.serviceType
        )
        newAdvertiser.delegate = self

        relayLock.lock()
        relayEnabled = true
        relaySession = newSession
        relayAdvertiser = newAdvertiser
        relayLock.unlock()

        newAdvertiser.startAdvertisingPeer()
        notifyConnectionChange()
    }

    func stop() {
        relayLock.lock()
        relayEnabled = false
        let previousSession = relaySession
        let previousAdvertiser = relayAdvertiser
        relaySession = nil
        relayAdvertiser = nil
        relayLock.unlock()

        endPairing()
        previousAdvertiser?.stopAdvertisingPeer()
        previousAdvertiser?.delegate = nil
        previousSession?.disconnect()
        previousSession?.delegate = nil
        notifyConnectionChange()
    }

    /// 取得目前可用的 session，接力模式關閉時回傳 nil。
    ///
    /// 「檢查旗標」與「取得 session」必須在同一個鎖裡完成，否則兩步之間狀態可能
    /// 已經被切換，變成用一個剛被關閉的 session 繼續收送訊息。
    private func activeSession() -> MCSession? {
        relayLock.lock()
        defer { relayLock.unlock() }
        return relayEnabled ? relaySession : nil
    }

    private var isRelayEnabled: Bool {
        relayLock.lock()
        defer { relayLock.unlock() }
        return relayEnabled
    }

    func beginPairing(code: String, validFor seconds: TimeInterval = 300) {
        pairingLock.lock()
        pairingCode = code
        pairingExpiresAt = Date().addingTimeInterval(seconds)
        pairingLock.unlock()
    }

    func endPairing() {
        pairingLock.lock()
        pairingCode = nil
        pairingExpiresAt = nil
        pairingLock.unlock()
    }

    func forgetPairedPhone() {
        activeSession()?.disconnect()
        UserDefaults.standard.removeObject(forKey: pairedPeerDefaultsKey)
        notifyConnectionChange()
    }

    var connectedPhoneName: String? {
        activeSession()?.connectedPeers.first?.displayName
    }

    var hasPairedPhone: Bool {
        loadPeer(forKey: pairedPeerDefaultsKey) != nil
    }

    @discardableResult
    func send(_ message: RemoteMessage) -> Bool {
        guard let session = activeSession() else { return false }
        let peers = session.connectedPeers
        guard !peers.isEmpty,
              let data = try? RemoteMessageCodec.encode(message) else { return false }
        do {
            try session.send(data, toPeers: peers, with: .reliable)
            return true
        } catch {
            return false
        }
    }

    private func isValidPairingInvitation(_ invitation: PairingInvitation) -> Bool {
        pairingLock.lock()
        defer { pairingLock.unlock() }
        guard let pairingCode,
              let pairingExpiresAt,
              pairingExpiresAt > Date(),
              invitation.code == pairingCode else { return false }
        self.pairingCode = nil
        self.pairingExpiresAt = nil
        return true
    }

    private func makeAndSaveLocalPeer() -> MCPeerID {
        let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let peer = MCPeerID(displayName: String(name.prefix(63)))
        savePeer(peer, forKey: localPeerDefaultsKey)
        return peer
    }

    private func loadPeer(forKey key: String) -> MCPeerID? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data)
    }

    private func savePeer(_ peer: MCPeerID, forKey key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: peer, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func isPaired(_ peer: MCPeerID) -> Bool {
        loadPeer(forKey: pairedPeerDefaultsKey) == peer
    }

    private func notifyConnectionChange() {
        let status: String
        if !isRelayEnabled {
            status = "已停用"
        } else if let connectedPhoneName {
            status = "已連線：\(connectedPhoneName)"
        } else if hasPairedPhone {
            status = "已配對，等待 iPhone 連線"
        } else {
            status = "尚未配對"
        }
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChange?(status)
        }
    }
}

extension MacRemoteBridge: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // 接力模式關閉時一律拒絕。以前這裡對已配對的手機是零確認自動接受，
        // 等於 App 一開就永遠在等手機連進來，正是使用者回報的「沒同意就連上手機」。
        guard let session = activeSession() else {
            invitationHandler(false, nil)
            return
        }

        if isPaired(peerID) {
            invitationHandler(true, session)
            return
        }

        guard let context,
              let invitation = try? RemoteMessageCodec.decode(PairingInvitation.self, from: context),
              isValidPairingInvitation(invitation) else {
            invitationHandler(false, nil)
            return
        }

        savePeer(peerID, forKey: pairedPeerDefaultsKey)
        invitationHandler(true, session)
        DispatchQueue.main.async { [weak self] in
            self?.onPairingComplete?(peerID.displayName)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChange?("無法啟動附近連線：\(error.localizedDescription)")
        }
    }
}

extension MacRemoteBridge: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        notifyConnectionChange()
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard activeSession() != nil,
              isPaired(peerID),
              let message = try? RemoteMessageCodec.decode(RemoteMessage.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onMessage?(message)
        }
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}
