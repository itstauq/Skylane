import AppKit
import CryptoKit
import Foundation
import ImageIO
import Nuke

enum WidgetImagePipelineContentMode {
    case fill
    case fit

    init(_ value: String?) {
        switch value {
        case "fit":
            self = .fit
        default:
            self = .fill
        }
    }

    var thumbnailContentMode: ImageProcessingOptions.ContentMode {
        switch self {
        case .fill:
            return .aspectFill
        case .fit:
            return .aspectFit
        }
    }
}

struct WidgetHostImageAssetReference: Equatable {
    var src: String
    var width: Double?
    var height: Double?
}

private enum WidgetHostAssetRegistry {
    private struct ImageAsset {
        let token: String
        let fingerprint: String
        let image: NSImage
        let intrinsicSize: CGSize?
        var accessIndex: UInt64
    }

    private static let imageScheme = "skylane-asset"
    private static let imageHost = "image"
    private static let maxImageCount = 256
    private static let lock = NSLock()
    private static var imageAssetsByToken: [String: ImageAsset] = [:]
    private static var imageTokensByFingerprint: [String: String] = [:]
    private static var nextAccessIndex: UInt64 = 1

    static func registerImage(data: Data, mimeType: String?) -> WidgetHostImageAssetReference? {
        _ = mimeType
        let fingerprint = imageFingerprint(for: data)

        if let cached = withLock({ () -> ImageAsset? in
            guard let token = imageTokensByFingerprint[fingerprint],
                  var asset = imageAssetsByToken[token] else {
                return nil
            }

            asset.accessIndex = claimAccessIndex()
            imageAssetsByToken[token] = asset
            return asset
        }) {
            return reference(from: cached)
        }

        guard let image = NSImage(data: data) else {
            return nil
        }

        let intrinsicSize = imageMetadata(from: data)?.displaySize ?? normalized(image.size)

        return withLock {
            if let token = imageTokensByFingerprint[fingerprint],
               var asset = imageAssetsByToken[token] {
                asset.accessIndex = claimAccessIndex()
                imageAssetsByToken[token] = asset
                return reference(from: asset)
            }

            let token = fingerprint
            let asset = ImageAsset(
                token: token,
                fingerprint: fingerprint,
                image: image,
                intrinsicSize: intrinsicSize,
                accessIndex: claimAccessIndex()
            )
            imageTokensByFingerprint[fingerprint] = token
            imageAssetsByToken[token] = asset
            trimImageAssetsIfNeeded()
            return reference(from: asset)
        }
    }

    static func isImageAssetURL(_ url: URL) -> Bool {
        imageToken(from: url) != nil
    }

    static func image(at url: URL) -> NSImage? {
        guard let token = imageToken(from: url) else {
            return nil
        }

        return withLock {
            guard var asset = imageAssetsByToken[token] else {
                return nil
            }

            asset.accessIndex = claimAccessIndex()
            imageAssetsByToken[token] = asset
            return asset.image
        }
    }

    static func intrinsicSize(at url: URL) -> CGSize? {
        guard let token = imageToken(from: url) else {
            return nil
        }

        return withLock {
            guard var asset = imageAssetsByToken[token] else {
                return nil
            }

            asset.accessIndex = claimAccessIndex()
            imageAssetsByToken[token] = asset
            return asset.intrinsicSize
        }
    }

    static func clearAll() {
        withLock {
            imageAssetsByToken.removeAll()
            imageTokensByFingerprint.removeAll()
            nextAccessIndex = 1
        }
    }

    #if DEBUG
    static func resetForTesting() {
        clearAll()
    }
    #endif

    private static func reference(from asset: ImageAsset) -> WidgetHostImageAssetReference {
        WidgetHostImageAssetReference(
            src: "skylane-asset://image/\(asset.token)",
            width: asset.intrinsicSize.map(\.width).map(Double.init),
            height: asset.intrinsicSize.map(\.height).map(Double.init)
        )
    }

    private static func imageToken(from url: URL) -> String? {
        guard url.scheme?.lowercased() == imageScheme,
              url.host?.lowercased() == imageHost else {
            return nil
        }

        let token = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return token.isEmpty ? nil : token
    }

