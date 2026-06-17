import Foundation
import CoreServices

public final class FSEventsWatcher {
    private let directory: URL
    private let store: SessionStore
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.aignals.fsevents", qos: .utility)

    public init(directory: URL, store: SessionStore) {
        self.directory = directory
        self.store = store
    }

    public func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let paths = [directory.path] as CFArray
        let callback: FSEventStreamCallback = { _, ctx, numEvents, eventPaths, _, _ in
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(ctx!).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            for i in 0..<numEvents {
                watcher.handle(path: paths[i])
            }
        }

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else { return }

        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        self.stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        self.stream = nil
    }

    deinit { stop() }

    private func handle(path: String) {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        guard name.hasSuffix(".json"), !name.hasSuffix(".json.tmp") else { return }

        let exists = FileManager.default.fileExists(atPath: path)
        Task { @MainActor in
            if exists {
                store.loadFromDisk(path: url)
            } else {
                store.removeBy(filename: name)
            }
        }
    }
}
