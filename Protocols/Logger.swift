//
//  Logger.swift
//  DownloadService
//
//  Created by Лысенко Алексей Димитриевич on 17.09.2018.
//

import Foundation

public protocol Logger {
    func info(_ string: String)
    func error(_ string: String)
}
