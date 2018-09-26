//
//  PendingDownloadObject.swift
//  DownloadService
//
//  Created by Лысенко Алексей Димитриевич on 26.09.2018.
//

import Foundation

struct PendingDownloadObject {
    var downloadToken: String
    var resumeData: Data?
    var remoteURL: URL
}
