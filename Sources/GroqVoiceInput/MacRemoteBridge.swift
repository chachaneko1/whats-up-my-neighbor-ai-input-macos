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

    private lazy var localPeerID: MCPeerID = loadPeer(forKey: localPeerDefaultsKey) ?? makeAndSaveLocalPeer()
    private lazy var session = MCSession(
        peer: localPeerID,
        securityIdentity: nil,
        encryptionPreference: .required
    )
    private lazy var advertiser = MCNearbyServiceAdvertiser(
        peer: localPeerID,
        discoveryInfo: ["protocol": String(RemoteMessage.currentVersion)],
        serviceType: Self.serviceType
    )

    override init() {
        super.init()
    }

    func start() {
        session.delegate = self
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        notifyConnectionChange()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        session.disconnect()
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
        session.disconnect()
        UserDefaults.standard.removeObject(forKey: pairedPeerDefaultsKey)
        notifyConnectionChange()
    }

    var connectedPhoneName: String? {
        session.connectedPeers.first?.displayName
    }

    var hasPairedPhone: Bool {
        loadPeer(forKey: pairedPeerDefaultsKey) != nil
    }

    @discardableResult
    func send(_ message: RemoteMessage) -> Bool {
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
        if let connectedPhoneName {
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
        guard isPaired(peerID),
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
