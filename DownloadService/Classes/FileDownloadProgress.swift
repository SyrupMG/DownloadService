//
//  FileDownloadProgress.swift
//  DownloadService
//
//  Created by Лысенко Алексей Димитриевич on 18.09.2018.
//

import Foundation
import HWIFileDownload

public struct FileDownloadProgress {
    init(_ hwiProgress: HWIFileDownloadProgress) {
        self.downloadProgress = Double(hwiProgress.downloadProgress)
        self.expectedFileSize = Int(hwiProgress.expectedFileSize)
        self.receivedFileSize = Int(hwiProgress.receivedFileSize)
        self.estimatedRemainingTime = hwiProgress.estimatedRemainingTime
        self.bytesPerSecondSpeed = Int(hwiProgress.bytesPerSecondSpeed)
        self.lastLocalizedDescription = hwiProgress.lastLocalizedDescription
        self.lastLocalizedAdditionalDescription = hwiProgress.lastLocalizedAdditionalDescription
        self.nativeProgress = hwiProgress.nativeProgress
    }
    
    /// from 0 to 1
    public var downloadProgress: Double
    public var expectedFileSize: Int
    public var receivedFileSize: Int
    public var estimatedRemainingTime: TimeInterval
    public var bytesPerSecondSpeed: Int
    public var lastLocalizedDescription: String?
    public var lastLocalizedAdditionalDescription: String?
    public var nativeProgress: Progress
}
