import Dispatch
import Foundation
import Darwin

final class StoreFileWatcher: @unchecked Sendable {
    private let descriptor: CInt
    private let source: DispatchSourceFileSystemObject

    static func changes(fileURL: URL) -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { continuation in
            do {
                let watcher = try StoreFileWatcher(fileURL: fileURL) {
                    continuation.yield()
                }
                continuation.onTermination = { _ in
                    _ = watcher
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    init(fileURL: URL, onChange: @escaping @Sendable () -> Void) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw StoreFileWatcherError.cannotOpenDirectory(directoryURL.path)
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}

enum StoreFileWatcherError: Error {
    case cannotOpenDirectory(String)
}
