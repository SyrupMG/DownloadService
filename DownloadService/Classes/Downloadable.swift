//
//  Downloadable.swift
//  instore travel
//
//  Created by Alexey Lysenko on 11.04.18.
//  Copyright © 2018 SL Tech. All rights reserved.
//

import Foundation

public protocol DownloadStatusListner: class {
    /**
     Закачался новый чанк
     
     @param progress Объект, содержащий описание прогресса
     */
    func downloadProgressUpdated(progress: FileDownloadProgress)
    
    /**
     Вызывается, когда скачка началась
     */
    func downloadBegan()
    
    /**
     Вызывается, когда скачка закончилась успешно
     */
    func downloadFinished()
    
    /**
     Когда произошла ошибка при скачивании
     
     @param failReason ошибка
     */
    func downloadFailed(_ error: Error)
}

public protocol Downloadable: class {
    /**
     Возвращает объект, соответствующий уникальному ИД

     @param uniqueId @see @property (readonly) NSString *downloadUniqueId;

     @return Объект, который отслеживает и настраивает закачку
     */
    init?(_ downloadableUniqueId: String)

    /**
     Уникальный ИД, идентифицирующий закачку
     */
    var downloadUniqueId: String { get }

    var downloadRemoteUrl: URL { get }
    /**
     Локальный путь, имя файла, куда сохранить скачанный контент
     */
    var downloadLocalUrl: URL { get }
    
    var downloadStatusListner: DownloadStatusListner? { get set }
}

public extension Downloadable {
    /// Начинает загрузку объекта с помощью shared DownloadService. Убедитесь, что объект binded
    public func resumeDownload(with downloadService: DownloadService = DownloadService.shared) throws -> Self {
        return try downloadService.resumeDownload(self)
    }
    
    public func isDownloading(with downloadService: DownloadService = DownloadService.shared) -> Bool {
        return downloadService.isDownloading(self)
    }
    
    public func cancelDownload(with downloadService: DownloadService = DownloadService.shared) {
        downloadService.cancelDownload(self)
    }
}

public extension Downloadable {
    public var isDownloadLocalFileExist: Bool {
        return FileManager.default.fileExists(atPath: downloadLocalUrl.path)
    }
}
