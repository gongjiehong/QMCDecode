//
//  QMCDecoder.swift
//  QMCDecode
//
//  Created by 龚杰洪 on 2019/8/26.
//  Copyright © 2019 龚杰洪. All rights reserved.
//

import Foundation

public protocol QMCipher {
    func qmDecrypt(data: Data, offset: Int, size: Int) -> Data
}

public class QMStaticCipher: QMCipher {
    public func qmDecrypt(data: Data, offset: Int, size: Int) -> Data {
        var resultArray = [UInt8](repeating: 0, count: size)
        for (index, byte) in data.enumerated() {
            resultArray[index] = byte ^ getMask(offset: offset + index)
        }
        return Data(resultArray)
    }

    public func getMask(offset: Int) -> UInt8 {
        if offset > 0x7FFF {
            return privateKey128[(offset % 0x7FFF) & 0x7F]
        } else {
            return privateKey128[offset & 0x7F]
        }
    }
}

public class QMMapCipher: QMCipher {
    var key: [UInt8]
    var keyLength: Int

    public init(key: [UInt8]) {
        self.key = key
        self.keyLength = key.count
    }

    public func qmDecrypt(data: Data, offset: Int, size: Int) -> Data {
        return Data()
    }

    public func getMask(offset: Int) -> UInt8 {
        let seed = key[]
        const seed = this.key[id % this.N];
        const idx = ((this.hash / ((id + 1) * seed)) * 100.0) | 0;
        return idx % this.N;
        if offset > 0x7FFF {
            return privateKey128[(offset % 0x7FFF) & 0x7F]
        } else {
            return privateKey128[offset & 0x7F]
        }
    }

    func rotate(value: UInt8, bits: UInt8) -> UInt8 {
        let rotate = (bits + 4) % 8
        let left = value << rotate
        let right = value >> rotate
        return (left | right) & 0xff
    }
}

