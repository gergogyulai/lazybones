import Foundation

/// Control of an LG webOS TV over its LAN API (SSAP over WebSocket, the protocol LG's own phone
/// app uses). Macs can't send HDMI-CEC, so this is how Lull reaches the TV's volume, which also
/// drives an ARC soundbar, and its power.
@MainActor
public final class TVLink: ObservableObject {
    public enum Status: Equatable, Sendable {
        case off, connecting, pairing, connected
        case failed(String)
    }

    @Published public private(set) var status = Status.off
    @Published public private(set) var volume: Int?
    @Published public private(set) var muted: Bool?
    /// e.g. "tv_speaker", "external_arc".
    @Published public private(set) var soundOutput: String?

    /// Called on any volume, mute or connection change.
    public var onChange: (() -> Void)?
    /// Called when the TV issues a client key, so it can be saved.
    public var onPaired: ((String) -> Void)?

    public private(set) var config: TVConfig?
    public var name: String { config?.name ?? "TV" }

    private let certificateTrust = TrustTVCertificate()
    private lazy var session = URLSession(configuration: .default, delegate: certificateTrust, delegateQueue: .main)
    private var socket: URLSessionWebSocketTask?
    private var generation = 0
    private var nextID = 0
    private var retry: Task<Void, Never>?
    private var pinger: Task<Void, Never>?

    public init() {}

    // MARK: Configuration

    /// Connects to `config`'s TV, or disconnects when nil. Saving a new client key for the same TV
    /// doesn't reconnect.
    public func configure(_ new: TVConfig?) {
        let reconnect = new?.host != config?.host
        config = new
        certificateTrust.host = new?.host
        if reconnect { connect() }
    }

    public func connect() {
        disconnect()
        guard config != nil else { return }
        open(secure: true)
    }

    public func disconnect() {
        generation += 1
        retry?.cancel()
        pinger?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        volume = nil
        muted = nil
        soundOutput = nil
        setStatus(.off)
    }

    // MARK: Commands

    /// One volume step of 1, like the TV's own remote. Relative steps also work for soundbars on
    /// ARC or optical, which don't accept an absolute volume.
    public func stepVolume(up: Bool) {
        if let v = volume { volume = min(100, max(0, v + (up ? 1 : -1))) }
        request(up ? "audio/volumeUp" : "audio/volumeDown")
        muted = false
        onChange?()
    }

    public func setMuted(_ mute: Bool) {
        muted = mute
        request("audio/setMute", ["mute": mute])
        onChange?()
    }

    public func turnOff() { request("system/turnOff") }

    // MARK: Connection

    /// Newer firmware only accepts wss on 3001 (self-signed); older only ws on 3000.
    private func open(secure: Bool) {
        guard let config else { return }
        generation += 1
        let gen = generation
        setStatus(.connecting)
        let url = URL(string: secure ? "wss://\(config.host):3001" : "ws://\(config.host):3000")!
        let task = session.webSocketTask(with: url)
        socket = task
        task.resume()
        receive(on: task, generation: gen, secure: secure, gotMessage: false)

        var payload = registration
        if let key = config.clientKey { payload["client-key"] = key }
        send(["type": "register", "id": "register", "payload": payload])
    }

    private func receive(on task: URLSessionWebSocketTask, generation gen: Int, secure: Bool, gotMessage: Bool) {
        task.receive { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, gen == self.generation else { return }
                switch result {
                case let .success(message):
                    if case let .string(text) = message,
                       let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.handle(json)
                    }
                    self.receive(on: task, generation: gen, secure: secure, gotMessage: true)
                case let .failure(error):
                    if secure && !gotMessage {
                        self.open(secure: false)
                    } else {
                        self.failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func failed(_ reason: String) {
        socket?.cancel()
        socket = nil
        pinger?.cancel()
        volume = nil
        muted = nil
        setStatus(.failed(reason))
        // The TV may just be off; keep trying quietly.
        let gen = generation
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled, gen == self.generation else { return }
            self.open(secure: true)
        }
    }

    private func handle(_ msg: [String: Any]) {
        let type = msg["type"] as? String
        let id = msg["id"] as? String
        let payload = msg["payload"] as? [String: Any] ?? [:]

        switch (id, type) {
        case ("register", "response"):
            if payload["pairingType"] as? String == "PROMPT" { setStatus(.pairing) }
        case ("register", "registered"):
            if let key = payload["client-key"] as? String, key != config?.clientKey {
                config?.clientKey = key
                onPaired?(key)
            }
            setStatus(.connected)
            subscribe("sub-volume", "audio/getVolume")
            subscribe("sub-output", "com.webos.service.apiadapter/audio/getSoundOutput")
            startPinging()
        case ("register", "error"):
            failed(msg["error"] as? String ?? "Pairing was declined")
        case ("sub-volume", _):
            let status = payload["volumeStatus"] as? [String: Any] ?? payload
            if let v = status["volume"] as? Int { volume = v }
            if let m = (status["muteStatus"] ?? status["muted"] ?? status["mute"]) as? Bool { muted = m }
            if let o = status["soundOutput"] as? String { soundOutput = o }
            onChange?()
        case ("sub-output", _):
            if let o = payload["soundOutput"] as? String { soundOutput = o }
            onChange?()
        default: break
        }
    }

    private func startPinging() {
        pinger?.cancel()
        let gen = generation
        pinger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self, gen == self.generation, let socket = self.socket else { return }
                socket.sendPing { [weak self] error in
                    guard let error else { return }
                    DispatchQueue.main.async {
                        guard let self, gen == self.generation else { return }
                        self.failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func request(_ uri: String, _ payload: [String: Any] = [:]) {
        guard status == .connected else { return }
        nextID += 1
        send(["type": "request", "id": "req-\(nextID)", "uri": "ssap://\(uri)", "payload": payload])
    }

    private func subscribe(_ id: String, _ uri: String) {
        send(["type": "subscribe", "id": id, "uri": "ssap://\(uri)", "payload": [:] as [String: Any]])
    }

    private func send(_ msg: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: msg),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    private func setStatus(_ s: Status) {
        guard status != s else { return }
        status = s
        onChange?()
    }

    /// The permissions LG's pairing prompt asks the user to grant.
    private let registration: [String: Any] = [
        "forcePairing": false,
        "pairingType": "PROMPT",
        "manifest": [
            "appVersion": "1.1",
            "manifestVersion": 1,
            "permissions": ["CONTROL_AUDIO", "CONTROL_POWER", "READ_POWER_STATE", "READ_SETTINGS"],
        ] as [String: Any],
    ]
}

/// webOS serves a self-signed certificate on 3001. It's accepted for the paired TV's address only.
private final class TrustTVCertificate: NSObject, URLSessionDelegate, @unchecked Sendable {
    var host: String?

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           space.host == host, let trust = space.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
