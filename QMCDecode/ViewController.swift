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
    case notError
}

class ViewController: NSViewController {

    
    @IBOutlet weak var openFolderButton: NSButton!
    @IBOutlet weak var inputFilesTable: NSTableView!
    @IBOutlet weak var outputPathButton: NSButton!
    @IBOutlet weak var ouputPathLabel: NSTextField!
    
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
        let path = NSHomeDirectory() + "/Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac/iQmc/"
        let fileManager = FileManager.default
        do {
            let filesPaths = try fileManager.contentsOfDirectory(atPath: path)
            for filePath in filesPaths {
                if filePath.range(of: "qmc") != nil {
                    let url = URL(fileURLWithPath: path + filePath)
                    dataSource.append(url)
                }
            }
        } catch {
            print(error)
        }
        
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
            for url in panel.urls {
                if url.pathExtension.lowercased().range(of: "qmc") != nil {
                    dataSource.append(url)
                }
            }
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
            alert.messageText = "Invalid data to be converted"
            alert.icon = NSImage(named: NSImage.Name())
            alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                
            })
        }
        
        // 串行队列，每次只处理一个，避免内存爆炸，可使用filestrem解决内存问题，但是我懒得写
        DispatchQueue(label: "convert").async {
            self.convertMusic(index: 0)
        }
    }
    
    var totalCount: Int {
        return dataSource.count
    }
    
    var errorCount: Int = 0
    
    func convertMusic(index: Int) {
        do {
            let url = dataSource[index]
            let data = try Data(contentsOf: url)
            
            let decoder = QMCDecoder()
            let result = decoder.qmcCryptoTransform(data: data, offset: 0, size: data.count)
            
            
            var outputURL = outputFolderURL
            
            switch url.pathExtension.lowercased() {
            case "qmcflac":
                outputURL.appendPathComponent(url.lastPathComponent)
                outputURL.deletePathExtension()
                outputURL.appendPathExtension("flac")
                break
            case "qmc0", "qmc3":
                outputURL.appendPathComponent(url.lastPathComponent)
                outputURL.deletePathExtension()
                outputURL.appendPathExtension("mp3")
                break
            default:
                break
            }
            
            try result.write(to: outputURL)
            DispatchQueue.main.async {
                self.progressView.doubleValue = Double(index + 1) / Double(self.dataSource.count) * 100.0
            }
        } catch {
            DispatchQueue.main.async {
                self.progressView.doubleValue = Double(index + 1) / Double(self.dataSource.count) * 100.0
            }
            print(error)
            
            errorCount += 1
        }
        if index + 1 < dataSource.count {
            convertMusic(index: index + 1)
        } else {
            DispatchQueue.main.async {
                let alert = NSAlert(error: QMCDecodeError.notError)
                alert.messageText = "Success: \(self.totalCount - self.errorCount), Failed: \(self.errorCount)"
                alert.icon = NSImage(named: NSImage.Name("Success"))
                alert.alertStyle = .informational
                alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                    
                })
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
        case "Path":
            return dataSource[row].path
        case "Name":
            return dataSource[row].lastPathComponent
        default:
            return nil
        }
    }
}
