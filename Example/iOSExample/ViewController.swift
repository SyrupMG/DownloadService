//
//  ViewController.swift
//  iOSExample
//
//  Created by Лысенко Алексей Димитриевич on 17.09.2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import UIKit
import DownloadService

class BasicDownloadableCell: UITableViewCell, DownloadStatusListner {
    fileprivate static let identifier: String = "basicCell"
    
    var downloadable: BasicDownloadable? {
        didSet {
            guard let downloadable = self.downloadable else { return }
            bindedDownlodable = DownloadService.shared.bind(some: downloadable)
            if bindedDownlodable?.isDownloadLocalFileExist ?? false {
                self.detailTextLabel?.text = "finished"
            }
            self.textLabel?.text = downloadable.name
        }
    }

    private var bindedDownlodable: Downloadable? {
        didSet { bindedDownlodable?.downloadStatusListner = self }
    }
    
    func handlePress() throws {
        if bindedDownlodable?.isDownloading() ?? false {
            bindedDownlodable?.cancelDownload()
            self.detailTextLabel?.text = "cancelled"
        } else {
            if !(bindedDownlodable?.isDownloadLocalFileExist ?? false) {
                bindedDownlodable = try bindedDownlodable?.resumeDownload()
            }
        }
    }
    
    // MARK: - actions
    func editActions() -> [UITableViewRowAction]? {
        var actions: [UITableViewRowAction] = []
        
        if (bindedDownlodable?.isDownloadLocalFileExist ?? false) {
            let deleteAction = UITableViewRowAction(style: .destructive, title: "Удалить загрузку") { action, indexPath in
                guard let localUrl = self.bindedDownlodable?.downloadLocalUrl else { return }
                
                do {
                    try FileManager.default.removeItem(at: localUrl)
                    self.detailTextLabel?.text = nil
                } catch { }
            }
            actions.append(deleteAction)
        }
        
        return actions
    }
    
    // MARK: - init
    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        detailTextLabel?.numberOfLines = 0
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    // MARK: - loading listner
    func downloadBegan() {
        self.detailTextLabel?.text = "began"
    }
    func downloadFinished() {
        self.detailTextLabel?.text = "finished"
    }
    func downloadFailed(_ error: Error) {
        self.detailTextLabel?.text = "error: "+error.localizedDescription
    }
    func downloadProgressUpdated(progress: FileDownloadProgress) {
        self.detailTextLabel?.text = "progress: \(progress.downloadProgress * 100)%"
    }
}

let filesLinks = [
    "SpeedTest_16MB.dat":"http://mirror.filearena.net/pub/speed/SpeedTest_16MB.dat",
    "SpeedTest_32MB.dat":"http://mirror.filearena.net/pub/speed/SpeedTest_32MB.dat",
    "SpeedTest_64MB.dat":"http://mirror.filearena.net/pub/speed/SpeedTest_64MB.dat",
    "SpeedTest_128MB.dat":"http://mirror.filearena.net/pub/speed/SpeedTest_128MB.dat",
    "SpeedTest_256MB.dat":"http://mirror.filearena.net/pub/speed/SpeedTest_256MB.dat",
    "SpeedTest_512MB.dat":"http://mirror.filearena.net/pub/speed/SpeedTest_512MB.dat",
    "SpeedTest_1024MB.dat":"http://mirror.filearena.net/pub/speed/SpeedTest_1024MB.dat"
]

class BasicDownloadable: Downloadable {    
    var name: String
    weak var downloadStatusListner: DownloadStatusListner?

    var downloadUniqueId: String { return name }
    var downloadRemoteUrl: URL
    
    required init?(_ downloadableUniqueId: String) {
        guard let remoteUrlString = filesLinks[downloadableUniqueId],
            let remoteUrl = URL(string: remoteUrlString) else { return nil }
        self.name = downloadableUniqueId
        self.downloadRemoteUrl = remoteUrl
    }
    
    static let localPath: URL = {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return directory!.appendingPathComponent("BasicDownloadable", isDirectory: true)
    }()
    
    var downloadLocalUrl: URL {
        return BasicDownloadable.localPath.appendingPathComponent(downloadUniqueId)
    }
}

class ViewController: UIViewController {
    @IBOutlet private weak var tableView: UITableView!
    
    private lazy var downloadables: [BasicDownloadable] = filesLinks.compactMap { BasicDownloadable($0.key) }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(BasicDownloadableCell.self, forCellReuseIdentifier: BasicDownloadableCell.identifier)
        
        _ = DownloadService.shared.onReady.done { _ in
            print("service ready")
        }
        DownloadService.shared.register(BasicDownloadable.self)
        // Do any additional setup after loading the view, typically from a nib.
    }
}

extension ViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let cell = cell as? BasicDownloadableCell else { return }
        cell.downloadable = downloadables[indexPath.row]
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let cell = tableView.cellForRow(at: indexPath) as? BasicDownloadableCell else { return }
        try? cell.handlePress()
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard let cell = tableView.cellForRow(at: indexPath) as? BasicDownloadableCell else { return nil }
        return cell.editActions()
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return downloadables.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return tableView.dequeueReusableCell(withIdentifier: BasicDownloadableCell.identifier, for: indexPath)
    }
}