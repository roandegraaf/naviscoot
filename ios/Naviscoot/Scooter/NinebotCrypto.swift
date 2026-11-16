import CommonCrypto
import CryptoKit
import Foundation

struct NinebotCrypto {
    enum Failure: Error, Equatable {
        case frameTooShort
        case integrityCheckFailed
    }

    static let firmwareKey: [UInt8] = [0x97, 0xCF, 0xB8, 0x02, 0x84, 0x41, 0x43, 0xDE, 0x56, 0x00, 0x2B, 0x3B, 0x34, 0x78, 0x0A, 0x5D]

    static let headerLength = 3
    static let tailLength = 6

    private var aesKey: [UInt8]
    private var auth = [UInt8](repeating: 0, count: 16)
    private var counter: UInt32 = 0

    init(key1: [UInt8], key2: [UInt8]?) {
        aesKey = Self.deriveKey(key1, key2)
    }

    static func deriveKey(_ key1: [UInt8], _ key2: [UInt8]?) -> [UInt8] {
        let material = padded(key1, to: 16) + padded(key2 ?? [], to: 16)
        return Array(Insecure.SHA1.hash(data: material).prefix(16))
    }

    mutating func rekey(key1: [UInt8], key2: [UInt8]?) {
        aesKey = Self.deriveKey(key1, key2)
    }

    // The first frame encrypted after this carries counter 2, as the Segway app does.
    mutating func startCountedMode(auth: [UInt8]) {
        self.auth = Self.padded(auth, to: 16)
        counter = 1
    }

    mutating func encrypt(_ plaintext: [UInt8]) -> [UInt8] {
        let header = Array(plaintext.prefix(Self.headerLength))
        let payload = Array(plaintext.dropFirst(Self.headerLength))
        guard counter > 0 else {
            let keystream = aes(Self.firmwareKey)
            let checksum = Self.checksum(payload)
            return header + xorRepeating(payload, keystream) + [0, 0, UInt8(checksum & 0xFF), UInt8(checksum >> 8), 0, 0]
        }
        counter += 1
        let nonce = Self.nonce(counter: counter, auth: auth)
        let tag = mac(plaintext, nonce: nonce)
        let tagMask = aes(Self.counterBlock(nonce, 0))
        let encryptedTag = zip(tag, tagMask).map { $0 ^ $1 }
        return header + ctr(payload, nonce: nonce) + encryptedTag + [UInt8((counter >> 8) & 0xFF), UInt8(counter & 0xFF)]
    }

    static func counter(of frame: [UInt8]) -> UInt32? {
        guard frame.count >= headerLength + tailLength else { return nil }
        return UInt32(frame[frame.count - 2]) << 8 | UInt32(frame[frame.count - 1])
    }

    func decrypt(_ frame: [UInt8]) throws -> [UInt8] {
        guard frame.count >= Self.headerLength + Self.tailLength else { throw Failure.frameTooShort }
        let header = Array(frame.prefix(Self.headerLength))
        let tail = Array(frame.suffix(Self.tailLength))
        let body = Array(frame[Self.headerLength ..< frame.count - Self.tailLength])
        let frameCounter = UInt32(tail[4]) << 8 | UInt32(tail[5])

        guard frameCounter > 0 else {
            let payload = xorRepeating(body, aes(Self.firmwareKey))
            let received = UInt16(tail[2]) | UInt16(tail[3]) << 8
            guard Self.checksum(payload) == received else { throw Failure.integrityCheckFailed }
            return header + payload
        }
        let nonce = Self.nonce(counter: frameCounter, auth: auth)
        let plaintext = header + ctr(body, nonce: nonce)
        let tagMask = aes(Self.counterBlock(nonce, 0))
        let receivedTag = zip(tail.prefix(4), tagMask).map { $0 ^ $1 }
        guard receivedTag == mac(plaintext, nonce: nonce) else { throw Failure.integrityCheckFailed }
        return plaintext
    }

    private func mac(_ plaintext: [UInt8], nonce: [UInt8]) -> [UInt8] {
        let payload = plaintext.dropFirst(Self.headerLength)
        var state = aes([0x59] + nonce + [0x00, UInt8(payload.count & 0xFF)])
        state = aes(zip(state, Self.padded(Array(plaintext.prefix(Self.headerLength)), to: 16)).map { $0 ^ $1 })
        for block in Self.blocks(Array(payload)) {
            state = aes(zip(state, Self.padded(block, to: 16)).map { $0 ^ $1 })
        }
        return Array(state.prefix(4))
    }

    private func ctr(_ data: [UInt8], nonce: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(data.count)
        for (index, block) in Self.blocks(data).enumerated() {
            let keystream = aes(Self.counterBlock(nonce, index + 1))
            out += zip(block, keystream).map { $0 ^ $1 }
        }
        return out
    }

    private func xorRepeating(_ data: [UInt8], _ keystream: [UInt8]) -> [UInt8] {
        data.enumerated().map { $0.element ^ keystream[$0.offset % 16] }
    }

    private func aes(_ block: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
            aesKey, aesKey.count, nil, block, 16, &out, 16, &moved
        )
        precondition(status == kCCSuccess, "AES-128 on a 16-byte block cannot fail")
        return out
    }

    private static func nonce(counter: UInt32, auth: [UInt8]) -> [UInt8] {
        [UInt8(counter >> 24), UInt8((counter >> 16) & 0xFF), UInt8((counter >> 8) & 0xFF), UInt8(counter & 0xFF)] + auth.prefix(8) + [0x00]
    }

    private static func counterBlock(_ nonce: [UInt8], _ index: Int) -> [UInt8] {
        [0x01] + nonce + [0x00, UInt8(index & 0xFF)]
    }

    private static func checksum(_ payload: [UInt8]) -> UInt16 {
        ~UInt16(truncatingIfNeeded: payload.reduce(0) { $0 + Int($1) })
    }

    private static func blocks(_ data: [UInt8]) -> [[UInt8]] {
        stride(from: 0, to: data.count, by: 16).map { Array(data[$0 ..< min($0 + 16, data.count)]) }
    }

    private static func padded(_ bytes: [UInt8], to length: Int) -> [UInt8] {
        Array((bytes + [UInt8](repeating: 0, count: length)).prefix(length))
    }
}