    private static func imageFingerprint(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func trimImageAssetsIfNeeded() {
        guard imageAssetsByToken.count > maxImageCount else {
            return
        }

        let overflowCount = imageAssetsByToken.count - maxImageCount
        let evictedTokens = imageAssetsByToken.values
            .sorted(by: { $0.accessIndex < $1.accessIndex })
            .prefix(overflowCount)
            .map(\.token)

        for token in evictedTokens {
            guard let removed = imageAssetsByToken.removeValue(forKey: token) else {
                continue
            }

            imageTokensByFingerprint.removeValue(forKey: removed.fingerprint)
        }
    }

    private static func claimAccessIndex() -> UInt64 {
        let value = nextAccessIndex
        nextAccessIndex += 1
        return value
    }

    private static func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func normalized(_ size: CGSize?) -> CGSize? {
        guard let size else {
            return nil
        }

        let width = max(0, size.width)
        let height = max(0, size.height)
        guard width > 0, height > 0 else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private static func imageMetadata(from data: Data) -> WidgetImagePipeline.ImageMetadata? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = numericProperty(kCGImagePropertyPixelWidth, in: properties),
              let height = numericProperty(kCGImagePropertyPixelHeight, in: properties),
              width > 0,
              height > 0 else {
            return nil
        }

        return WidgetImagePipeline.ImageMetadata(
            pixelSize: CGSize(width: width, height: height),
            orientation: imageOrientation(from: properties)
        )
    }

    private static func numericProperty(_ key: CFString, in properties: [CFString: Any]) -> CGFloat? {
        if let value = properties[key] as? CGFloat {
            return value
        }

        if let value = properties[key] as? NSNumber {
            return CGFloat(truncating: value)
        }

        return nil
    }

    private static func imageOrientation(from properties: [CFString: Any]) -> CGImagePropertyOrientation {
        if let rawValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value,
           let orientation = CGImagePropertyOrientation(rawValue: rawValue) {
            return orientation
        }

        if let rawValue = (properties[kCGImagePropertyTIFFOrientation] as? NSNumber)?.uint32Value,
           let orientation = CGImagePropertyOrientation(rawValue: rawValue) {
            return orientation
        }

        return .up
    }
}

enum WidgetImagePipeline {
    fileprivate struct ImageMetadata {
        let pixelSize: CGSize
        let orientation: CGImagePropertyOrientation

        var displaySize: CGSize {
            if orientation.swapsDimensions {
                return CGSize(width: pixelSize.height, height: pixelSize.width)
            }

            return pixelSize
        }
    }

    private final class PipelineContext {
        let imageCache: ImageCache
        let remoteDataCache: DataCache?
        let localPipeline: ImagePipeline
        let remotePipeline: ImagePipeline

        init(instanceID: UUID, protocolClasses: [AnyClass]?) {
            let imageCache = WidgetImagePipeline.makeImageCache()
            self.imageCache = imageCache
            self.remoteDataCache = WidgetImagePipeline.makeRemoteDataCache(instanceID: instanceID)
            self.localPipeline = WidgetImagePipeline.makeLocalPipeline(imageCache: imageCache)
            self.remotePipeline = WidgetImagePipeline.makeRemotePipeline(
                imageCache: imageCache,
                remoteDataCache: remoteDataCache,
                protocolClasses: protocolClasses
            )
        }

        func pipeline(for url: URL) -> ImagePipeline? {
            if url.isFileURL {
                return localPipeline
            }

            guard WidgetHostNetworkPolicy.allows(url) else {
                return nil
            }

            return remotePipeline
        }

        func clear() {
            localPipeline.invalidate()
            remotePipeline.invalidate()
            imageCache.removeAll()
            remoteDataCache?.removeAll()
            remoteDataCache?.flush()
        }
    }

    private static let remoteResponseSizeLimit = 3 * 1024 * 1024
    private static let perInstanceRemoteDiskCacheLimit = 32 * 1_048_576
    private static let perInstanceMemoryCacheLimit = 24 * 1_048_576
    private static let contextLock = NSLock()
    private static var pipelineContexts: [UUID: PipelineContext] = [:]
    private static var remoteProtocolClassesForTesting: [AnyClass]?

