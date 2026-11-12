import Foundation

/// 資料夾底下新增、刪除或改名項目時呼叫 onChange。複製大資料夾需要時間，所以等 0.5 秒再通知。
@MainActor
final class FolderWatcher {
    private let source: DispatchSourceFileSystemObject
    private var pending: DispatchWorkItem?

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setCancelHandler { close(fd) }
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending?.cancel()
                let work = DispatchWorkItem { MainActor.assumeIsolated { onChange() } }
                self.pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            }
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
