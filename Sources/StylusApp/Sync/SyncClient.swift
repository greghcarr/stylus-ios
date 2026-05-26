import Foundation

// REST client for the desktop's SyncServer. Owns the bearer token
// issued by /v1/pair and stamps every subsequent request with
// Authorization: Bearer <token>. Each instance is bound to a single
// resolved peer (host, port); a new sync session spawns a new client.

actor SyncClient
{
    private let host: String
    private let port: Int
    private var token: String?
    private let session: URLSession

    init(host: String, port: Int)
    {
        self.host = host
        self.port = port

        // Standard ephemeral session: no cookies, no cache, no shared
        // credential storage. Bumped timeouts because file transfers
        // over LAN can stall briefly during disk writes.
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 6 * 60 * 60   // up to 6 h for a big library
        self.session = URLSession(configuration: cfg)
    }

    // Returns (URL?, attempted-string). The attempted-string is
    // always returned so callers can include it in Error.badRequest
    // for diagnostics even when the URL is nil. We try two
    // strategies because each handles a different host shape better:
    //
    //  1) URLComponents: handles regular hostnames + IPv6 (auto-
    //     brackets), percent-encodes anything questionable in the
    //     path / query. Returns nil if the host is structurally
    //     invalid (e.g. contains a space or apostrophe).
    //  2) Manual bracketed-IPv6 string fed to URL(string:): more
    //     permissive about hosts URLComponents rejects, useful when
    //     URLComponents rejects a host that URL(string:) would
    //     accept.
    //
    // Whichever URL we end up with, the attempted-string is the
    // human-readable form we wanted to fetch.
    private nonisolated func buildURLAndString(
        path:  String,
        query: [URLQueryItem] = []
    ) -> (URL?, String)
    {
        var components = URLComponents()
        components.scheme = "http"
        components.host   = host
        components.port   = port
        components.path   = path
        if !query.isEmpty { components.queryItems = query }
        let attempted = components.url?.absoluteString
                     ?? "http://\(host):\(port)\(path)"

        if let url = components.url { return (url, attempted) }

        let bracketedHost = host.contains(":") ? "[\(host)]" : host
        var base = "http://\(bracketedHost):\(port)\(path)"
        if !query.isEmpty
        {
            var c = URLComponents()
            c.queryItems = query
            if let q = c.url?.query, !q.isEmpty { base += "?" + q }
        }
        return (URL(string: base), base)
    }

    // PIN handshake. On 200 the response body carries a bearer token
    // we store on this client for the remainder of the session. On
    // 401 we surface the server's typed error (wrongPin / lockedOut)
    // so the UI can drive its retry / lockout messaging.
    func pair(pin: String) async throws -> Void
    {
        let body = try JSONEncoder().encode(["pin": pin])
        var req  = try request(path: "/v1/pair", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Error.badResponse }

        switch http.statusCode
        {
        case 200:
            let decoded = try JSONDecoder().decode(SyncPairResponse.self, from: data)
            token = decoded.token
        case 401:
            let parsed = (try? JSONDecoder().decode(SyncPairError.self, from: data))
                       ?? SyncPairError(code: "wrongPin", message: "Wrong PIN.")
            throw Error.pair(parsed)
        default:
            throw Error.http(http.statusCode)
        }
    }

    func fetchManifest() async throws -> SyncManifest
    {
        try requireToken()
        let req = try request(path: "/v1/manifest", method: "GET")
        let (data, response) = try await session.data(for: req)
        try checkHTTP(response)
        return try JSONDecoder().decode(SyncManifest.self, from: data)
    }

    func fetchPlaylists() async throws -> SyncPlaylistsPayload
    {
        try requireToken()
        let req = try request(path: "/v1/playlists", method: "GET")
        let (data, response) = try await session.data(for: req)
        try checkHTTP(response)
        return try JSONDecoder().decode(SyncPlaylistsPayload.self, from: data)
    }

    // Streams /v1/file?root=<root>&rel=<rel> to the given URL on disk
    // with optional byte-range resume. Returns the URL on success.
    // Caller is responsible for moving the file out of its temp
    // location and into final placement (see SyncDownloader).
    //
    // The function uses URLSession.download(for:) so the whole file
    // is streamed to disk rather than buffered in memory; appends a
    // Range header when resumeFromBytes is non-zero so the server
    // can replay from the right offset.
    func downloadFile(
        root:            FileRoot,
        rel:             String,
        to destination:  URL,
        resumeFromBytes: Int64 = 0
    ) async throws
    {
        try requireToken()

        let (urlMaybe, attempted) = buildURLAndString(
            path:  "/v1/file",
            query: [URLQueryItem(name: "root", value: root.rawValue),
                    URLQueryItem(name: "rel",  value: rel)]
        )
        guard let url = urlMaybe
        else { throw Error.badRequest(attempted: attempted) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
        if resumeFromBytes > 0
        {
            req.setValue("bytes=\(resumeFromBytes)-",
                         forHTTPHeaderField: "Range")
        }

        let (tempURL, response) = try await session.download(for: req)
        try checkHTTP(response, allow: [200, 206])

        // Append-or-rename: a 206 partial-content response carries
        // only the missing tail and must be appended to whatever is
        // already on disk at destination; a 200 is the whole file
        // and clobbers any partial.
        let http = response as? HTTPURLResponse
        if http?.statusCode == 206 && resumeFromBytes > 0
        {
            let handle = try FileHandle(forWritingTo: destination)
            try handle.seekToEnd()
            let data = try Data(contentsOf: tempURL)
            try handle.write(contentsOf: data)
            try handle.close()
            try? FileManager.default.removeItem(at: tempURL)
        }
        else
        {
            // Clean parent dir if missing, then move the temp file
            // into place (atomic on the same filesystem).
            let parent = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path)
            {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
        }
    }

    enum FileRoot: String, Sendable
    {
        case music
        case podcast
    }

    enum Error: Swift.Error, Sendable
    {
        // badRequest carries the URL string we tried to build, so the
        // user-facing error can show the actual offending host and
        // we can diagnose without a remote debugger. Common cause:
        // a Mac with spaces / apostrophes in its Computer Name that
        // NWConnection handed back as a "name" host instead of an IP.
        case badRequest(attempted: String)
        case badResponse
        // 401 returned by any post-pair endpoint -- token has been
        // invalidated (server restart, revokeAllTokens). Caller
        // should drop the client and route the user back to the
        // pairing stage rather than treat it as a generic HTTP error.
        case unauthorized
        case http(Int)
        case noToken
        case pair(SyncPairError)
    }

    // MARK: - Helpers

    private func request(path: String, method: String) throws -> URLRequest
    {
        let (urlMaybe, attempted) = buildURLAndString(path: path)
        guard let url = urlMaybe
        else { throw Error.badRequest(attempted: attempted) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private func requireToken() throws
    {
        if token == nil { throw Error.noToken }
    }

    private func checkHTTP(_ response: URLResponse, allow: Set<Int> = [200]) throws
    {
        guard let http = response as? HTTPURLResponse
        else { throw Error.badResponse }
        if !allow.contains(http.statusCode)
        {
            // 401 from a bearer-authed endpoint means our token was
            // revoked (server restart, manual logout, lockout).
            // Surface separately so SyncView can drop the client and
            // send the user back to the PIN screen.
            if http.statusCode == 401 { throw Error.unauthorized }
            throw Error.http(http.statusCode)
        }
    }
}
