// Sparkle 更新包签名工具（等价于官方 sign_update，用 CryptoKit 实现）
// 用法: swift scripts/sign_update.swift <待签名文件> <base64 私钥seed>
// 输出: sparkle:edSignature="..." length="..."
import Foundation
import CryptoKit

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("用法: swift scripts/sign_update.swift <文件> <base64私钥seed>\n".data(using: .utf8)!)
    exit(1)
}

guard let seed = Data(base64Encoded: args[2]), seed.count == 32 else {
    FileHandle.standardError.write("私钥 seed 必须是 base64 编码的 32 字节\n".data(using: .utf8)!)
    exit(1)
}

let data = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
let sig = try key.signature(for: data)
print("sparkle:edSignature=\"\(sig.base64EncodedString())\" length=\"\(data.count)\"")
