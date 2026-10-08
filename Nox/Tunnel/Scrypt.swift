import Foundation

/// scrypt (RFC 7914) with the SHA-256 / HMAC / PBKDF2 pieces it needs, in plain Swift: neither
/// CryptoKit nor CommonCrypto has scrypt. OpenFlux derives its encryption key with N = 32768,
/// r = 8 — 32 MB of memory, too much for the 50 MB Network Extension — so the app derives it and
/// hands the extension only the result (`OpenFluxKeys`).
enum Scrypt {
    /// nil → invalid parameters (N must be a power of two above 1).
    static func derive(password: [UInt8], salt: [UInt8], n: Int, r: Int, p: Int, length: Int) -> [UInt8]? {
        guard n > 1, n & (n - 1) == 0, n <= 1 << 30, r > 0, p > 0, length > 0 else { return nil }
        let words = 32 * r
        let initial = pbkdf2(password: password, salt: salt, length: p * 128 * r)
        var state = [UInt32](repeating: 0, count: p * words)
        for i in state.indices {
            state[i] = UInt32(initial[4 * i]) | UInt32(initial[4 * i + 1]) << 8
                | UInt32(initial[4 * i + 2]) << 16 | UInt32(initial[4 * i + 3]) << 24
        }
        let v = UnsafeMutablePointer<UInt32>.allocate(capacity: n * words)
        let x = UnsafeMutablePointer<UInt32>.allocate(capacity: words)
        let y = UnsafeMutablePointer<UInt32>.allocate(capacity: words)
        let t = UnsafeMutablePointer<UInt32>.allocate(capacity: 16)
        defer {
            v.deallocate()
            x.deallocate()
            y.deallocate()
            t.deallocate()
        }
        let mask = UInt32(truncatingIfNeeded: n - 1)
        state.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for chunk in 0..<p {
                let block = base + chunk * words
                x.update(from: block, count: words)
                for i in 0..<n {
                    (v + i * words).update(from: x, count: words)
                    blockMix(x, y, t, r)
                }
                for _ in 0..<n {
                    let j = Int(x[(2 * r - 1) * 16] & mask)
                    let vj = v + j * words
                    for k in 0..<words { x[k] ^= vj[k] }
                    blockMix(x, y, t, r)
                }
                block.update(from: x, count: words)
            }
        }
        var mixed = [UInt8](repeating: 0, count: p * 128 * r)
        for (i, w) in state.enumerated() {
            mixed[4 * i] = UInt8(truncatingIfNeeded: w)
            mixed[4 * i + 1] = UInt8(truncatingIfNeeded: w >> 8)
            mixed[4 * i + 2] = UInt8(truncatingIfNeeded: w >> 16)
            mixed[4 * i + 3] = UInt8(truncatingIfNeeded: w >> 24)
        }
        return pbkdf2(password: password, salt: mixed, length: length)
    }

    /// PBKDF2-HMAC-SHA256 with one iteration, all scrypt needs.
    static func pbkdf2(password: [UInt8], salt: [UInt8], length: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(length + 32)
        var index: UInt32 = 1
        while out.count < length {
            let counter = [UInt8(truncatingIfNeeded: index >> 24), UInt8(truncatingIfNeeded: index >> 16),
                           UInt8(truncatingIfNeeded: index >> 8), UInt8(truncatingIfNeeded: index)]
            out += Hash256.hmac(key: password, message: salt + counter)
            index += 1
        }
        return Array(out.prefix(length))
    }

    /// B ← BlockMix(B): `y` holds 32·r words, `t` 16.
    private static func blockMix(_ b: UnsafeMutablePointer<UInt32>, _ y: UnsafeMutablePointer<UInt32>,
                                 _ t: UnsafeMutablePointer<UInt32>, _ r: Int) {
        t.update(from: b + (2 * r - 1) * 16, count: 16)
        for i in 0..<(2 * r) {
            let bi = b + i * 16
            for k in 0..<16 { t[k] ^= bi[k] }
            salsa8(t)
            // Even blocks go to the first half, odd ones to the second.
            (y + ((i & 1) * r + (i >> 1)) * 16).update(from: t, count: 16)
        }
        b.update(from: y, count: 32 * r)
    }

    @inline(__always)
    private static func rotl(_ v: UInt32, _ n: UInt32) -> UInt32 { (v &<< n) | (v &>> (32 &- n)) }

    /// Salsa20/8 core, in place.
    private static func salsa8(_ p: UnsafeMutablePointer<UInt32>) {
        var x0 = p[0], x1 = p[1], x2 = p[2], x3 = p[3], x4 = p[4], x5 = p[5], x6 = p[6], x7 = p[7]
        var x8 = p[8], x9 = p[9], x10 = p[10], x11 = p[11], x12 = p[12], x13 = p[13], x14 = p[14], x15 = p[15]
        for _ in 0..<4 {
            x4 ^= rotl(x0 &+ x12, 7); x8 ^= rotl(x4 &+ x0, 9)
            x12 ^= rotl(x8 &+ x4, 13); x0 ^= rotl(x12 &+ x8, 18)
            x9 ^= rotl(x5 &+ x1, 7); x13 ^= rotl(x9 &+ x5, 9)
            x1 ^= rotl(x13 &+ x9, 13); x5 ^= rotl(x1 &+ x13, 18)
            x14 ^= rotl(x10 &+ x6, 7); x2 ^= rotl(x14 &+ x10, 9)
            x6 ^= rotl(x2 &+ x14, 13); x10 ^= rotl(x6 &+ x2, 18)
            x3 ^= rotl(x15 &+ x11, 7); x7 ^= rotl(x3 &+ x15, 9)
            x11 ^= rotl(x7 &+ x3, 13); x15 ^= rotl(x11 &+ x7, 18)

            x1 ^= rotl(x0 &+ x3, 7); x2 ^= rotl(x1 &+ x0, 9)
            x3 ^= rotl(x2 &+ x1, 13); x0 ^= rotl(x3 &+ x2, 18)
            x6 ^= rotl(x5 &+ x4, 7); x7 ^= rotl(x6 &+ x5, 9)
            x4 ^= rotl(x7 &+ x6, 13); x5 ^= rotl(x4 &+ x7, 18)
            x11 ^= rotl(x10 &+ x9, 7); x8 ^= rotl(x11 &+ x10, 9)
            x9 ^= rotl(x8 &+ x11, 13); x10 ^= rotl(x9 &+ x8, 18)
            x12 ^= rotl(x15 &+ x14, 7); x13 ^= rotl(x12 &+ x15, 9)
            x14 ^= rotl(x13 &+ x12, 13); x15 ^= rotl(x14 &+ x13, 18)
        }
        p[0] = p[0] &+ x0; p[1] = p[1] &+ x1; p[2] = p[2] &+ x2; p[3] = p[3] &+ x3
        p[4] = p[4] &+ x4; p[5] = p[5] &+ x5; p[6] = p[6] &+ x6; p[7] = p[7] &+ x7
        p[8] = p[8] &+ x8; p[9] = p[9] &+ x9; p[10] = p[10] &+ x10; p[11] = p[11] &+ x11
        p[12] = p[12] &+ x12; p[13] = p[13] &+ x13; p[14] = p[14] &+ x14; p[15] = p[15] &+ x15
    }
}

