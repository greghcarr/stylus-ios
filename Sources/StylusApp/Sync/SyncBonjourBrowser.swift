import Foundation
import Network

// Thread-safe single-shot flag used by resolve() to make sure a
// CheckedContinuation gets resumed exactly once across the multiple
// callbacks that can fire on it (.ready, .failed, .cancelled, and
// the timeout). Lifts the previous `var resumed = false` captured by
// reference, which the Swift 6 strict-concurrency checker (and
// reality) flagged as a data race risk -- NWConnection's state
// updates and our asyncAfter timer can race even when both fire on
// the main queue, because asyncAfter is allowed to run later within
// the same runloop tick.
private final class ResolveOnce: @unchecked Sendable
{
    private let lock = NSLock()
    private var fired = false

    // Returns true exactly once; subsequent calls return false.
    func fire() -> Bool
    {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

// Browses the local network for Mac peers advertising the
// `_stylus-sync._tcp` Bonjour service from the desktop's SyncServer.
// Wraps NWBrowser (the Network framework's modern replacement for
// NetServiceBrowser) so the SwiftUI sync view can render a live
// list of peers without touching low-level callbacks itself.
//
// NWBrowser surfaces results as full NWEndpoint values; each
// NWEndpoint.service result is then resolved to (host, port) by
// opening an NWConnection to it -- this is the recommended
// post-deprecation path on iOS 13+. We intentionally don't ship
// the raw NWBrowser.Result outside this class; the SyncView
// consumes a stable Peer struct that carries everything the next
// step (PIN handshake) needs.

@MainActor
final class SyncBonjourBrowser: ObservableObject
{
    @Published private(set) var peers:     [Peer]      = []
    @Published private(set) var isBrowsing: Bool       = false
    @Published private(set) var lastError: String?     = nil

    private var browser: NWBrowser?
    // NWBrowser results are NWEndpoint values; the same service can
    // be re-advertised under the same name multiple times. Track by
    // service-name string so we dedupe and update on changes.
    private var seenByName: [String: Peer] = [:]

    struct Peer: Identifiable, Equatable, Sendable
    {
        let name: String          // Bonjour service name, user-readable
        let host: String          // resolved IPv4 or IPv6 literal, or hostname.local
        let port: Int
        var id: String { name }
    }

    func start()
    {
        guard browser == nil else { return }
        lastError = nil

        let descriptor = NWBrowser.Descriptor.bonjour(
            type:    "_stylus-sync._tcp",
            domain:  nil
        )
        let params = NWParameters()
        params.includePeerToPeer = true

        let b = NWBrowser(for: descriptor, using: params)
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleState(state)
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handleResults(results)
            }
        }
        b.start(queue: .main)
        browser = b
        isBrowsing = true
    }

    func stop()
    {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    private func handleState(_ state: NWBrowser.State)
    {
        switch state
        {
        case .failed(let err):
            lastError  = err.localizedDescription
            isBrowsing = false
        case .cancelled:
            isBrowsing = false
        default:
            break
        }
    }

    private func handleResults(_ results: Set<NWBrowser.Result>)
    {
        // Take the current results set as the new truth -- anything
        // missing this time has gone away.
        var next: [String: Peer] = [:]
        for r in results
        {
            guard case .service(let name, _, _, _) = r.endpoint else { continue }
            // Reuse any prior resolution rather than re-resolving on
            // every snapshot; resolution writes once and stays.
            if let existing = seenByName[name]
            {
                next[name] = existing
                continue
            }
            // Stub a Peer entry with the service name; (host, port)
            // gets filled in when the user taps to pair. We resolve
            // on-demand instead of eagerly because Bonjour resolution
            // requires a connection attempt under iOS 14+'s privacy
            // rules and that triggers the system permission prompt
            // -- holding it for tap-time keeps the discovery list
            // permission-free.
            let placeholder = Peer(name: name, host: "", port: 0)
            next[name]   = placeholder
        }
        seenByName = next
        peers = Array(next.values).sorted { $0.name < $1.name }
    }

    // Resolve a discovered service name to (host, port) by opening
    // an NWConnection to it and reading the resolved endpoint. The
    // connection is torn down immediately afterwards -- this is the
    // standard post-NSNetService resolution dance on modern iOS.
    //
    // Hard 10 s deadline: an NWConnection to a vanished mDNS record
    // can sit in .preparing forever, neither firing .ready nor
    // .failed, which would leave the awaiting Task wedged. The
    // timeout fires regardless and resumes with URLError(.timedOut).
    func resolve(peer: Peer) async throws -> Peer
    {
        if !peer.host.isEmpty { return peer }

        let endpoint = NWEndpoint.service(
            name:   peer.name,
            type:   "_stylus-sync._tcp",
            domain: "local.",
            interface: nil
        )
        let conn = NWConnection(to: endpoint, using: .tcp)
        let once = ResolveOnce()

        let resolved: (String, Int) = try await withCheckedThrowingContinuation
        { continuation in
            conn.stateUpdateHandler = { state in
                switch state
                {
                case .ready:
                    if case .hostPort(let host, let port) = conn.currentPath?.remoteEndpoint,
                       once.fire()
                    {
                        continuation.resume(returning: (
                            Self.hostString(host),
                            Int(port.rawValue)
                        ))
                    }
                case .failed(let err):
                    if once.fire() { continuation.resume(throwing: err) }
                case .cancelled:
                    if once.fire() { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            conn.start(queue: .main)

            DispatchQueue.main.asyncAfter(deadline: .now() + 10)
            {
                if once.fire()
                {
                    conn.cancel()
                    continuation.resume(throwing: URLError(.timedOut))
                }
            }
        }
        conn.cancel()

        let updated = Peer(name: peer.name, host: resolved.0, port: resolved.1)
        seenByName[peer.name] = updated
        if let i = peers.firstIndex(where: { $0.id == peer.id })
        {
            peers[i] = updated
        }
        return updated
    }

    // nonisolated because it's called from inside NWConnection's
    // stateUpdateHandler closure, which runs off the main actor
    // (queue is .main but the closure itself isn't @MainActor).
    // The function is pure -- no instance state -- so nonisolated
    // is the right escape.
    private nonisolated static func hostString(_ host: NWEndpoint.Host) -> String
    {
        // Return host strings WITHOUT brackets even for IPv6 -- URL
        // building wraps them itself, and an IPv6 like `fe80::1%en0`
        // would otherwise compose to `[fe80::1%en0]` which URL won't
        // parse. Zone identifiers (the `%en0` tail) need to be
        // stripped from BOTH IPv4 and IPv6 forms: Network framework
        // attaches the resolving interface as a zone on either
        // family when the address came back interface-scoped, and
        // the resulting `%` makes URL parsing fail. Letting the OS
        // pick the route for a globally-routable LAN address (e.g.
        // 192.168.x.y) is almost always what we want anyway.
        switch host
        {
        case .name(let n, _):   return stripZone(n)
        case .ipv4(let v4):     return stripZone("\(v4)")
        case .ipv6(let v6):     return stripZone("\(v6)")
        @unknown default:       return ""
        }
    }

    private nonisolated static func stripZone(_ s: String) -> String
    {
        if let pct = s.firstIndex(of: "%") { return String(s[..<pct]) }
        return s
    }
}
