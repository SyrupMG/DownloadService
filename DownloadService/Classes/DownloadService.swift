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

private final class Weak<T> {
    private weak var rawValue: AnyObject?
    private(set) var value: T? {
        get { return rawValue as! T? }
        set { rawValue = newValue as AnyObject }
    }
    init(_ value: T) {
        self.value = value
    }

    var isValid: Bool {
        return value != nil
    }
}

private class WeakDictionary<Key: Hashable, Value> : Collection {

    typealias Storage = Dictionary<Key, Weak<Value>>
    typealias Index = DictionaryIndex<Key, Weak<Value>>

    private var storage: Storage

    var startIndex: Storage.Index { return storage.startIndex }
    var endIndex: Storage.Index { return storage.endIndex }
    func index(after i: Index) -> Index { return storage.index(after: i) }

    public init() {
        storage = [:]
    }

    public init(dictionary: [Key : Value]) {
        storage = dictionary.mapValues { Weak($0) }
    }

    private init(withStorage s: [Key: Weak<Value>]) {
        storage = s
        reap()
    }

    subscript(position: Index) -> (Key, Weak<Value>) {
        reap()
        return storage[position]
    }

    subscript(key: Key) -> Value? {
        get {
            reap()
            return storage[key]?.value
        }
        set {
            reap()
            guard let value = newValue else { return }
            storage[key] = Weak(value)
        }
    }

    public subscript(bounds: Range<Index>) -> WeakDictionary<Key, Value> {
        return WeakDictionary(withStorage: Storage(uniqueKeysWithValues: storage[bounds.lowerBound ..< bounds.upperBound].map { $0 }))
    }

    private func reap() {
        guard storage.filter({ !$0.value.isValid }).count > 0 else { return }
        storage = storage.filter { $0.value.isValid }
    }
}

public enum DownloadableError: Error {
    case notBound
}

private let logger: Logger = SimpleLogger()

public class DownloadService: NSObject {

    public static let shared = DownloadService()

    private var downloadManager: HWIFileDownloader!
    private var downloadableCache = WeakDictionary<String, Downloadable>()
    private var downloadableListeners = [String: [DownloadStatusListner]]()
    private let onReadyPending = Promise<DownloadService>.pending()

    public var onReady: Promise<DownloadService> { return onReadyPending.promise }
    public var hasActiveDownloads: Bool { return downloadManager.hasActiveDownloads() }

    override init() {
        super.init()
        downloadManager = HWIFileDownloader(delegate: self)
        downloadManager.setup { [weak self] in
            self?.onReadyPending.resolver.fulfill(self!)

            if self?.downloadManager.hasActiveDownloads() ?? false {
                logger.info("Download manager has active downloads, resuming")
            }
        }
    }

    func notify(_ downloadable: Downloadable, _ listener: @escaping (DownloadStatusListner) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let this = self else { return }
            defer { this.clearCache() }
            this.downloadableListeners[downloadable.downloadUniqueId]?.forEach { listener($0) }
        }
    }

    /**
     Начинает закачку по информации протокола

     @param downloadable Объект, описывающий загрузку
     */
    @discardableResult
    public func resumeDownload<T: Downloadable>(_ downloadable: T) throws -> T {
        let mixedUniqueId = downloadable.mixedUniqueId
        guard let cachedDownloadable = getDownloadableBy(mixedUniqueId: mixedUniqueId) as? T else { throw DownloadableError.notBound }

        if !downloadManager.isDownloadingIdentifier(mixedUniqueId) {
            downloadManager.startDownload(withIdentifier: mixedUniqueId,
                                          fromRemoteURL: cachedDownloadable.downloadRemoteUrl)

            notify(cachedDownloadable) { $0.downloadBegan() }
        }
        clearCache()
        return cachedDownloadable
    }
    
    func isDownloading<T: Downloadable>(_ downloadable: T) -> Bool {
        return downloadManager.isDownloadingIdentifier(downloadable.mixedUniqueId)
    }

    /**
     Отменить закачку

     @param downloadable Объект
     */
    public func cancelDownload(_ downloadable: Downloadable) {
        let uniqueId = downloadable.mixedUniqueId
        downloadManager.cancelDownload(withIdentifier: uniqueId)

        clearCache()
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

    /// Регистрирует тип, который будет будет использовать фабричный метод из протокола для создания через уникальный ИД
    ///
    /// - Parameter downloadableType: тип
    public func register<T: Downloadable>(_ downloadableType: T.Type) {
        registeredDownloadables[downloadableType.classId] = downloadableType
    }

    /**
     Блок, который передается в AppDelegate. Используется для обработки фоновых закачек
     */
    public var backgroundSessionCompletionHandlerBlock: () -> () = {} {
        didSet { downloadManager.setBackgroundSessionCompletionHandlerBlock(backgroundSessionCompletionHandlerBlock) }
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
        return downloadableCache[mixedUniqueId]
    }

    private func createDownloadableFrom(mixedUniqueId: String) -> Downloadable? {
        let (type, uniqueId) = restoreFrom(mixedUniqueId: mixedUniqueId)
        return registeredDownloadables[type]?.init(uniqueId)
    }

    // MARK: - Cache operations
    private func addToCache(_ downloadable: Downloadable) {
        clearCache()
        downloadableCache[downloadable.mixedUniqueId] = downloadable
    }

    private func clearCache() {
//        downloadableCache.reap()
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
