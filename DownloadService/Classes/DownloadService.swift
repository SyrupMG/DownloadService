//
//  DownloadService.swift
//  instore travel
//
//  Created by Alexey Lysenko on 11.04.18.
//  Copyright © 2018 SL Tech. All rights reserved.
//

import Foundation
import HWIFileDownload

public enum DownloadableError: Error {
    case notBound
}

/// Main service
public class DownloadService: NSObject {

    /// Shared instance. Just use it!
    public static let shared = DownloadService()

    private var downloadManager: HWIFileDownloader!
    private var downloadableCache = WeakDictionary<String, Downloadable>()
    private var downloadableListeners = [String: [DownloadStatusListner]]()

    public var hasActiveDownloads: Bool { return downloadManager.hasActiveDownloads() }

    private override init() {
        super.init()
        downloadManager = HWIFileDownloader(delegate: self)
        downloadManager.setup { [weak self] in
            self?.isReady = true
        }
    }

    private var readyHandlers: [() -> Void] = []
    private var isReady: Bool = false {
        didSet {
            readyHandlers.forEach { $0() }
            readyHandlers.removeAll()
        }
    }

    /// Register callback which is called when download service initialized and ready to work.
    ///
    /// - Parameter callback: callback
    public func onReady(_ callback: @escaping () -> Void) {
        if isReady { callback() }
        else { readyHandlers.append(callback) }
    }

    func register(listener: DownloadStatusListner, for object: Downloadable) {
        downloadableListeners[object.downloadUniqueId, default: []].append(listener)
    }

    func notify(_ downloadable: Downloadable, _ listener: @escaping (DownloadStatusListner) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let this = self else { return }
            this.downloadableListeners[downloadable.downloadUniqueId]?.forEach { listener($0) }
        }
    }

    @discardableResult
    func resumeDownload<T: Downloadable>(_ downloadable: T) throws -> T {
        let mixedUniqueId = downloadable.mixedUniqueId
        guard let cachedDownloadable = getDownloadableBy(mixedUniqueId: mixedUniqueId) as? T else { throw DownloadableError.notBound }

        if !downloadManager.isDownloadingIdentifier(mixedUniqueId) {
            downloadManager.startDownload(withIdentifier: mixedUniqueId,
                                          fromRemoteURL: cachedDownloadable.downloadRemoteUrl)

            notify(cachedDownloadable) { $0.downloadBegan() }
        }
        return cachedDownloadable
    }
    
    func isDownloading<T: Downloadable>(_ downloadable: T) -> Bool {
        return downloadManager.isDownloadingIdentifier(downloadable.mixedUniqueId)
    }

    func cancelDownload(_ downloadable: Downloadable) {
        let uniqueId = downloadable.mixedUniqueId
        downloadManager.cancelDownload(withIdentifier: uniqueId)
    }

    /// Возвращает связанный с сервисом объект, который уже находится
    /// в очереди на скачивание, или же добавляет объект в очередь и возвращает его
    ///
    /// - Parameter some: объект, который мы хотим завязать с сервисом загрузки
    /// - Returns: объект, который завязан с сервисом загрузки
    func bind<T: Downloadable>(some: T) -> T {
        let mixedUniqueId = some.mixedUniqueId

        guard let cachedDownloadable = getDownloadableBy(mixedUniqueId: mixedUniqueId) else {
            addToCache(some)
            return some
        }
        return cachedDownloadable as! T
    }


    private var registeredDownloadables = [String: Downloadable.Type]()

    /// Registers `Downloadable`\`s type in manager for service could use fabric initializers for creating instances
    ///
    /// - Parameter downloadableType: type
    public func register<T: Downloadable>(_ downloadableType: T.Type) {
        registeredDownloadables[downloadableType.classId] = downloadableType
    }

    /// Must be used in UIApplicationDelegate to catch downloads finish
    public var backgroundSessionCompletionHandlerBlock: () -> () = {} {
        didSet { downloadManager.setBackgroundSessionCompletionHandlerBlock(backgroundSessionCompletionHandlerBlock) }
    }

    /// Called when more downloads are active
    public var incrementNetworkActivityCountHandler: () -> Void = {}

    /// Called when some of downloads is finished
    public var decrementNetworkActivityCountHandler: () -> Void = {}

    // MARK: - privates
    private func getDownloadableBy(mixedUniqueId: String) -> Downloadable? {
        return downloadableCache[mixedUniqueId]
    }

    private func createDownloadableFrom(mixedUniqueId: String) -> Downloadable? {
        let (type, uniqueId) = restoreFrom(mixedUniqueId: mixedUniqueId)
        return registeredDownloadables[type]?.init(uniqueId)
    }

    // MARK: - Cache operations
    private func addToCache(_ downloadable: Downloadable) {
        downloadableCache[downloadable.mixedUniqueId] = downloadable
    }
}

extension DownloadService: HWIFileDownloadDelegate {
    public func downloadDidComplete(withIdentifier aDownloadIdentifier: String, localFileURL aLocalFileURL: URL) {
        guard let downloadable = getDownloadableBy(mixedUniqueId: aDownloadIdentifier) else { return }
        notify(downloadable) { $0.downloadFinished() }
    }

    public func downloadFailed(withIdentifier aDownloadIdentifier: String,
                               error anError: Error,
                               httpStatusCode aHttpStatusCode: Int,
                               errorMessagesStack anErrorMessagesStack: [String]?,
                               resumeData aResumeData: Data?) {
        guard let downloadable = getDownloadableBy(mixedUniqueId: aDownloadIdentifier) else { return }
        notify(downloadable) { $0.downloadFailed(anError) }
    }
    
    public func incrementNetworkActivityIndicatorActivityCount() {
        incrementNetworkActivityCountHandler()
    }

    public func decrementNetworkActivityIndicatorActivityCount() {
        decrementNetworkActivityCountHandler()
    }

    // MARK: - optionals

    public func customizeBackgroundSessionConfiguration(_ aBackgroundSessionConfiguration: URLSessionConfiguration) {
        aBackgroundSessionConfiguration.isDiscretionary = false;
    }

    public func localFileURL(forIdentifier aDownloadIdentifier: String, remoteURL aRemoteURL: URL) -> URL? {
        guard let downloadable = getDownloadableBy(mixedUniqueId: aDownloadIdentifier)
            ?? createDownloadableFrom(mixedUniqueId: aDownloadIdentifier) else { return nil }

        var localPath = downloadable.downloadLocalUrl
        if localPath.isFileURL { localPath = localPath.deletingLastPathComponent() }

        do {
            try FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error(error.localizedDescription)
            return nil
        }

        return downloadable.downloadLocalUrl
    }

    public func downloadProgressChanged(forIdentifier aDownloadIdentifier: String) {
        guard let downloadable = getDownloadableBy(mixedUniqueId: aDownloadIdentifier) else { return }
        guard let progress = downloadManager.downloadProgress(forIdentifier: aDownloadIdentifier) else { return }
        notify(downloadable) { $0.downloadProgressUpdated(progress: FileDownloadProgress(progress)) }
    }
}

private extension DownloadService {
    func restoreFrom(mixedUniqueId mixed: String) -> (type: String, uniqueId: String) {
        let tokens = mixed.components(separatedBy: "👻")
        return (tokens[0], tokens[1])
    }
}

private extension Downloadable {
    var mixedUniqueId: String {
        return String(describing: type(of: self)) + "👻" + downloadUniqueId
    }

    static var classId: String {
        return String(describing: self)
    }
}
