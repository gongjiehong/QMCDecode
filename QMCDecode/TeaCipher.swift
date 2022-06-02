//
//  TeaCipher.swift
//  QMCDecode
//
//  Created by 龚杰洪 on 2022/5/19.
//  Copyright © 2022 龚杰洪. All rights reserved.
//

import Foundation

enum TeaCipherError: Error {
    case keySizeInvalid
    case oddNumberOfRoundsSpecified
}

class TeaCipher {
    let blockSize = 8
    let keySize = 16
    let delta: UInt32 = 0x9e3779b9
    let numRounds = 64

    var key0: UInt32
    var key1: UInt32
    var key2: UInt32
    var key3: UInt32
    var rounds: UInt32

    /// 初始化
    /// - Parameters:
    ///   - Key: 原始key
    ///   - rounds: 轮数，默认64
    init(key: [UInt8], rounds: UInt32 = 64) throws {
        if key.count != 16 {
            throw TeaCipherError.keySizeInvalid
        }

        if (rounds & 1) != 0 {
            throw TeaCipherError.oddNumberOfRoundsSpecified
        }

        self.rounds = rounds


        self.key0 = key[0..<16].withUnsafeBytes({
            $0.load(as: UInt32.self).bigEndian
        })

        self.key1 = key[4..<16].withUnsafeBytes({
            $0.load(as: UInt32.self).bigEndian
        })

        self.key2 = key[8..<16].withUnsafeBytes({
            $0.load(as: UInt32.self).bigEndian
        })

        self.key3 = key[12..<16].withUnsafeBytes({
            $0.load(as: UInt32.self).bigEndian
        })
    }

    /// 加密数据
    /// - Parameter src: 原始数据
    /// - Returns: 加密后的数据
    func encrypt(src: [UInt8]) -> [UInt8] {
        var v0 = src[0..<src.count].withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        var v1 = src[4..<src.count].withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        // 此处与运算全部用于处理UInt32溢出，这个煞笔算法整个在32位的框框内运行
        var sum : UInt32 = 0
        for _ in 0..<self.rounds/2 {
            sum = sum &+ delta
            v0 = v0 &+ (((v1<<4) &+ key0) ^ (v1 &+ sum) ^ ((v1>>5) &+ key1))
            v1 = v1 &+ (((v0<<4) &+ key2) ^ (v0 &+ sum) ^ ((v0>>5) &+ key3))
        }

        // 强行转换为大端数据后读取为byte数组
        v0 = CFSwapInt32HostToBig(v0)
        v1 = CFSwapInt32HostToBig(v1)

        var result = [UInt8]()
        let v0Data = Data(bytes: &v0, count: MemoryLayout.size(ofValue: v0))
        result += [UInt8](v0Data)

        let v1Data = Data(bytes: &v1, count: MemoryLayout.size(ofValue: v1))
        result += [UInt8](v1Data)
        return result
    }

    /// 解密数据
    /// - Parameter src: 需要解密的原始数据
    /// - Returns: 解密后的数据
    func decrypt(src: [UInt8]) -> [UInt8] {
        var v0 = src[0..<src.count].withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        var v1 = src[4..<src.count].withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        // 此处与运算全部用于处理UInt32溢出，这个煞笔算法整个在32位的框框内运行
        var sum: UInt32 = delta &* (self.rounds / 2)
        for _ in 0..<self.rounds/2 {
            v1 = v1 &- (((v0<<4) &+ key2) ^ (v0 &+ sum) ^ ((v0>>5) &+ key3))
            v0 = v0 &- (((v1<<4) &+ key0) ^ (v1 &+ sum) ^ ((v1>>5) &+ key1))
            sum = sum &- delta
        }

        // 强行转换为大端数据后读取为byte数组
        v0 = CFSwapInt32HostToBig(v0)
        v1 = CFSwapInt32HostToBig(v1)

        var result = [UInt8]()
        let v0Data = Data(bytes: &v0, count: MemoryLayout.size(ofValue: v0))
        result += [UInt8](v0Data)

        let v1Data = Data(bytes: &v1, count: MemoryLayout.size(ofValue: v1))
        result += [UInt8](v1Data)
        return result
    }
}
