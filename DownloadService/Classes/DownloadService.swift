//
//  DownloadService.swift
//  instore travel
//
//  Created by Alexey Lysenko on 11.04.18.
//  Copyright © 2018 SL Tech. All rights reserved.
//

import Foundation
import HWIFileDownload
import PromiseKit

private class WeakDownloadableWrapper {
    private(set) weak var downloadable: Downloadable?
    init(_ downloadable: Downloadable) {
        self.downloadable = downloadable
    }
}

class DownloadableNotBound: Error {}

public class DownloadService: NSObject {
    private var downloadManager: HWIFileDownloader!
    private var downloadableCache = [String: WeakDownloadableWrapper]()
    private var onReadyPending = Promise<DownloadService>.pending()

    public var onReady: Promise<DownloadService> { return onReadyPending.promise }
    public var hasActiveDownloads: Bool { return downloadManager.hasActiveDownloads() }
    public var logger: Logger = SimpleLogger()
    
    public static let shared = DownloadService()
    
    override init() {
        super.init()
        downloadManager = HWIFileDownloader(delegate: self)
        downloadManager.setup { [weak self] in
            self?.onReadyPending.resolver.fulfill(self!)

            if self?.downloadManager.hasActiveDownloads() ?? false {
                self?.logger.info("Download manager has active downloads, resuming")
            }
        }
    }

    /**
     Начинает закачку по информации протокола

     @param downloadable Объект, описывающий загрузку
     */
    @discardableResult
    public func resumeDownload<T: Downloadable>(_ downloadable: T) throws -> T {
        let mixedUniqueId = downloadable.mixedUniqueId
        guard let cachedDownloadable = getDownloadableBy(mixedUniqueId: mixedUniqueId) as? T else {
            throw DownloadableNotBound()
        }
        if !downloadManager.isDownloadingIdentifier(mixedUniqueId) {
            downloadManager.startDownload(withIdentifier: mixedUniqueId,
                                          fromRemoteURL: cachedDownloadable.downloadRemoteUrl)
            DispatchQueue.main.async { cachedDownloadable.downloadStatusListner?.downloadBegan() }
        }
        cleanCache()
        return cachedDownloadable
    }
    
    public func isDownloading<T: Downloadable>(_ downloadable: T) -> Bool {
        return downloadManager.isDownloadingIdentifier(downloadable.mixedUniqueId)
    }

    /**
     Отменить закачку

     @param downloadable Объект
     */
    public func cancelDownload(_ downloadable: Downloadable) {
        let uniqueId = downloadable.mixedUniqueId
        downloadManager.cancelDownload(withIdentifier: uniqueId)

        cleanCache()
    }

    /// Возвращает связанный с сервисом объект, который уже находится
    /// в очереди на скачивание, или же добавляет объект в очередь и возвращает его
    ///
    /// - Parameter some: объект, который мы хотим завязать с сервисом загрузки
    /// - Returns: объект, который завязан с сервисом загрузки
    public func bind<T: Downloadable>(some: T) -> T {
        let mixedUniqueId = some.mixedUniqueId

        guard let cachedDownloadable = getDownloadableBy(mixedUniqueId: mixedUniqueId) else {
            addToCache(some)
            return some
        }
        return cachedDownloadable as! T
    }

    // MARK: - работа с регистрацией сущностей в сервисе
    private var registeredDownloadables = [String: Downloadable.Type]()
    public func register<T: Downloadable>(_ downloadableType: T.Type) {
        registeredDownloadables[downloadableType.classId] = downloadableType
    }

    /**
     Блок, который передается в AppDelegate. Используется для обработки фоновых закачек
     */
    public var backgroundSessionCompletionHandlerBlock: () -> () = {} {
        didSet {
            downloadManager.setBackgroundSessionCompletionHandlerBlock(backgroundSessionCompletionHandlerBlock)
        }
    }
    
    // MARK: - Network Activity counting
    /**
     Функция, которя будет вызываться, если надо увеличить счетчик сетевых активностей
     */
    public var incrementNetworkActivityCountHandler: () -> Void = {}
    
    /**
     Функция, которя будет вызываться, если надо уменьшить счетчик сетевых активностей
     */
    public var decrementNetworkActivityCountHandler: () -> Void = {}

    // MARK: - privates
    private func getDownloadableBy(mixedUniqueId: String) -> Downloadable? {
        return downloadableCache[mixedUniqueId]?.downloadable
    }

    private func createDownloadableFrom(mixedUniqueId: String) -> Downloadable? {
        let (type, uniqueId) = restoreFrom(mixedUniqueId: mixedUniqueId)
        return registeredDownloadables[type]?.init(uniqueId)
    }

    // MARK: - Cache operations
    private func addToCache(_ downloadable: Downloadable) {
        cleanCache()
        downloadableCache[downloadable.mixedUniqueId] = WeakDownloadableWrapper(downloadable)
    }

    private func cleanCache() {
        downloadableCache = downloadableCache.filter { $0.value.downloadable != nil }
    }
}

extension DownloadService: HWIFileDownloadDelegate {
    public func downloadDidComplete(withIdentifier aDownloadIdentifier: String, localFileURL aLocalFileURL: URL) {
        guard let downloadable = getDownloadableBy(mixedUniqueId: aDownloadIdentifier) else {
            return
        }
        DispatchQueue.main.async {
            downloadable.downloadStatusListner?.downloadFinished()
            self.cleanCache()
        }
    }

    public func downloadFailed(withIdentifier aDownloadIdentifier: String, error anError: Error, httpStatusCode aHttpStatusCode: Int, errorMessagesStack anErrorMessagesStack: [String]?, resumeData aResumeData: Data?) {
        guard let downloadable = getDownloadableBy(mixedUniqueId: aDownloadIdentifier) else {
            return
        }
        DispatchQueue.main.async {
            downloadable.downloadStatusListner?.downloadFailed(anError)
            self.cleanCache()
        }
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
        guard let downloadable = getDownloadableBy(mixedUniqueId: aDownloadIdentifier) ?? createDownloadableFrom(mixedUniqueId: aDownloadIdentifier) else {
            return nil
        }

        var localPath = downloadable.downloadLocalUrl
        if localPath.isFileURL {
            localPath = localPath.deletingLastPathComponent()
        }

        do {
            try FileManager.default.createDirectory(at: localPath, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            logger.error(error.localizedDescription)
            return nil
        }

        return downloadable.downloadLocalUrl
    }

    public func downloadProgressChanged(forIdentifier aDownloadIdentifier: String) {
        guard let downloadable = getDownloadableBy(mixedUniqueId: aDownloadIdentifier) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            defer { self?.cleanCache() }
            guard let progress = self?.downloadManager.downloadProgress(forIdentifier: aDownloadIdentifier) else {
                return
            }
            downloadable.downloadStatusListner?.downloadProgressUpdated(progress: FileDownloadProgress(progress))
        }
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
