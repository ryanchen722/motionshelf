import AVFoundation
import AppKit
import WebKit

enum Resolution: String, CaseIterable, Identifiable {
    case landscape, portrait, square

    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .landscape: CGSize(width: 1920, height: 1080)
        case .portrait: CGSize(width: 1080, height: 1920)
        case .square: CGSize(width: 1440, height: 1440)
        }
    }

    var label: String {
        switch self {
        case .landscape: L("橫 1920×1080", "Landscape 1920×1080")
        case .portrait: L("直 1080×1920", "Portrait 1080×1920")
        case .square: L("方 1440×1440", "Square 1440×1440")
        }
    }
}

/// 逐幀呼叫 seek(t)、擷取透明畫面，用 AVAssetWriter 編碼成 ProRes 4444（含 alpha）的 .mov。
/// 不依賴 Node、Playwright 或 ffmpeg。
@MainActor
final class Exporter: ObservableObject {
    enum State {
        case idle
        case exporting(progress: Double)
        case done(url: URL, thumbnail: NSImage)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    static var outputFolder: URL { Settings.exportFolder }

    var isExporting: Bool {
        if case .exporting = state { return true }
        return false
    }

    func start(effect: Effect, paramsJSON: String, resolution: Resolution, camera: CameraState) {
        guard !isExporting else { return }
        state = .exporting(progress: 0)
        task = Task {
            do {
                let (url, thumbnail) = try await render(effect: effect, paramsJSON: paramsJSON, resolution: resolution, camera: camera)
                state = .done(url: url, thumbnail: thumbnail)
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    func revealInFinder() {
        if case .done(let url, _) = state {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            try? FileManager.default.createDirectory(at: Self.outputFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([Self.outputFolder])
        }
    }

    // MARK: - 輸出流程

    private func render(effect: Effect, paramsJSON: String, resolution: Resolution, camera: CameraState) async throws -> (URL, NSImage) {
        let size = resolution.size
        let width = Int(size.width)
        let height = Int(size.height)
        let fps = effect.manifest.fps
        let frameCount = max(1, Int((effect.manifest.duration * Double(fps)).rounded()))

        // 放在螢幕外的視窗：CSS 畫布剛好是輸出解析度，使用者看不到
        let window = NSWindow(
            contentRect: NSRect(x: -40000, y: -40000, width: size.width, height: size.height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        let configuration = WKWebViewConfiguration()
        NetworkBlock.install(on: configuration)
        let webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        window.contentView = webView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        let loader = PageLoader()
        try await loader.load(effect, in: webView)
        let hasAPI = try await webView.evaluateJavaScript(
            "typeof window.seek === 'function' && typeof window.setParams === 'function'"
        ) as? Bool
        guard hasAPI == true else { throw ExportError(L("effect.html 必須提供 window.seek(t) 與 window.setParams(params)", "effect.html must provide window.seek(t) and window.setParams(params)")) }
        _ = try await webView.evaluateJavaScript("window.setParams(\(paramsJSON)); 0")
        _ = try await webView.callAsyncJavaScript("await document.fonts.ready", contentWorld: .page)

        try FileManager.default.createDirectory(at: Self.outputFolder, withIntermediateDirectories: true)
        let url = Self.outputFolder.appendingPathComponent("\(effect.id)_\(width)x\(height)_\(Self.stamp()).mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes4444,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError(L("無法開始寫入影片", "Could not start writing the video")) }
        writer.startSession(atSourceTime: .zero)

        var thumbnail: NSImage?
        do {
            for index in 0..<frameCount {
                try Task.checkCancellation()
                let t = Double(index) / Double(fps)
                _ = try await webView.evaluateJavaScript("window.seek(\(t)); " + camera.script(at: t))

                let config = WKSnapshotConfiguration()
                config.snapshotWidth = NSNumber(value: Double(width) / Double(window.backingScaleFactor))
                let image = try await webView.takeSnapshot(configuration: config)
                if index == frameCount / 2 { thumbnail = image }
                guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw ExportError(L("第 \(index + 1) 幀擷取失敗", "Failed to capture frame \(index + 1)"))
                }
                let buffer = try Self.pixelBuffer(from: cgImage, pool: adaptor.pixelBufferPool, width: width, height: height)

                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: Int32(fps))) else {
                    throw writer.error ?? ExportError(L("第 \(index + 1) 幀寫入失敗", "Failed to write frame \(index + 1)"))
                }
                state = .exporting(progress: Double(index + 1) / Double(frameCount))
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? ExportError(L("影片寫入沒有完成", "The video was not written completely")) }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return (url, thumbnail ?? NSImage())
    }

    /// 把擷取的畫面畫進 BGRA（預乘 alpha）的 pixel buffer，並標記 alpha 模式，ProRes 4444 才會保留透明
    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool?, width: Int, height: Int) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)
        } else {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &created)
        }
        guard let buffer = created else { throw ExportError(L("無法建立畫面緩衝區", "Could not create a pixel buffer")) }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw ExportError(L("無法建立繪圖環境", "Could not create a drawing context")) }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)

        CVBufferSetAttachment(buffer, kCVImageBufferAlphaChannelModeKey, kCVImageBufferAlphaChannelMode_PremultipliedAlpha, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        return buffer
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

struct ExportError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// 等 effect.html 載入完成
@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ effect: Effect, in webView: WKWebView) async throws {
        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadFileURL(effect.htmlURL, allowingReadAccessTo: effect.folder)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
