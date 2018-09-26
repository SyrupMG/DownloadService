//
//  DownloadService.swift
//  instore travel
//
//  Created by Alexey Lysenko on 11.04.18.
//  Copyright © 2018 SL Tech. All rights reserved.
//

import Foundation
import HWIFileDownload

/// Main service
public class DownloadService: NSObject {

    /// Shared instance. Just use it!
    public static let shared = DownloadService()
    
    /// Позволяет узнать, есть ли у нас активные загрузки. Загрузки, которые стоят в ожидании
    /// (ждут завершения других или по другим причинам), также считаются активными
    public var hasActiveDownloads: Bool { return downloadManager.hasActiveDownloads() }

    private var downloadManager: HWIFileDownloader!
    private var downloadableCache = WeakDictionary<String, Downloadable>()
    private var downloadableListeners = [String: [DownloadStatusListner]]()
    
    // MARK: - Download manager accessors
    private var activeDownloadsDictionary: [NSNumber: HWIFileDownloadItem] {
        return downloadManager.value(forKey: "activeDownloadsDictionary") as? [NSNumber: HWIFileDownloadItem] ?? [:]
    }
    private var waitingDownloadsArray: [[String: Any]] {
        get {
            return downloadManager.value(forKey: "waitingDownloadsArray") as? [[String: Any]] ?? []
        }
        set {
            downloadManager.setValue(newValue, forKey: "waitingDownloadsArray")
        }
    }
    
    // MARK: - configuration
    /// Объект конфигурации
    public var configuration: DownloadManagerConfig = .default {
        didSet { resetWithNewConfiguration() }
    }
    
    /// Индикатор, что процедура замены ```resetWithNewConfiguration``` запущена
    private var configurationIsChainging: Bool = false
    
    /// Запускает процедуру замены FileDownloader'а относительного новой конфигурациии
    ///
    /// В случае, если такая процедура уже запущена, повторный вызов будет проигнорирован
    private func resetWithNewConfiguration() {
        guard !configurationIsChainging else { return }
        configurationIsChainging = true

        // Сохраняем то, что стоит на паузе
        var tasksToResume = waitingDownloadsArray.compactMap { waitingObjectDict -> PendingDownloadObject? in
            guard let downloadToken = waitingObjectDict["downloadToken"] as? String,
                let remoteURL = waitingObjectDict["remoteURL"] as? URL else { return nil }
            
            let resumeData = waitingObjectDict["resumeData"] as? Data
            return PendingDownloadObject(downloadToken: downloadToken, resumeData: resumeData, remoteURL: remoteURL)
        }
        // Обнуляем то, что стоит на паузе
        waitingDownloadsArray = []
        
        // Считаем, сколько всего тасок должно быть (запаузеные + те, которые сейчас запущены)
        let allTasksCount = tasksToResume.count + activeDownloadsDictionary.count
        
        // Функция проверки, все ли текущие загрузки мы сохранили
        func checkIfAllDone() {
            // Если в tasksToResume добавлены все задачи, можно приступать к финализирующим действиям
            guard tasksToResume.count == allTasksCount else { return }
            
            createNewBgSessionId()
            createNewFileDownloader()
            downloadManager.setBackgroundSessionCompletionHandlerBlock(backgroundSessionCompletionHandlerBlock)

            downloadManager.setup { [weak self] in
                tasksToResume.forEach { taskToResume in
                    guard let this = self else { return }
                    if let resumeData = taskToResume.resumeData {
                        this.downloadManager.startDownload(withIdentifier: taskToResume.downloadToken, usingResumeData: resumeData)
                    } else {
                        this.downloadManager.startDownload(withIdentifier: taskToResume.downloadToken, fromRemoteURL: taskToResume.remoteURL)
                    }
                    let uniqueId = this.restoreFrom(mixedUniqueId: taskToResume.downloadToken).uniqueId
                    this.notify(uniqueId) { $0.downloadBegan() }
                }
                self?.configurationIsChainging = false
            }
        }
        
        // Проверяем, есть ли таски, которые запущены
        guard activeDownloadsDictionary.count != 0 else {
            // Если таковых нет, мы сразу переходим к финализирующей функции
            checkIfAllDone()
            return
        }

        // Бежим по активным загрузкам и убиваем их
        activeDownloadsDictionary.forEach { key, value in
            guard let downloadTask = value.sessionDownloadTask,
                let downloadToken = downloadTask.taskDescription,
                let remoteURL = downloadTask.currentRequest?.url else {
                    value.sessionDownloadTask?.cancel()
                    return
            }
    
            value.sessionDownloadTask?.cancel(byProducingResumeData: { (resumeData) in
                tasksToResume.insert(PendingDownloadObject(downloadToken: downloadToken, resumeData: resumeData, remoteURL: remoteURL), at: 0)
                checkIfAllDone()
            })
        }
    }
    
    // MARK: - bgSessionId methods
    
    /// Ключ, по которому в UserDeafults лежит идентификатор сессии
    private let bgSessionIdKey = "\(Bundle.main.bundleIdentifier ?? "").DownloadServiceBgSessionId"
    
    /// Аксессор по которому можно получить идентификатор сессии из UserDefaults.
    /// В случае, если это первый запуск, аксессор сам сгенерирует имя сессии
    private var backgroundSessionIdentifier: String {
        get {
            guard let sessionId = UserDefaults.standard.string(forKey: bgSessionIdKey) else {
                return createNewBgSessionId()
            }
            return sessionId
        }
        set { UserDefaults.standard.set(newValue, forKey: bgSessionIdKey) }
    }
    
    /// Creates and saves new session id to UserDefaults
    @discardableResult
    private func createNewBgSessionId() -> String {
        let newSessionId = "\(Bundle.main.bundleIdentifier ?? "").DownloadService.\(UUID().uuidString)"
        UserDefaults.standard.set(newSessionId, forKey: bgSessionIdKey)
        return newSessionId
    }
    
    // MARK: - initialization
    /// Создает новый HWIFileDownloader
    private func createNewFileDownloader() {
        downloadManager = HWIFileDownloader(delegate: self,
                                            maxConcurrentDownloads: configuration.maxConcurrentFileDownloadsCount,
                                            backgroundSessionIdentifier: backgroundSessionIdentifier)
    }

    private override init() {
        super.init()
        createNewFileDownloader()
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

    func notify(_ downloadable: Downloadable, _ listner: @escaping (DownloadStatusListner) -> Void) {
        notify(downloadable.downloadUniqueId, listner)
    }
    
    func notify(_ downloadUniqueId: String, _ listner: @escaping (DownloadStatusListner) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let this = self else { return }
            this.downloadableListeners[downloadUniqueId]?.forEach { listner($0) }
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

    /// Отменяет загрузку
    ///
    /// - Parameter downloadable: объект, загрузку которого необходимо отменить
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
        aBackgroundSessionConfiguration.allowsCellularAccess = configuration.allowsCellularAccess
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