    static func image(
        for instanceID: UUID,
        at url: URL,
        targetSize: CGSize,
        scale: CGFloat = 1,
        contentMode: String? = nil
    ) async -> NSImage? {
        if WidgetHostAssetRegistry.isImageAssetURL(url) {
            return WidgetHostAssetRegistry.image(at: url)
        }

        guard targetSize.width > 0, targetSize.height > 0 else {
            return nil
        }

        guard let pipeline = pipeline(for: url, instanceID: instanceID) else {
            return nil
        }

        let request = makeRequest(
            url: url,
            targetSize: targetSize,
            scale: scale,
            contentMode: contentMode
        )

        if let cached = cachedImage(for: request, pipeline: pipeline) {
            return cached
        }

        do {
            return try await pipeline.image(for: request)
        } catch {
            return nil
        }
    }

    static func cachedImage(
        for instanceID: UUID,
        at url: URL,
        targetSize: CGSize,
        scale: CGFloat = 1,
        contentMode: String? = nil
    ) -> NSImage? {
        if WidgetHostAssetRegistry.isImageAssetURL(url) {
            return WidgetHostAssetRegistry.image(at: url)
        }

        guard targetSize.width > 0, targetSize.height > 0 else {
            return nil
        }

        guard let pipeline = pipeline(for: url, instanceID: instanceID) else {
            return nil
        }

        return cachedImage(
            for: makeRequest(
                url: url,
                targetSize: targetSize,
                scale: scale,
                contentMode: contentMode
            ),
            pipeline: pipeline
        )
    }

    static func intrinsicSize(at url: URL) -> CGSize? {
        if WidgetHostAssetRegistry.isImageAssetURL(url) {
            return WidgetHostAssetRegistry.intrinsicSize(at: url)
        }

        return imageMetadata(at: url)?.displaySize
    }

    static func registerHostImage(data: Data, mimeType: String?) -> WidgetHostImageAssetReference? {
        WidgetHostAssetRegistry.registerImage(data: data, mimeType: mimeType)
    }

    static func isHostAssetURL(_ url: URL) -> Bool {
        WidgetHostAssetRegistry.isImageAssetURL(url)
    }

    static func clearCache() {
        let contexts = removeAllContexts()
        contexts.forEach { $0.clear() }
        WidgetHostAssetRegistry.clearAll()
    }

    static func clearCache(for instanceID: UUID) {
        removeContext(for: instanceID)?.clear()
    }

    static func clearCaches(for instanceIDs: [UUID]) {
        let contexts = removeContexts(for: instanceIDs)
        contexts.forEach { $0.clear() }
    }

    static func resetRemotePipelinesForTesting(protocolClasses: [AnyClass]? = nil) {
        let contexts = withContextLock { () -> [PipelineContext] in
            remoteProtocolClassesForTesting = protocolClasses
            let existing = Array(pipelineContexts.values)
            pipelineContexts.removeAll()
            return existing
        }
        contexts.forEach { $0.clear() }
    }

    static func thumbnailRequestSize(for targetSize: CGSize, at url: URL) -> CGSize {
        if WidgetHostAssetRegistry.isImageAssetURL(url) {
            return targetSize
        }

        guard url.isFileURL,
              let metadata = imageMetadata(at: url),
              metadata.orientation.swapsDimensions else {
            return targetSize
        }

        return CGSize(width: targetSize.height, height: targetSize.width)
    }

    private static func cachedImage(for request: ImageRequest, pipeline: ImagePipeline) -> NSImage? {
        pipeline.cache.cachedImage(for: request, caches: [.memory])?.image
    }

    #if DEBUG
    static func testingCacheLimits(for instanceID: UUID) -> (memory: Int, disk: Int?) {
        let context = context(for: instanceID)
        return (context.imageCache.costLimit, context.remoteDataCache?.sizeLimit)
    }

    static func resetHostAssetsForTesting() {
        WidgetHostAssetRegistry.resetForTesting()
    }
    #endif

    private static func pipeline(for url: URL, instanceID: UUID) -> ImagePipeline? {
        context(for: instanceID).pipeline(for: url)
    }

