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
        
        errorCount = 0
        
        succeedCount = 0
        
        let coreCount = ProcessInfo().processorCount
        
        print(CACurrentMediaTime())
        
        for index in 0..<dataSource.count {
            let queue = queueArray[index % coreCount]
            queue.async {
                self.convertMusic(index: index)
            }
        }
    }
    
    /// 根据CPU物理核心数组装队列，尽量跑死CPU
    lazy var queueArray: [DispatchQueue] = {
        var result = [DispatchQueue]()
        let coreCount = ProcessInfo().processorCount
        for index in 0..<coreCount {
            result.append(DispatchQueue(label: "QMCDecode.Convert.Queue\(index)", qos: DispatchQoS.default))
        }
        return result
    }()
    
    var totalCount: Int {
        return dataSource.count
    }
    
    var errorCount: Int = 0
    
    var succeedCount: Int = 0
    
    let bufferSize: Int = 10_240
    
    var decoder: QMCDecoder = QMCDecoder()
    
    func convertMusic(index: Int) {
        autoreleasepool {
            do {
                let url = dataSource[index]
                
                guard let readStream = InputStream(url: url) else {
                    throw QMCDecodeError.readFileToStreamFailed
                }
                readStream.open()
                defer { readStream.close() }
                
                
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
                
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                
                guard let outputStream = OutputStream(url: outputURL, append: true) else {
                    throw QMCDecodeError.outputFileStreamInvalid
                }
                outputStream.open()
                defer {
                    outputStream.close()
                }
                
                var offset: Int = 0
                
                while readStream.hasBytesAvailable {
                    var buffer = [UInt8](repeating: 0, count: bufferSize)
                    let bytesRead = readStream.read(&buffer, maxLength: bufferSize)
                    
                    if let streamError = readStream.streamError {
                        throw streamError
                    }
                    
                    if bytesRead > 0 {
                        var readData = Data(buffer)
                        if buffer.count != bytesRead {
                            readData = Data(buffer[0..<bytesRead])
                        }
                        
                        let resultData = decoder.qmcCryptoTransform(data: readData,
                                                                    offset: offset,
                                                                    size: bytesRead)
                        _ = resultData.withUnsafeBytes({ (rawBufferPointer: UnsafeRawBufferPointer) -> Int in
                            let bufferPointer = rawBufferPointer.bindMemory(to: UInt8.self)
                            return outputStream.write(bufferPointer.baseAddress!, maxLength: bytesRead)
                        })
                        
                        offset += bytesRead
                    } else {
                        break
                    }
                }
                
                self.progressAppend(index: index, success: true)
            } catch {
                print(error)
                self.progressAppend(index: index, success: false)
            }
        }
    }
    
    func progressAppend(index: Int, success: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.progressView.doubleValue = Double(strongSelf.succeedCount + strongSelf.errorCount + 1) / Double(strongSelf.dataSource.count) * 100.0
            
            if success {
                strongSelf.succeedCount += 1
            } else {
                strongSelf.errorCount += 1
            }
            
            if strongSelf.succeedCount + strongSelf.errorCount == strongSelf.totalCount {
                let alert = NSAlert(error: QMCDecodeError.notError)
                alert.alertStyle = .informational
                alert.messageText = "All done \n Success: \(strongSelf.totalCount - strongSelf.errorCount), Failed: \(strongSelf.errorCount)"
                alert.icon = NSImage(named: NSImage.Name("Success"))
                alert.beginSheetModal(for: strongSelf.view.window!, completionHandler: { (response) in
                    
                })
                print(CACurrentMediaTime())
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
