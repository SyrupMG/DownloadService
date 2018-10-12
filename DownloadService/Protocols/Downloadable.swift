//
//  Downloadable.swift
//
//  Created by Alexey Lysenko on 11.04.18.
//  Copyright © 2018 SL Tech. All rights reserved.
//

import Foundation

/// Observer for `Downloadable` retrieving progress
public protocol DownloadStatusListner: AnyObject {
    /// Next data chunk is downloaded
    ///
    /// - Parameter progress: object downloading progress struct
    func downloadProgressUpdated(progress: FileDownloadProgress)

    /// Called when `Downloadable` is being started to download
    func downloadBegan()

    /// Called when downloading is successfully finished
    func downloadFinished()

    /// Called when downloading failed
    ///
    /// - Parameter error: reason of failure
    func downloadFailed(_ error: Error)
}

/// Protocol for observing, binding and (re)creating objects which can be downloaded
public protocol Downloadable: AnyObject {

    /// Fabric initializer
    ///
    /// - Parameter downloadableUniqueId: unique ID for identifying specific object in this type of objects
    init?(_ downloadableUniqueId: String)

    /// Unique ID for identifying specific object in this type of objects
    var downloadUniqueId: String { get }

    /// Remote file/source URL
    var downloadRemoteUrl: URL { get }

    /// Local/target URL
    var downloadLocalUrl: URL { get }

}

public extension Downloadable {
    /// Adding listener who observes this `Downloadable` downloading progress
    ///
    /// - Parameter observer: observer which listenes
    func observe(by observer: DownloadStatusListner) {
        DownloadService.shared.register(listener: observer, for: self)
    }
}

public extension Downloadable {
    /// Returns object which is binded to download service. It could be not the same as self!
    internal var binded: Self {
        return DownloadService.shared.bind(some: self)
    }

    /// Starts/Resumes download. Should not be called before downloading service is ready - can appear multiple identical downloads.
    ///
    /// - Returns: returns object which is binded to dowload service and can be observed etc.
    public func resumeDownload() -> Self {
        return try! DownloadService.shared.resumeDownload(self.binded)
    }

    /// Cancelles downloading
    public func cancelDownload() {
        DownloadService.shared.cancelDownload(self)
    }

    /// Gets downloading status
    public var isDownloading: Bool {
        return DownloadService.shared.isDownloading(self)
    }
}

public extension Downloadable {
    /// Checks if file already downloaded
    public var isDownloadLocalFileExist: Bool {
        return FileManager.default.fileExists(atPath: downloadLocalUrl.path)
    }
}