    private static func makeRequest(
        url: URL,
        targetSize: CGSize,
        scale: CGFloat,
        contentMode: String?
    ) -> ImageRequest {
        let requestTargetSize = thumbnailRequestSize(for: targetSize, at: url)
        let pixelSize = quantizedPixelSize(for: requestTargetSize, scale: scale)
        let contentMode = WidgetImagePipelineContentMode(contentMode)
        let thumbnail = ImageRequest.ThumbnailOptions(
            size: pixelSize,
            unit: .pixels,
            contentMode: contentMode.thumbnailContentMode
        )
        let userInfo: [ImageRequest.UserInfoKey: Any] = [
            .thumbnailKey: thumbnail
        ]

        return ImageRequest(
            url: url,
            userInfo: userInfo
        )
    }

    private static func quantizedPixelSize(for targetSize: CGSize, scale: CGFloat) -> CGSize {
        let scale = max(scale, 1)
        let width = max(1, ceil(targetSize.width * scale))
        let height = max(1, ceil(targetSize.height * scale))
        return CGSize(width: width, height: height)
    }

    private static func makeImageCache() -> ImageCache {
        let imageCache = ImageCache(costLimit: perInstanceMemoryCacheLimit, countLimit: Int.max)
        imageCache.entryCostLimit = 1
        return imageCache
    }

    private static func makeLocalPipeline(imageCache: ImageCache) -> ImagePipeline {
        var configuration = ImagePipeline.Configuration()
        configuration.imageCache = imageCache
        configuration.dataCache = nil
        configuration.isLocalResourcesSupportEnabled = true
        configuration.isTaskCoalescingEnabled = true
        configuration.isProgressiveDecodingEnabled = false
        return ImagePipeline(configuration: configuration)
    }

    private static func makeRemoteDataCache(instanceID: UUID) -> DataCache? {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let path = root
            .appendingPathComponent("com.skylaneapp.Skylane.WidgetRemoteImages", isDirectory: true)
            .appendingPathComponent(instanceID.uuidString, isDirectory: true)
        let cache = try? DataCache(path: path)
        cache?.sizeLimit = perInstanceRemoteDiskCacheLimit
        return cache
    }

    private static func makeRemotePipeline(
        imageCache: ImageCache,
        remoteDataCache: DataCache?,
        protocolClasses: [AnyClass]?
    ) -> ImagePipeline {
        let dataLoader = WidgetRemoteImageDataLoader(
            sizeLimit: remoteResponseSizeLimit,
            protocolClasses: protocolClasses
        )

        var configuration = ImagePipeline.Configuration(dataLoader: dataLoader)
        configuration.imageCache = imageCache
        configuration.dataCache = remoteDataCache
        configuration.dataCachePolicy = .storeOriginalData
        configuration.isLocalResourcesSupportEnabled = false
        configuration.isTaskCoalescingEnabled = true
        configuration.isProgressiveDecodingEnabled = false
        return ImagePipeline(configuration: configuration)
    }

    private static func context(for instanceID: UUID) -> PipelineContext {
        withContextLock {
            if let existing = pipelineContexts[instanceID] {
                return existing
            }

            let context = PipelineContext(instanceID: instanceID, protocolClasses: remoteProtocolClassesForTesting)
            pipelineContexts[instanceID] = context
            return context
        }
    }

    private static func removeContext(for instanceID: UUID) -> PipelineContext? {
        withContextLock {
            pipelineContexts.removeValue(forKey: instanceID)
        }
    }

    private static func removeContexts(for instanceIDs: [UUID]) -> [PipelineContext] {
        withContextLock {
            instanceIDs.compactMap { pipelineContexts.removeValue(forKey: $0) }
        }
    }

    private static func removeAllContexts() -> [PipelineContext] {
        withContextLock {
            let contexts = Array(pipelineContexts.values)
            pipelineContexts.removeAll()
            return contexts
        }
    }

    private static func withContextLock<T>(_ body: () -> T) -> T {
        contextLock.lock()
        defer { contextLock.unlock() }
        return body()
    }

    private static func imageMetadata(at url: URL) -> ImageMetadata? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = numericProperty(kCGImagePropertyPixelWidth, in: properties),
              let height = numericProperty(kCGImagePropertyPixelHeight, in: properties),
              width > 0,
              height > 0 else {
            return nil
        }

        return ImageMetadata(
            pixelSize: CGSize(width: width, height: height),
            orientation: imageOrientation(from: properties)
        )
    }

