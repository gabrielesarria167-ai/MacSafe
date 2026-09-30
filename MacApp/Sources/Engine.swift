import Foundation

enum EngineError: LocalizedError {
    case noPython
    case missingScript
    case launchFailed(String)
    case http(Int, String)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .noPython:
            return "Python 3 wasn't found. Install it from python.org or run `xcode-select --install`."
        case .missingScript:
            return "engine.py is missing from the app bundle. Rebuild the app with build.sh."
        case .launchFailed(let why):
            return why
        case .http(_, let message):
            return message
        case .notRunning:
            return "The scanning engine isn't running."
        }
    }
}

/// Runs engine.py as a helper process and talks to its private localhost API.
/// The engine exits on its own when this app quits (it watches its stdin).
final class EngineClient: @unchecked Sendable {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var base: URL?
    private var token = ""
    private let session: URLSession
    private let decoder: JSONDecoder

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/MacSafe/engine.log")

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 900
        cfg.timeoutIntervalForResource = 3600
        session = URLSession(configuration: cfg)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    static func findPython() -> String? {
        let candidates = [
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func launch() async throws {
        guard let python = Self.findPython() else { throw EngineError.noPython }
        guard let script = Bundle.main.path(forResource: "engine", ofType: "py") else { throw EngineError.missingScript }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = [script, "serve"]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        let out = Pipe()
        let inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        p.standardError = Self.openLog()
        try p.run()
        process = p
        stdinPipe = inp

        let line = try await Self.readLine(out.fileHandleForReading)
        struct Handshake: Decodable { let port: Int; let token: String }
        guard let hs = try? JSONDecoder().decode(Handshake.self, from: Data(line.utf8)) else {
            throw EngineError.launchFailed("The engine didn't start correctly. Details are in \(Self.logURL.path).")
        }
        base = URL(string: "http://127.0.0.1:\(hs.port)/api/")
        token = hs.token
    }

    func stop() {
        process?.terminate()
    }

    /// Appends (the engine also writes its own errors here), so earlier failures survive a relaunch.
    private static func openLog() -> FileHandle? {
        let dir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
        let fd = open(logURL.path, O_WRONLY | O_CREAT | O_APPEND | (size > 1_000_000 ? O_TRUNC : 0), 0o644)
        return fd < 0 ? nil : FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    private static func readLine(_ fh: FileHandle) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()
                while true {
                    let chunk = fh.availableData
                    if chunk.isEmpty {
                        cont.resume(throwing: EngineError.launchFailed(
                            "The engine stopped while starting. Details are in \(logURL.path)."))
                        return
                    }
                    buffer.append(chunk)
                    if let nl = buffer.firstIndex(of: 0x0A) {
                        cont.resume(returning: String(decoding: buffer[..<nl], as: UTF8.self))
                        return
                    }
                }
            }
        }
    }

    // MARK: requests

    func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        guard let base else { throw EngineError.notRunning }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.setValue(token, forHTTPHeaderField: "X-Token")
        return try await send(req)
    }

    func post<T: Decodable>(_ path: String, _ body: [String: Any] = [:]) async throws -> T {
        guard let base else { throw EngineError.notRunning }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-Token")
        return try await send(req)
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Engine error (HTTP \(code))"
            throw EngineError.http(code, message)
        }
        return try decoder.decode(T.self, from: data)
    }
}
