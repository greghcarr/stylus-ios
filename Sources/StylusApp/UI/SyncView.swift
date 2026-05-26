import SwiftUI

// Multi-stage flow for pulling the user's library from a Mac
// running the desktop's SyncServer. Stages:
//   1. Discover (Bonjour browse for _stylus-sync._tcp)
//   2. Pair (6-digit PIN entry, sets bearer token on SyncClient)
//   3. Confirm (preflight: manifest size vs available disk)
//   4. Transfer (per-file progress)
//   5. Done / Failed
//
// All stages share one @StateObject so the view's local @State
// stays focused on UI selection (which peer is tapped, what PIN
// the user typed, etc.); the heavy lifting is in SyncBonjourBrowser
// / SyncClient / SyncDownloader.
struct SyncView: View
{
    @EnvironmentObject var folder:    MusicFolderStore
    @EnvironmentObject var playlists: PlaylistStore

    @StateObject private var browser = SyncBonjourBrowser()

    @State private var selectedPeer: SyncBonjourBrowser.Peer?
    @State private var pin:          String = ""
    @State private var client:       SyncClient?
    @State private var downloader:   SyncDownloader?
    @State private var stage:        Stage = .discovering
    @State private var statusMessage: String?
    @State private var transferTask:  Task<Void, Never>?
    // Set ~15 s after the discovery screen first appears if we
    // STILL have no peers. Drives the "Not finding your Mac?" hint
    // below the empty-state image.
    @State private var showDiscoveryHint: Bool = false
    @State private var discoveryHintTask: Task<Void, Never>?

    enum Stage
    {
        case discovering
        case pairing
        case confirming
        case transferring
        case done
        case failed
    }

    var body: some View
    {
        Group
        {
            switch stage
            {
            case .discovering:   discoveringView
            case .pairing:       pairingView
            case .confirming:    confirmingView
            case .transferring:  transferringView
            case .done:          doneView
            case .failed:        failedView
            }
        }
        .tabTitleMenu(AppTab.sync.title)
        .onAppear
        {
            browser.start()
            scheduleDiscoveryHint()
        }
        .onDisappear
        {
            browser.stop()
            transferTask?.cancel()
            discoveryHintTask?.cancel()
        }
    }

    // Flips showDiscoveryHint true after 15 s of empty-result
    // browsing so the user gets a checklist of likely fixes rather
    // than an infinite "Looking for your Mac…" screen.
    private func scheduleDiscoveryHint()
    {
        discoveryHintTask?.cancel()
        showDiscoveryHint = false
        discoveryHintTask = Task
        {
            try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
            await MainActor.run
            {
                if browser.peers.isEmpty && stage == .discovering
                {
                    showDiscoveryHint = true
                }
            }
        }
    }

    // MARK: - Stage 1: Discovering

