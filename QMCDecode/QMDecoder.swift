//
//  QMCDecoder.swift
//  QMCDecode
//
//  Created by 龚杰洪 on 2022/1/10.
//  Copyright © 2022 龚杰洪. All rights reserved.
//

import Foundation

class QMDecoder {
    enum DecoderError: Error {
        case unsupportFileExtension(ext: String)
        case canNotReadFile
        case canNotReadFileByStream
        case canNotGetFileLength
        case canNotReadSizeBuffer
        case canNotReadRawKeyBuffer
        case searchRawKeyFailed
    }

    private let commaASCIICode: UInt8 = Character(",").asciiValue ?? 44


    private let originFilePath: String
    private let outputDirectory: String
    private let readStream: InputStream
    private let originFileLength: Int

    private var realAudioSize: Int = 0

    private var cipher: QMCipher?

    init(originFilePath: String, outputDirectory: String) throws {
        self.originFilePath = originFilePath
        self.outputDirectory = outputDirectory
        guard let fileStream = InputStream(fileAtPath: originFilePath) else {
            throw DecoderError.canNotReadFileByStream
        }
        self.readStream = fileStream

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: originFilePath)
        guard let fileLength = fileAttributes[FileAttributeKey.size] as? Int else {
            throw DecoderError.canNotGetFileLength
        }
        self.originFileLength = fileLength

        try searchKey()
    }

    func decryptAndWriteToFile() throws {
        let fileURL = URL(fileURLWithPath: originFilePath)
        let fileExtension = fileURL.pathExtension
        if fileExtension.count > 0, let extAndVersion = encryptExtDictionary[fileExtension], let cipher = self.cipher {
            let fileHandle = FileHandle(forReadingAtPath: originFilePath)
            if let fileData = try fileHandle?.read(upToCount: self.realAudioSize) {
                let decodeData = cipher.qmDecrypt(data: fileData, offset: 0)
                var outputURL = URL(fileURLWithPath: self.outputDirectory)
                outputURL.appendPathComponent(fileURL.lastPathComponent)
                outputURL.deletePathExtension()
                outputURL.appendPathExtension(extAndVersion.ext)
                try decodeData.write(to: outputURL, options: Data.WritingOptions.atomic)
            } else {
                throw DecoderError.canNotReadFile
            }
        } else {
            throw DecoderError.unsupportFileExtension(ext: fileExtension)
        }
    }

    func matchingDecoder(_ extAndVersion: ExtensionAndVersion) throws {
        if extAndVersion.version == .v2 {

        } else {

        }
    }

    func searchKey() throws {
        guard let fileHandle = FileHandle(forReadingAtPath: originFilePath) else {
            throw DecoderError.canNotReadFile
        }
        defer {
            try? fileHandle.close()
        }

        try fileHandle.seek(toOffset: UInt64(self.originFileLength - 4))
        guard let lastFourBytes = try fileHandle.readToEnd() else {
            throw DecoderError.canNotReadFile
        }

        // 移动端下载的用,以QTag结尾
        if String(bytes: lastFourBytes, encoding: String.Encoding.utf8) == "QTag" {
            // 读取key长度
            try fileHandle.seek(toOffset: UInt64(self.originFileLength - 8))
            guard let sizeBuffer = try fileHandle.read(upToCount: 4) else {
                throw DecoderError.canNotReadFile
            }
            let keySize = sizeBuffer.withUnsafeBytes {
                $0.load(as: UInt32.self).bigEndian
            }

            // 计算真实音频长度
            self.realAudioSize = self.originFileLength - Int(keySize) - 8

            // 读取原始key
            try fileHandle.seek(toOffset: UInt64(self.realAudioSize))
            guard let rawKey = try fileHandle.read(upToCount: Int(keySize)) else {
                throw DecoderError.canNotReadRawKeyBuffer
            }

            // 通过逗号找到key结束位置
            guard let keyEndIndex = rawKey.firstIndex(of: commaASCIICode) else {
                throw DecoderError.searchRawKeyFailed
            }

            // 通过原始key和key结束位置组装解码器
            try setCipher(keyBuffer: [UInt8]([UInt8](rawKey)[0..<keyEndIndex]))
        } else {
            // PC macOS端下载的文件
            let keySize = lastFourBytes.withUnsafeBytes {
                $0.load(as: UInt32.self).littleEndian
            }

            if keySize < 0x300 {
                // key 在固定位置
                self.realAudioSize = self.originFileLength - Int(keySize) - 4
                try fileHandle.seek(toOffset: UInt64(self.realAudioSize))
                guard let rawKey = try fileHandle.read(upToCount: Int(keySize)) else {
                    throw DecoderError.canNotReadRawKeyBuffer
                }

                try setCipher(keyBuffer: [UInt8](rawKey))
            } else {
                // 用固定key解码
                self.realAudioSize = self.originFileLength
                self.cipher = try QMStaticCipher(originKey: privateKey256)
            }
        }
    }

    func setCipher(keyBuffer: [UInt8]) throws {
        let keyDecoder = QMCKeyDecoder()
        let decodedKey = try keyDecoder.deriveKey(keyBuffer)

        if decodedKey.count > 300 {
            self.cipher = try QMRC4Cipher(originKey: decodedKey)
        } else {
            self.cipher = try QMMapCipher(originKey: decodedKey)
        }
    }
}
