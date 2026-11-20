import Foundation

final class StatusWriter {
    private let url: URL
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "RemoteVibe.status", qos: .utility)
    private let formatter = ISO8601DateFormatter()
    private var pendingWork: DispatchWorkItem?
    private var latestStatus: [String: Any]?
    private var lastSnapshot: Data?

    init(url: URL, debounceInterval: TimeInterval = 0.15) {
        self.url = url
        self.debounceInterval = debounceInterval
    }

    func schedule(_ status: [String: Any]) {
        queue.async { [weak self] in
            guard let self else { return }
            self.latestStatus = status
            guard self.pendingWork == nil else { return }
            if self.debounceInterval <= 0 {
                self.commitLatest()
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingWork = nil
                self.commitLatest()
            }
            self.pendingWork = work
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: work)
        }
    }

    func flushSync(_ status: [String: Any]? = nil) {
        queue.sync {
            pendingWork?.cancel()
            pendingWork = nil
            if let status { latestStatus = status }
            commitLatest()
        }
    }

    private func commitLatest() {
        guard var status = latestStatus else { return }
        latestStatus = nil
        guard let snapshot = try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]),
              snapshot != lastSnapshot else { return }
        status["updated"] = formatter.string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            lastSnapshot = snapshot
        } catch {
            // Diagnostics must not interrupt input.
        }
    }
}