    @ViewBuilder
    private var discoveringView: some View
    {
        if browser.peers.isEmpty
        {
            EmptyStateView(
                title:       "Looking for your Mac\u{2026}",
                systemImage: "wifi",
                message: showDiscoveryHint
                    ? "Still not seeing it? Make sure Stylus is open on your Mac, \u{201C}Allow iPhone Sync\u{201D} is turned on in Preferences, and both devices are on the same Wi-Fi network. If you denied the local network prompt for Stylus, re-enable it in iOS Settings."
                    : "Open Stylus on your Mac and turn on \u{201C}Allow iPhone Sync\u{201D} in Preferences. Both devices must be on the same Wi-Fi network."
            )
        }
        else
        {
            List
            {
                Section("Found")
                {
                    ForEach(browser.peers)
                    { peer in
                        Button
                        {
                            startPairing(with: peer)
                        }
                        label:
                        {
                            HStack
                            {
                                Image(systemName: "laptopcomputer")
                                    .foregroundStyle(.secondary)
                                Text(peer.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let err = browser.lastError
                {
                    Section
                    {
                        Text(err).foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Stage 2: Pairing

    @ViewBuilder
    private var pairingView: some View
    {
        VStack(spacing: 20)
        {
            Text("Enter PIN")
                .font(.title2.bold())
            if let peer = selectedPeer
            {
                Text("From \(peer.name)")
                    .foregroundStyle(.secondary)
            }
            TextField("123456", text: $pin)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .frame(maxWidth: 200)
                .onChange(of: pin)
                {
                    pin = String(pin.filter(\.isNumber).prefix(6))
                }

            if let msg = statusMessage
            {
                Text(msg).foregroundStyle(.red)
            }

            HStack
            {
                Button("Cancel") { reset() }
                    .buttonStyle(.bordered)
                Button("Pair")
                {
                    submitPin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pin.count != 6)
            }
        }
        .padding()
    }

    // MARK: - Stage 3: Confirming

    @ViewBuilder
    private var confirmingView: some View
    {
        VStack(spacing: 16)
        {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Ready to sync")
                .font(.title2.bold())
            if let msg = statusMessage
            {
                Text(msg).foregroundStyle(.secondary)
            }
            Button("Start sync")
            {
                startTransfer()
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel") { reset() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Stage 4: Transferring

    // Extracted into a child view so `@ObservedObject` can subscribe
    // to the downloader's @Published phase + bytes. `@State` on the
    // parent doesn't observe @Published changes on an
    // ObservableObject -- the parent re-renders only when the State
    // variable itself is reassigned, not when the object's internal
    // state mutates. Without this separation the progress UI froze
    // at the initial .idle phase ("Preparing\u{2026}", 0 of 0)
    // even while the actual sync was running underneath.
    @ViewBuilder
    private var transferringView: some View
    {
        if let downloader
        {
            TransferProgressView(downloader: downloader)
            {
                transferTask?.cancel()
            }
        }
        else
        {
            ProgressView()
                .padding()
        }
    }

    // MARK: - Stage 5: Done / Failed

    @ViewBuilder
    private var doneView: some View
    {
        VStack(spacing: 16)
        {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Sync complete")
                .font(.title2.bold())
            Button("Sync again") { reset() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    @ViewBuilder
    private var failedView: some View
    {
        VStack(spacing: 16)
        {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Sync failed")
                .font(.title2.bold())
            if let msg = statusMessage
            {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Try again") { reset() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Flow actions

    private func startPairing(with peer: SyncBonjourBrowser.Peer)
    {
        selectedPeer = peer
        pin           = ""
        statusMessage = nil
        stage         = .pairing
    }

    private func submitPin()
    {
        guard let peer = selectedPeer else { return }

        statusMessage = "Pairing…"
        Task
        {
            do
            {
                let resolved = try await browser.resolve(peer: peer)
                let c = SyncClient(host: resolved.host, port: resolved.port)
                try await c.pair(pin: pin)
                await MainActor.run
                {
                    client        = c
                    statusMessage = nil
                    stage         = .confirming
                }
            }
            catch SyncClient.Error.pair(let pairErr)
            {
                await MainActor.run
                {
                    statusMessage = pairErr.message
                }
            }
            catch
            {
                await MainActor.run
                {
                    statusMessage = "Couldn\u{2019}t pair: \(friendlyError(error))"
                }
            }
        }
    }

    private func startTransfer()
    {
        guard let client = client,
              let musicURL = folder.musicFolderURL
        else
        {
            statusMessage = "Pick a music folder first."
            stage         = .failed
            return
        }

        let dl = SyncDownloader(
            client:        client,
            musicRoot:     musicURL,
            podcastRoot:   folder.podcastFolderURL,
            playlistStore: playlists
        )
        downloader   = dl
        statusMessage = nil
        stage         = .transferring

        transferTask = Task
        {
            do
            {
                try await dl.run()
                await MainActor.run { stage = .done }
            }
            catch is CancellationError
            {
                await MainActor.run
                {
                    statusMessage = "Sync cancelled."
                    stage         = .failed
                }
            }
            catch SyncDownloader.Error.outOfDisk(let need, let have)
            {
                await MainActor.run
                {
                    statusMessage = "Not enough free space: needs \(byteCount(need)), available \(byteCount(have))."
                    stage         = .failed
                }
            }
            catch SyncDownloader.Error.versionMismatch(let serverVersion)
            {
                await MainActor.run
                {
                    statusMessage = "Your Mac is running a sync protocol version (\(serverVersion)) this iPhone app doesn\u{2019}t support. Update the iPhone app or the Mac app."
                    stage         = .failed
                }
            }
            catch SyncClient.Error.unauthorized
            {
                // Token revoked mid-session (server restart, manual
                // logout, lockout). Drop the client and send the
                // user back to the pairing screen with a brief note;
                // they re-enter the PIN and resumed-staging picks up
                // where the previous attempt left off.
                await MainActor.run
                {
                    self.client       = nil
                    self.pin          = ""
                    statusMessage     = "Session expired. Enter the PIN again to continue."
                    stage             = .pairing
                }
            }
            catch
            {
                await MainActor.run
                {
                    statusMessage = friendlyError(error)
                    stage         = .failed
                }
            }
        }
    }

    private func reset()
    {
        transferTask?.cancel()
        transferTask  = nil
        downloader    = nil
        client        = nil
        selectedPeer  = nil
        pin           = ""
        statusMessage = nil
        stage         = .discovering
    }

    // MARK: - Formatting

    private func byteCount(_ n: Int64) -> String
    {
        ByteCountFormatter.string(fromByteCount: n,
                                  countStyle: .file)
    }

    // Maps the most common URLError codes AND every SyncClient.Error
    // case to user-friendly text. Falls back to localizedDescription
    // only for unknown error types. Used by every catch site below
    // so the user never sees a raw "Stylus.SyncClient.Error error N"
    // string -- even if an explicit catch pattern above somehow
    // misses (build skew, unexpected propagation path).
    private func friendlyError(_ error: Error) -> String
    {
        if let urlErr = error as? URLError
        {
            switch urlErr.code
            {
            case .notConnectedToInternet:
                return "Your iPhone isn\u{2019}t connected to a Wi-Fi network."
            case .cannotConnectToHost:
                return "Couldn\u{2019}t reach your Mac. Make sure Stylus is open and Allow iPhone Sync is on."
            case .networkConnectionLost:
                return "Network dropped mid-transfer. Check Wi-Fi and try again."
            case .timedOut:
                return "Couldn\u{2019}t reach your Mac in time. Try again."
            case .cancelled:
                return "Sync cancelled."
            default:
                return urlErr.localizedDescription
            }
        }
        if let syncErr = error as? SyncClient.Error
        {
            switch syncErr
            {
            case .badRequest(let attempted):
                return "Couldn\u{2019}t build a valid request URL: \(attempted). The host returned by Bonjour isn\u{2019}t a legal URL host -- check your Mac\u{2019}s Computer Name in System Settings for apostrophes, spaces, or other special characters."
            case .badResponse:
                return "Got an unexpected response from your Mac."
            case .unauthorized:
                return "Session expired. Re-enter the PIN to continue."
            case .http(let status):
                return "Your Mac returned an error (HTTP \(status))."
            case .noToken:
                return "Not paired yet. Enter the PIN to continue."
            case .pair(let pairErr):
                return pairErr.message
            }
        }
        return error.localizedDescription
    }
}

// Child of SyncView's transferringView. Owns the @ObservedObject
// subscription to SyncDownloader so the progress UI updates live as
// the downloader transitions through .preflight -> .downloading
// (...) -> .swapping -> .writingPlaylists -> .done. The parent
// SyncView holds the actual SyncDownloader instance via @State so
// the object's lifecycle is parent-managed; we just observe.
private struct TransferProgressView: View
{
    @ObservedObject var downloader: SyncDownloader
    let onCancel: () -> Void

    var body: some View
    {
        VStack(spacing: 16)
        {
            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)
                .padding(.horizontal)

            Text(phaseLabel(downloader.phase))
                .font(.headline)
            Text(detailLabel(downloader.phase))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("\(byteCount(downloader.bytesReceived)) of \(byteCount(downloader.bytesTotal))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Cancel sync", action: onCancel)
                .buttonStyle(.bordered)
        }
        .padding()
    }

    private var progressFraction: Double
    {
        guard downloader.bytesTotal > 0 else { return 0 }
        return Double(downloader.bytesReceived) / Double(downloader.bytesTotal)
    }

    private func phaseLabel(_ phase: SyncDownloader.Phase) -> String
    {
        switch phase
        {
        case .idle:                 return "Preparing\u{2026}"
        case .preflight:            return "Checking free space\u{2026}"
        case .downloading(let i, let n, _):
                                    return "Downloading \(i) of \(n)"
        case .swapping:             return "Finalising files\u{2026}"
        case .writingPlaylists:     return "Updating playlists\u{2026}"
        case .done:                 return "Done"
        case .failed:               return "Failed"
        }
    }

    private func detailLabel(_ phase: SyncDownloader.Phase) -> String
    {
        if case .downloading(_, _, let name) = phase { return name }
        return ""
    }

    private func byteCount(_ n: Int64) -> String
    {
        ByteCountFormatter.string(fromByteCount: n,
                                  countStyle: .file)
    }
}
