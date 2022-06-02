//
//  ViewController.swift
//  QMCDecode
//
//  Created by 龚杰洪 on 2019/8/26.
//  Copyright © 2019 龚杰洪. All rights reserved.
//

import Cocoa

enum QMCDecodeError: Error {
    case inputFileIsInvalid
    case outputDirectoryIsInvalid
    case decodeFailed
    case readFileToStreamFailed
    case outputFileStreamInvalid
    case notError
}

class ViewController: NSViewController {
    @IBOutlet weak var openFolderButton: NSButton!
    @IBOutlet weak var inputFilesTable: NSTableView!
    @IBOutlet weak var outputPathButton: NSButton!
    @IBOutlet weak var ouputPathLabel: NSTextField!
    @IBOutlet weak var currentFolderLabel: NSTextField!
    
    @IBOutlet weak var startButton: NSButton!
    @IBOutlet weak var progressView: NSProgressIndicator!
    
    lazy var outputFolderURL: URL = {
        let path = NSHomeDirectory() + "/Music/QMCConvertOutput/"
        let url = URL(fileURLWithPath: path)
        do {
            let filemanager = FileManager.default
            var isDirectory = ObjCBool(false)
            let fileExists = filemanager.fileExists(atPath: path, isDirectory: &isDirectory)
            if fileExists {
                if isDirectory.boolValue {
                    // do nothing
                } else {
                    try filemanager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                }
            } else {
                try filemanager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            print(error)
        }
        return url
    }()
    
    var dataSource: [URL] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()

        openFolderButton.target = self
        openFolderButton.action = #selector(openInputFolder(_:))
        
        outputPathButton.target = self
        outputPathButton.action = #selector(openOutputFolder(_:))
        
        startButton.target = self
        startButton.action = #selector(startConvert(_:))
        
        setupTableView()

        loadDefaultPath()

        ouputPathLabel.stringValue = outputFolderURL.path
    }
    
    func loadDefaultPath() {
        var path = NSHomeDirectory()
        path += "/Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac/iQmc/"
        let fileManager = FileManager.default
        do {
            let filesPaths = try fileManager.contentsOfDirectory(atPath: path)
            for filePath in filesPaths {
                if encryptExtDictionary.keys.contains(URL(fileURLWithPath: filePath).pathExtension) {
                    let url = URL(fileURLWithPath: path + filePath)
                    dataSource.append(url)
                }
            }
        } catch {
            print(error)
        }
        
        self.currentFolderLabel.stringValue = path
        
        self.inputFilesTable.reloadData()
    }
    
    func setupTableView() {
        inputFilesTable.dataSource = self
        inputFilesTable.delegate = self
    }

    override var representedObject: Any? {
        didSet {
            
        }
    }
    
    @objc func openInputFolder(_ sender: Any) {
        dataSource.removeAll()
        inputFilesTable.reloadData()
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        
        let finded = panel.runModal()
        
        if finded == .OK {
            var directoryArray = [String]()
            for url in panel.urls {
                var isDirectory: ObjCBool = ObjCBool(false)
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                if isDirectory.boolValue == true {
                    do {
                        let filesPaths = try FileManager.default.contentsOfDirectory(atPath: url.path)
                        for filePath in filesPaths {
                            if encryptExtDictionary.keys.contains(URL(fileURLWithPath: filePath).pathExtension) {
                                let fileURL = url.appendingPathComponent(filePath)
                                dataSource.append(fileURL)
                            }
                        }
                    } catch {
                        print(error)
                    }
                    directoryArray.append(url.path)
                } else {
                    if encryptExtDictionary.keys.contains(url.pathExtension.lowercased()) {
                        dataSource.append(url)
                    }
                }
            }
            self.currentFolderLabel.stringValue = directoryArray.joined(separator: "\n")
            inputFilesTable.reloadData()
        } else {
            inputFilesTable.reloadData()
        }
    }
    
    @objc func openOutputFolder(_ sender: Any) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        
        
        let finded = panel.runModal()
        
        if finded == .OK {
            for url in panel.urls {
                self.outputFolderURL = url
                self.ouputPathLabel.stringValue = url.path
                break
            }
        } else {
        }
    }
    
    @objc func startConvert(_ sender: Any) {
        if dataSource.count == 0 {
            let alert = NSAlert(error: QMCDecodeError.inputFileIsInvalid)
            alert.messageText = "没有可供转换的数据"
            alert.icon = NSImage(named: NSImage.Name())
            alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                
            })
        }
        
        self.startButton.isEnabled = false
        
        errorCount = 0
        
        succeedCount = 0
        
        let coreCount = ProcessInfo().processorCount
        
        for index in 0..<dataSource.count {
            let queue = queueArray[index % coreCount]
            queue.async {
                do {
                    let decoder = try QMDecoder(originFilePath: self.dataSource[index].path,
                                                outputDirectory: self.outputFolderURL.path)
                    try decoder.decryptAndWriteToFile()
                    self.progressAppend(index: index, success: true)
                } catch {
                    self.progressAppend(index: index, success: false)
                    print(error)
                }
            }
        }
    }
    
    /// 根据CPU物理核心数组装队列，尽量跑死CPU
    lazy var queueArray: [DispatchQueue] = {
        var result = [DispatchQueue]()
        let coreCount = ProcessInfo().processorCount
        for index in 0..<coreCount {
            result.append(DispatchQueue(label: "QMCDecode.Convert.Queue\(index)", qos: DispatchQoS.utility))
        }
        return result
    }()
    
    var totalCount: Int {
        return dataSource.count
    }
    
    var errorCount: Int = 0
    
    var succeedCount: Int = 0

    func progressAppend(index: Int, success: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            if success {
                strongSelf.succeedCount += 1
            } else {
                strongSelf.errorCount += 1
            }
            
            let succeedCount = strongSelf.succeedCount
            let errorCount = strongSelf.errorCount
            let totalCount = strongSelf.totalCount
            let progress = Double(succeedCount + errorCount + 1) / Double(totalCount) * 100.0
            strongSelf.progressView.doubleValue = progress
            
            if succeedCount + errorCount == totalCount {
                let alert = NSAlert(error: QMCDecodeError.notError)
                alert.alertStyle = .informational
                let messageText = "转换完成 \n成功: \(totalCount - errorCount), 失败: \(errorCount)"
                alert.messageText = messageText
                alert.icon = NSImage(named: NSImage.Name("Success"))
                alert.beginSheetModal(for: strongSelf.view.window!, completionHandler: { (response) in
                    
                })
                self?.startButton.isEnabled = true
            }
        }
    }
}

extension ViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return dataSource.count
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 44.0
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        switch tableColumn?.title {
        case "路径":
            return dataSource[row].path
        case "歌曲名称":
            return dataSource[row].lastPathComponent
        default:
            return nil
        }
    }
}
