//
//  Downloadable.swift
//  instore travel
//
//  Created by Alexey Lysenko on 11.04.18.
//  Copyright © 2018 SL Tech. All rights reserved.
//

import Foundation

/// Наблюдает за процессом скачивания
public protocol DownloadStatusListner: AnyObject {
    /// Закачался новый чанк
    ///
    /// - Parameter progress: Объект, содержащий описание прогресса
    func downloadProgressUpdated(progress: FileDownloadProgress)

    /// Вызывается, когда скачка началась
    func downloadBegan()

    /// Вызывается, когда скачка закончилась успешно
    func downloadFinished()

    /// Когда произошла ошибка при скачивании
    ///
    /// - Parameter error: ошибка
    func downloadFailed(_ error: Error)
}

public protocol Downloadable: AnyObject {

    /// Фабричный конструктор
    ///
    /// - Parameter downloadableUniqueId: уникальный ид для создания объекта
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
//
//    var downloadStatusListner: DownloadStatusListner? { get set }

}

public extension Downloadable {
    func observe(by: AnyObject) {
//        DownloadService.shared
    }
}

public extension Downloadable {
    public func resumeDownload() throws -> Self {
        let object = DownloadService.shared.bind(some: self)
        return try DownloadService.shared.resumeDownload(object)
    }

    public func cancelDownload() {
        DownloadService.shared.cancelDownload(self)
    }

    public var isDownloading: Bool {
        return DownloadService.shared.isDownloading(self)
    }
}

public extension Downloadable {
    public var isDownloadLocalFileExist: Bool {
        return FileManager.default.fileExists(atPath: downloadLocalUrl.path)
    }
}
