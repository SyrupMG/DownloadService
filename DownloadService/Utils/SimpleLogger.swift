//
//  SimpleLogger.swift
//  DownloadService
//
//  Created by Лысенко Алексей Димитриевич on 17.09.2018.
//

import Foundation

public class SimpleLogger: Logger {
    public func info(_ string: String) {
        print("INFO 💙: ", string)
    }
    
    public func error(_ string: String) {
        print("ERROR 💔:", string)
    }
}
