//
//  FileDownloadProgress.swift
//  DownloadService
//
//  Created by Лысенко Алексей Димитриевич on 18.09.2018.
//

import Foundation
import SMG_HWIFileDownload

/// Information of current download
public struct FileDownloadProgress {
    init(_ hwiProgress: HWIFileDownloadProgress) {
        self.downloadProgress = Double(hwiProgress.downloadProgress)
        self.expectedFileSize = UInt64(hwiProgress.expectedFileSize)
        self.receivedFileSize = UInt64(hwiProgress.receivedFileSize)
        self.estimatedRemainingTime = hwiProgress.estimatedRemainingTime
        self.bytesPerSecondSpeed = UInt(hwiProgress.bytesPerSecondSpeed)
    }

    /// Progress from 0 to 1
    public var downloadProgress: Double
    /// Target file size in bytes
    public var expectedFileSize: UInt64
    /// How many bytes have been downloaded
    public var receivedFileSize: UInt64
    /// Estimated time before completion
    public var estimatedRemainingTime: TimeInterval
    /// Calculated downloading speed
    public var bytesPerSecondSpeed: UInt
}