/// SHA-256 (FIPS 180-4). Named apart from CryptoKit's `SHA256`.
struct Hash256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    private var pending: [UInt8] = []
    private var total: UInt64 = 0

    mutating func update(_ bytes: [UInt8]) {
        total &+= UInt64(bytes.count)
        pending += bytes
        var offset = 0
        while pending.count - offset >= 64 {
            compress(pending, at: offset)
            offset += 64
        }
        if offset > 0 { pending.removeFirst(offset) }
    }

    mutating func finish() -> [UInt8] {
        let bits = total &* 8
        var tail: [UInt8] = [0x80]
        tail += [UInt8](repeating: 0, count: (119 - pending.count) % 64)
        for shift in stride(from: 56, through: 0, by: -8) { tail.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        let saved = total
        update(tail)
        total = saved
        var out: [UInt8] = []
        out.reserveCapacity(32)
        for word in h {
            out += [UInt8(truncatingIfNeeded: word >> 24), UInt8(truncatingIfNeeded: word >> 16),
                    UInt8(truncatingIfNeeded: word >> 8), UInt8(truncatingIfNeeded: word)]
        }
        return out
    }

    static func hash(_ bytes: [UInt8]) -> [UInt8] {
        var hasher = Hash256()
        hasher.update(bytes)
        return hasher.finish()
    }

    static func hmac(key: [UInt8], message: [UInt8]) -> [UInt8] {
        var k = key.count > 64 ? hash(key) : key
        k += [UInt8](repeating: 0, count: 64 - k.count)
        var inner = Hash256()
        inner.update(k.map { $0 ^ 0x36 } + message)
        var outer = Hash256()
        outer.update(k.map { $0 ^ 0x5c } + inner.finish())
        return outer.finish()
    }

    private mutating func compress(_ data: [UInt8], at offset: Int) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            let j = offset + 4 * i
            w[i] = UInt32(data[j]) << 24 | UInt32(data[j + 1]) << 16 | UInt32(data[j + 2]) << 8 | UInt32(data[j + 3])
        }
        for i in 16..<64 {
            let s0 = Self.rotr(w[i - 15], 7) ^ Self.rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = Self.rotr(w[i - 2], 17) ^ Self.rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
        for i in 0..<64 {
            let s1 = Self.rotr(e, 6) ^ Self.rotr(e, 11) ^ Self.rotr(e, 25)
            let ch = (e & f) ^ (~e & g)
            let t1 = hh &+ s1 &+ ch &+ Self.k[i] &+ w[i]
            let s0 = Self.rotr(a, 2) ^ Self.rotr(a, 13) ^ Self.rotr(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = s0 &+ maj
            hh = g; g = f; f = e; e = d &+ t1
            d = c; c = b; b = a; a = t1 &+ t2
        }
        h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
        h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
    }

    @inline(__always)
    private static func rotr(_ v: UInt32, _ n: UInt32) -> UInt32 { (v &>> n) | (v &<< (32 &- n)) }
}