    private static func numericProperty(_ key: CFString, in properties: [CFString: Any]) -> CGFloat? {
        if let value = properties[key] as? CGFloat {
            return value
        }

        if let value = properties[key] as? NSNumber {
            return CGFloat(truncating: value)
        }

        return nil
    }

    private static func imageOrientation(from properties: [CFString: Any]) -> CGImagePropertyOrientation {
        if let rawValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value,
           let orientation = CGImagePropertyOrientation(rawValue: rawValue) {
            return orientation
        }

        if let rawValue = (properties[kCGImagePropertyTIFFOrientation] as? NSNumber)?.uint32Value,
           let orientation = CGImagePropertyOrientation(rawValue: rawValue) {
            return orientation
        }

        return .up
    }
}

enum RuntimeV2ImageLayoutResolver {
    static func layoutSize(
        explicitFrameSize: CGSize?,
        measuredSize: CGSize,
        intrinsicSize: CGSize?
    ) -> CGSize? {
        let explicitWidth = normalized(explicitFrameSize?.width)
        let explicitHeight = normalized(explicitFrameSize?.height)

        if let explicitWidth, let explicitHeight {
            return CGSize(width: explicitWidth, height: explicitHeight)
        }

        if let intrinsicSize = normalized(intrinsicSize) {
            if let explicitWidth, intrinsicSize.width > 0 {
                return CGSize(
                    width: explicitWidth,
                    height: explicitWidth * intrinsicSize.height / intrinsicSize.width
                )
            }

            if let explicitHeight, intrinsicSize.height > 0 {
                return CGSize(
                    width: explicitHeight * intrinsicSize.width / intrinsicSize.height,
                    height: explicitHeight
                )
            }

            return intrinsicSize
        }

        return normalized(measuredSize)
    }

    static func requestSize(
        explicitFrameSize: CGSize?,
        measuredSize: CGSize,
        intrinsicSize: CGSize?
    ) -> CGSize? {
        let explicitWidth = normalized(explicitFrameSize?.width)
        let explicitHeight = normalized(explicitFrameSize?.height)

        if let explicitWidth, let explicitHeight {
            return CGSize(width: explicitWidth, height: explicitHeight)
        }

        if let measuredSize = normalized(measuredSize) {
            let width = explicitWidth ?? measuredSize.width
            let height = explicitHeight ?? measuredSize.height
            if width > 0, height > 0 {
                return CGSize(width: width, height: height)
            }
        }

        return layoutSize(
            explicitFrameSize: explicitFrameSize,
            measuredSize: measuredSize,
            intrinsicSize: intrinsicSize
        )
    }

    private static func normalized(_ value: CGFloat?) -> CGFloat? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func normalized(_ size: CGSize?) -> CGSize? {
        guard let size else { return nil }
        let width = max(0, size.width)
        let height = max(0, size.height)
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}

private extension CGImagePropertyOrientation {
    var swapsDimensions: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }
}

private enum WidgetRemoteImageLoadingError: LocalizedError {
    case invalidURL
    case disallowedScheme
    case unacceptableStatusCode(Int)
    case nonImageContentType(String?)
    case responseTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid remote image URL."
        case .disallowedScheme:
            return "Remote image URL uses a disallowed scheme."
        case .unacceptableStatusCode(let statusCode):
            return "Remote image response returned status \(statusCode)."
        case .nonImageContentType(let mimeType):
            if let mimeType {
                return "Remote image response was not an image (\(mimeType))."
            }

            return "Remote image response was not an image."
        case .responseTooLarge(let sizeLimit):
            return "Remote image response exceeded \(sizeLimit) bytes."
        }
    }
}

private final class WidgetRemoteImageTask: Nuke.Cancellable, @unchecked Sendable {
    private let cancelAction: @Sendable () -> Void

    init(cancelAction: @escaping @Sendable () -> Void) {
        self.cancelAction = cancelAction
    }

    func cancel() {
        cancelAction()
    }
}

private final class WidgetRemoteImageDataLoader: NSObject, DataLoading, URLSessionDataDelegate, @unchecked Sendable {
    private final class Handler: @unchecked Sendable {
        let didReceiveData: (Data, URLResponse) -> Void
        let completion: (Error?) -> Void
        var receivedBytes = 0
        var terminalError: Error?

