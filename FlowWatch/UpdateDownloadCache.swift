import Foundation
import Network

@MainActor
final class UpdateDownloadCache: NSObject {
    typealias ProgressHandler = (Double?) -> Void
    typealias CompletionHandler = (Result<URL, Error>) -> Void

    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var destinationURL: URL?
    private var progressHandler: ProgressHandler?
    private var completionHandler: CompletionHandler?
    private var didMoveDownload = false

    func cachedFileURL(version: String, build: String) -> URL {
        let safeVersion = version.replacingOccurrences(of: "/", with: "-")
        let safeBuild = build.replacingOccurrences(of: "/", with: "-")
        return cacheDirectory
            .appendingPathComponent("FlowWatch-\(safeVersion)-\(safeBuild)")
            .appendingPathExtension("zip")
    }

    func existingFileURL(version: String, build: String, expectedLength: UInt64) -> URL? {
        let url = cachedFileURL(version: version, build: build)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if expectedLength > 0,
           let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           UInt64(size) != expectedLength {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    func download(
        from sourceURL: URL,
        version: String,
        build: String,
        expectedLength: UInt64,
        progress: @escaping ProgressHandler,
        completion: @escaping CompletionHandler
    ) {
        cancel()
        if let cached = existingFileURL(version: version, build: build, expectedLength: expectedLength) {
            progress(1)
            completion(.success(cached))
            return
        }

        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            completion(.failure(error))
            return
        }

        destinationURL = cachedFileURL(version: version, build: build)
        progressHandler = progress
        completionHandler = completion
        didMoveDownload = false

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 30 * 60
        let queue = OperationQueue()
        queue.name = "com.flowwatch.update-download"
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.downloadTask(with: sourceURL)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        progressHandler = nil
        completionHandler = nil
        destinationURL = nil
    }

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.hxd.FlowWatch", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    private func finish(_ result: Result<URL, Error>) {
        let completion = completionHandler
        task = nil
        session?.finishTasksAndInvalidate()
        session = nil
        progressHandler = nil
        completionHandler = nil
        destinationURL = nil
        completion?(result)
    }
}

extension UpdateDownloadCache: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress: Double? = totalBytesExpectedToWrite > 0
            ? min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1)
            : nil
        Task { @MainActor [weak self] in
            self?.progressHandler?(progress)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let stableTemporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowwatch-update-\(UUID().uuidString)")
            .appendingPathExtension("download")
        do {
            try FileManager.default.moveItem(at: location, to: stableTemporaryURL)
        } catch {
            Task { @MainActor [weak self] in
                self?.finish(.failure(error))
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let destinationURL = self.destinationURL else {
                try? FileManager.default.removeItem(at: stableTemporaryURL)
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: stableTemporaryURL, to: destinationURL)
                self.didMoveDownload = true
                self.finish(.success(destinationURL))
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.didMoveDownload else { return }
            self.finish(.failure(error))
        }
    }
}

final class CachedUpdateHTTPServer {
    private let queue = DispatchQueue(label: "com.flowwatch.update-cache-server", qos: .utility)
    private var listener: NWListener?
    private var fileURL: URL?
    private var readyHandlers: [(Result<URL, Error>) -> Void] = []
    private var localURL: URL?

    func start(fileURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.fileURL == fileURL, let localURL = self.localURL {
                completion(.success(localURL))
                return
            }
            self.stopLocked()
            self.fileURL = fileURL
            self.readyHandlers = [completion]
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in
                    self?.serve(connection)
                }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let port = listener?.port else { return }
                        let url = URL(string: "http://127.0.0.1:\(port.rawValue)/FlowWatch.zip")!
                        self.localURL = url
                        let handlers = self.readyHandlers
                        self.readyHandlers.removeAll()
                        handlers.forEach { $0(.success(url)) }
                    case .failed(let error):
                        let handlers = self.readyHandlers
                        self.readyHandlers.removeAll()
                        handlers.forEach { $0(.failure(error)) }
                        self.stopLocked()
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            } catch {
                let handlers = readyHandlers
                readyHandlers.removeAll()
                handlers.forEach { $0(.failure(error)) }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    private func stopLocked() {
        listener?.cancel()
        listener = nil
        fileURL = nil
        localURL = nil
        readyHandlers.removeAll()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, error in
            guard let self, error == nil, let data, let fileURL = self.fileURL else {
                connection.cancel()
                return
            }
            self.sendFile(fileURL, requestData: data, over: connection)
        }
    }

    private func sendFile(_ fileURL: URL, requestData: Data, over connection: NWConnection) {
        guard let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            sendError(404, over: connection)
            return
        }
        let request = String(decoding: requestData, as: UTF8.self)
        let rangeStart = parsedRangeStart(from: request, fileSize: UInt64(fileSize))
        let contentLength = UInt64(fileSize) - rangeStart
        try? handle.seek(toOffset: rangeStart)
        let status = rangeStart > 0 ? "206 Partial Content" : "200 OK"
        var headers = "HTTP/1.1 \(status)\r\nContent-Type: application/zip\r\nAccept-Ranges: bytes\r\nContent-Length: \(contentLength)\r\n"
        if rangeStart > 0 {
            headers += "Content-Range: bytes \(rangeStart)-\(UInt64(fileSize) - 1)/\(fileSize)\r\n"
        }
        headers += "Connection: close\r\n\r\n"
        connection.send(content: Data(headers.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            self?.sendNextChunk(handle: handle, over: connection)
        })
    }

    private func sendNextChunk(handle: FileHandle, over connection: NWConnection) {
        let chunk = (try? handle.read(upToCount: 256 * 1024)) ?? nil
        guard let chunk, !chunk.isEmpty else {
            try? handle.close()
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            self?.sendNextChunk(handle: handle, over: connection)
        })
    }

    private func parsedRangeStart(from request: String, fileSize: UInt64) -> UInt64 {
        guard let rangeLine = request.split(separator: "\n").first(where: { $0.lowercased().hasPrefix("range:") }),
              let markerRange = rangeLine.range(of: "bytes="),
              let value = UInt64(rangeLine[markerRange.upperBound...].split(separator: "-").first ?? "") else {
            return 0
        }
        return min(value, fileSize)
    }

    private func sendError(_ code: Int, over connection: NWConnection) {
        let response = "HTTP/1.1 \(code) Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
