//
//  QMCDecoder.swift
//  QMCDecode
//
//  Created by 龚杰洪 on 2019/8/26.
//  Copyright © 2019 龚杰洪. All rights reserved.
//

import Foundation

/// 解码器协议，通过原始数据和偏移量进行解密
public protocol QMCipher {
    func qmDecrypt(data: Data, offset: Int) -> Data
    init(originKey: [UInt8]) throws
}

public enum QMCipherError: Error {
    case invalidKeyLength
}

/// QMStaticCipher 固定key解码器
public class QMStaticCipher: QMCipher {
    var key: [UInt8]
    var keyLength: Int

    required public init(originKey: [UInt8]) throws {
        if originKey.count == 0 {
            throw QMCipherError.invalidKeyLength
        }
        self.key = originKey
        self.keyLength = key.count
    }

    public func qmDecrypt(data: Data, offset: Int) -> Data {
        var resultArray = [UInt8](repeating: 0, count: data.count)
        for (index, byte) in data.enumerated() {
            resultArray[index] = byte ^ getMask(offset: offset + index)
        }
        return Data(resultArray)
    }

    public func getMask(offset: Int) -> UInt8 {
        let temp = offset > 0x7FFF ? (offset % 0x7FFF) : offset
        let index = (temp * temp + 27) & 0xFF
        return key[index]
    }
}

/// QMMapCipher 翻转解码
public class QMMapCipher: QMCipher {
    var key: [UInt8]
    var keyLength: Int

    required public init(originKey: [UInt8]) throws {
        if originKey.count == 0 {
            throw QMCipherError.invalidKeyLength
        }
        self.key = originKey
        self.keyLength = key.count
    }

    public func qmDecrypt(data: Data, offset: Int) -> Data {
        var resultArray = [UInt8](repeating: 0, count: data.count)
        for (index, byte) in data.enumerated() {
            resultArray[index] = byte ^ getMask(offset: offset + index)
        }
        return Data(resultArray)
    }

    public func getMask(offset: Int) -> UInt8 {
        let temp = offset > 0x7FFF ? (offset % 0x7FFF) : offset
        let index = (temp * temp + 71_214) & 0xFF
        return rotate(value: key[index], bits: index & 0x7)
    }

    func rotate(value: UInt8, bits: Int) -> UInt8 {
        let rotate = (bits + 4) % 8
        let left = value << rotate
        let right = value >> rotate
        return (left | right) & 0xff
    }
}

public class QMRC4Cipher: QMCipher {
    private let firstSegmentSize: Int = 0x80 // 128
    private let segmentSize: Int = 0x1_400 //5_120

    let originKey: [UInt8]
    let originKeyLength: Int
    let seedBox: [UInt8]
    var hashValue: UInt32

    required public init(originKey: [UInt8]) throws {
        if originKey.count == 0 {
            throw QMCipherError.invalidKeyLength
        }

        self.originKey = originKey

        let keyLength = originKey.count
        self.originKeyLength = keyLength

        var seedBox: [UInt8] = [UInt8](repeating: 0, count: keyLength)
        for index in 0..<keyLength {
            seedBox[index] = UInt8(index & 0xff)
        }

        var tempIndex: Int = 0
        for index in 0..<keyLength {
            tempIndex = (Int(seedBox[index]) + tempIndex + Int(originKey[index % keyLength])) % keyLength
            (seedBox[index], seedBox[tempIndex]) = (seedBox[tempIndex], seedBox[index])
        }
        self.seedBox = seedBox

        self.hashValue = 1

        for index in 0..<keyLength {
            let value = originKey[index]
            if value == 0 {
                continue
            }

            let nextHash = (self.hashValue &* UInt32(value)) & 0xffffffff
            if nextHash == 0 || nextHash <= self.hashValue {
                break
            }

            self.hashValue = nextHash
        }
    }

    func getSegmentKey(index: Int) -> Int {
        let seed = self.originKey[index % self.originKeyLength]
        let resultValue = Int(floor(((Double(self.hashValue) / (Double(index + 1) * Double(seed))) * 100)))
        return resultValue % self.originKeyLength
    }

    public func qmDecrypt(data: Data, offset: Int) -> Data {
        let size = data.count
        var toProcess = size
        var processed = 0
        var newOffset = offset

        @discardableResult
        func postProcessed(length: Int) -> Bool {
            toProcess -= length
            processed += length
            newOffset += length
            return toProcess == 0
        }

        // 初始片段
        var resultArray = [UInt8](data)
        if newOffset < firstSegmentSize {
            let processLength = min(size, firstSegmentSize - newOffset)
            var tempBuffer = [UInt8](resultArray[0..<processLength])
            encodeFirstSegment(data: &tempBuffer, offset: newOffset)
            resultArray.replaceSubrange(0..<processLength, with: tempBuffer)
            if postProcessed(length: processLength) {
                return Data(resultArray)
            }
        }

        // 对齐片段
        if newOffset % segmentSize != 0 {
            let processLength = min(segmentSize - (newOffset % segmentSize), toProcess)
            var tempBuffer = [UInt8](resultArray[processed..<processed+processLength])
            encodeAllSegment(data: &tempBuffer, offset: newOffset)
            resultArray.replaceSubrange(processed..<processed+processLength, with: tempBuffer)
            if postProcessed(length: processLength) {
                return Data(resultArray)
            }
        }

        // 批处理段
        while toProcess > segmentSize {
            var tempBuffer = [UInt8](resultArray[processed..<processed+segmentSize])
            encodeAllSegment(data: &tempBuffer, offset: newOffset)
            resultArray.replaceSubrange(processed..<processed+segmentSize, with: tempBuffer)
            postProcessed(length: segmentSize)
        }

        // 最后剩余片段
        if toProcess > 0 {
            var tempBuffer = [UInt8](resultArray[processed..<resultArray.count])
            encodeAllSegment(data: &tempBuffer, offset: newOffset)
            resultArray.replaceSubrange(processed..<resultArray.count, with: tempBuffer)
        }

        return Data(resultArray)
    }

    func encodeFirstSegment(data: inout [UInt8], offset: Int) {
        for index in 0..<data.count {
            data[index] ^= self.originKey[getSegmentKey(index: index + offset)]
        }
    }

    func encodeAllSegment(data: inout [UInt8], offset: Int) {
        var newSeedBox = [UInt8](self.seedBox)

        let skipLength = (offset % segmentSize) + self.getSegmentKey(index: offset / segmentSize)

        var left: Int = 0
        var right: Int = 0
        for index in -skipLength..<data.count {
            left = (left + 1) % self.originKeyLength
            right = (Int(newSeedBox[left]) + right) % self.originKeyLength

            (newSeedBox[right], newSeedBox[left]) = (newSeedBox[left], newSeedBox[right])

            if index >= 0 {
                let seedValue = Int(newSeedBox[left]) + Int(newSeedBox[right])
                data[index] ^= newSeedBox[seedValue % self.originKeyLength]
            }
        }
    }
}