        init(
            didReceiveData: @escaping (Data, URLResponse) -> Void,
            completion: @escaping (Error?) -> Void
        ) {
            self.didReceiveData = didReceiveData
            self.completion = completion
        }
    }

    private let sizeLimit: Int
    private let stateLock = NSLock()
    private var session: URLSession!
    private var handlers: [Int: Handler] = [:]

    init(
        sizeLimit: Int,
        protocolClasses: [AnyClass]? = nil
    ) {
        self.sizeLimit = sizeLimit

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.protocolClasses = protocolClasses

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        super.init()

        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session.sessionDescription = "Widget Remote Image URLSession"
    }

    deinit {
        session.invalidateAndCancel()
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping (Data, URLResponse) -> Void,
        completion: @escaping (Error?) -> Void
    ) -> any Nuke.Cancellable {
        guard let url = request.url else {
            completion(WidgetRemoteImageLoadingError.invalidURL)
            return WidgetRemoteImageTask(cancelAction: {})
        }

        guard WidgetHostNetworkPolicy.allows(url) else {
            completion(WidgetRemoteImageLoadingError.disallowedScheme)
            return WidgetRemoteImageTask(cancelAction: {})
        }

        var sanitizedRequest = request
        sanitizedRequest.httpMethod = "GET"
        sanitizedRequest.httpBody = nil
        sanitizedRequest.allHTTPHeaderFields = nil

        let task = session.dataTask(with: sanitizedRequest)
        let handler = Handler(didReceiveData: didReceiveData, completion: completion)

        withHandlerLock {
            handlers[task.taskIdentifier] = handler
        }

        task.resume()

        return WidgetRemoteImageTask { [weak task] in
            task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let handler = handler(for: dataTask.taskIdentifier) else {
            completionHandler(.cancel)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            handler.terminalError = WidgetRemoteImageLoadingError.invalidURL
            completionHandler(.cancel)
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            handler.terminalError = WidgetRemoteImageLoadingError.unacceptableStatusCode(httpResponse.statusCode)
            completionHandler(.cancel)
            return
        }

        let expectedLength = response.expectedContentLength
        if expectedLength > 0,
           expectedLength > Int64(sizeLimit) {
            handler.terminalError = WidgetRemoteImageLoadingError.responseTooLarge(sizeLimit)
            completionHandler(.cancel)
            return
        }

        guard Self.isAcceptedImageMimeType(httpResponse.mimeType) else {
            handler.terminalError = WidgetRemoteImageLoadingError.nonImageContentType(httpResponse.mimeType)
            completionHandler(.cancel)
            return
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let handler = handler(for: dataTask.taskIdentifier),
              let response = dataTask.response else {
            return
        }

        handler.receivedBytes += data.count
        if handler.receivedBytes > sizeLimit {
            handler.terminalError = WidgetRemoteImageLoadingError.responseTooLarge(sizeLimit)
            dataTask.cancel()
            return
        }

        handler.didReceiveData(data, response)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              WidgetHostNetworkPolicy.allows(url) else {
            if let handler = handler(for: task.taskIdentifier) {
                handler.terminalError = WidgetRemoteImageLoadingError.disallowedScheme
            }
            task.cancel()
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let handler = removeHandler(for: task.taskIdentifier) else {
            return
        }

        if let terminalError = handler.terminalError {
            handler.completion(terminalError)
            return
        }

        handler.completion(error)
    }

    private static func isAcceptedImageMimeType(_ mimeType: String?) -> Bool {
        guard let mimeType else {
            return true
        }

        let normalized = mimeType.lowercased()
        if normalized.hasPrefix("image/") {
            return true
        }

        return normalized.contains("octet-stream") || normalized.contains("binary")
    }

    private func handler(for taskIdentifier: Int) -> Handler? {
        withHandlerLock {
            handlers[taskIdentifier]
        }
    }

    private func removeHandler(for taskIdentifier: Int) -> Handler? {
        withHandlerLock {
            handlers.removeValue(forKey: taskIdentifier)
        }
    }

    private func withHandlerLock<T>(_ work: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return work()
    }
}
