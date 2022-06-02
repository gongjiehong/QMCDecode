//
//  QMCKeyDec.swift
//  QMCDecode
//
//  Created by 龚杰洪 on 2022/5/19.
//  Copyright © 2022 龚杰洪. All rights reserved.
//

import Foundation

enum QMCKeyDecoderError: Error {
    case inBufferSizeInvalidWithBlockSize
    case inBufferSizeToSmall
    case zeroCheckFailed
    case canNotConstructBase64Key
    case keyLengthTooShort
    case invalidPaddingLength
}

class QMCKeyDecoder {
    let saltLength = 2
    let zeroLength = 7

    /// 查找key
    /// - Parameter rawKey: 原始key
    /// - Returns: 计算后的key
    func deriveKey(_ rawKey: [UInt8]) throws -> [UInt8] {
        let base64Key = Data(bytes: rawKey, count: rawKey.count)
        guard let base64DecodedKey = Data(base64Encoded: base64Key) else {
            throw QMCKeyDecoderError.canNotConstructBase64Key
        }

        if base64DecodedKey.count < 16 {
            throw QMCKeyDecoderError.keyLengthTooShort
        }

        let simpleKey = simpleMakeKey(seed: 106, length: 8)
        var teaKey = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            teaKey[index << 1] = simpleKey[index]
            teaKey[(index << 1) + 1] = base64DecodedKey[index]
        }

        let inBuffer = [UInt8](base64DecodedKey[8..<base64DecodedKey.count])
        let subBuffer = try decryptTencentTea(inBuffer: inBuffer, key: teaKey)

        let newKey = base64DecodedKey[0...7] + subBuffer

        return [UInt8](newKey)
    }

    /// 生成simple key
    /// - Parameters:
    ///   - seed: 密码盐
    ///   - length: buffer长度
    /// - Returns: 组装好的simplekey
    fileprivate func simpleMakeKey(seed: UInt8, length: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: length)
        for index in 0..<length {
            result[index] = UInt8(fabs(tan(Double(seed) + Double(index) * 0.1)) * 100.0)
        }
        return result
    }

    /// tea解密
    /// - Parameters:
    ///   - inBuffer: 输入数据
    ///   - key: 解密key
    /// - Returns: 解密结果
    fileprivate func decryptTencentTea(inBuffer: [UInt8], key: [UInt8]) throws -> [UInt8] {
        if inBuffer.count % 8 != 0 {
            throw QMCKeyDecoderError.inBufferSizeInvalidWithBlockSize
        }

        if inBuffer.count < 16 {
            throw QMCKeyDecoderError.inBufferSizeToSmall
        }

        let teaCipher = try TeaCipher(key: key, rounds: 32)

        var tempBuffer = teaCipher.decrypt(src: inBuffer)

        let paddingLength = Int(tempBuffer[0] & 0x7)
        let outputLength = inBuffer.count - 1 - paddingLength - saltLength - zeroLength

        if paddingLength + saltLength != 8 {
            throw QMCKeyDecoderError.invalidPaddingLength
        }

        var outputBuffer = [UInt8](repeating: 0, count: outputLength)

        var ivPrevious = [UInt8](repeating: 0, count: 8)
        var ivCruuent = [UInt8](inBuffer[0...7])
        var inBufferPosition = 8

        var tempIndex = 1 + paddingLength

        // CBC IV
        func cryptBlock() {
            ivPrevious = ivCruuent
            ivCruuent = [UInt8](inBuffer[inBufferPosition...inBufferPosition+7])
            for j in 0..<8 {
                tempBuffer[j] ^= ivCruuent[j]
            }

            tempBuffer = teaCipher.decrypt(src: tempBuffer)
            inBufferPosition += 8
            tempIndex = 0
        }

        // 不处理salt
        var saltIndex = 1
        while saltIndex <= saltLength {
            if tempIndex < 8 {
                tempIndex += 1
                saltIndex += 1
            } else {
                cryptBlock()
            }
        }

        // 解密为原文
        var outputBufferPosition = 0

        while outputBufferPosition < outputLength {
            if tempIndex < 8 {
                outputBuffer[outputBufferPosition] = tempBuffer[tempIndex] ^ ivPrevious[tempIndex]
                outputBufferPosition += 1
                tempIndex += 1
            } else {
                cryptBlock()
            }
        }

        // 验证应为0的位置是否为0
        for _ in 1...zeroLength {
            if tempBuffer[tempIndex] != ivPrevious[tempIndex] {
                throw QMCKeyDecoderError.zeroCheckFailed
            }
        }
        return outputBuffer
    }
}
