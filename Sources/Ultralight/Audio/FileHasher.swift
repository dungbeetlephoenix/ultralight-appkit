import Foundation
import CommonCrypto

enum FileHasher {
    /// MD5 hash of first 64KB + last 64KB + file size string.
    /// Matches the Electron app's hashing scheme for EQ profile migration.
    static func hash(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        let chunkSize = 65536
        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)

        // Read head
        let head = handle.readData(ofLength: chunkSize)
        head.withUnsafeBytes { ptr in
            _ = CC_MD5_Update(&context, ptr.baseAddress, CC_LONG(head.count))
        }

        // Read tail if file is larger than one chunk
        let fileSize = handle.seekToEndOfFile()
        if fileSize > UInt64(chunkSize) {
            handle.seek(toFileOffset: fileSize - UInt64(chunkSize))
            let tail = handle.readData(ofLength: chunkSize)
            tail.withUnsafeBytes { ptr in
                _ = CC_MD5_Update(&context, ptr.baseAddress, CC_LONG(tail.count))
            }
        }

        // Include file size in hash
        let sizeString = String(fileSize)
        sizeString.withCString { ptr in
            _ = CC_MD5_Update(&context, ptr, CC_LONG(sizeString.count))
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
