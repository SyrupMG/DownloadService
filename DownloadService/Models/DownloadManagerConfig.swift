//
//  DownloadManagerConfig.swift
//  DownloadService
//
//  Created by Лысенко Алексей Димитриевич on 26.09.2018.
//

import Foundation

public struct DownloadManagerConfig {
    public enum ConcurentDownloads {
        case infinite
        case finite(maxCount: Int)
    }
    
    public var allowsCellularAccess: Bool
    public var concurrentDownloads: ConcurentDownloads
    
    var maxConcurrentFileDownloadsCount: Int {
        switch concurrentDownloads {
        case .infinite:
            return -1
        case .finite(let maxCount):
            return maxCount
        }
    }
    
    static var `default`: DownloadManagerConfig {
        return DownloadManagerConfig(allowsCellularAccess: true, concurrentDownloads: .infinite)
    }
    
    public init(allowsCellularAccess: Bool, concurrentDownloads: ConcurentDownloads) {
        self.allowsCellularAccess = allowsCellularAccess
        self.concurrentDownloads = concurrentDownloads
    }
}
