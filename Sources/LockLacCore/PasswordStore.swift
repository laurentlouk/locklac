import Foundation
import CommonCrypto

public final class PasswordStore {
    private let configDir: URL
    private var config: PasswordConfig?

    public var hasPassword: Bool { config != nil }

    public init(configDir: URL? = nil) {
        self.configDir = configDir ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".locklac")
    }

    public func load() throws {
        let configFile = configDir.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configFile.path) else { return }
        let data = try Data(contentsOf: configFile)
        config = try JSONDecoder().decode(PasswordConfig.self, from: data)
    }

    public func setPassword(_ password: String) throws {
        let salt = generateSalt()
        let hash = deriveKey(password: password, salt: salt)
        config = PasswordConfig(
            passwordHash: hash.base64EncodedString(),
            salt: salt.base64EncodedString(),
            iterations: Self.iterations,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try save()
    }

    public func verify(_ password: String) -> Bool {
        guard let config else { return false }
        guard let salt = Data(base64Encoded: config.salt),
              let storedHash = Data(base64Encoded: config.passwordHash) else { return false }
        let candidateHash = deriveKey(password: password, salt: salt, iterations: config.iterations)
        return constantTimeEqual(candidateHash, storedHash)
    }

    // MARK: - Private

    private static let iterations: UInt32 = 100_000
    private static let keyLength = 64
    private static let saltLength = 32

    private func generateSalt() -> Data {
        var salt = Data(count: Self.saltLength)
        salt.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, Self.saltLength, ptr.baseAddress!)
        }
        return salt
    }

    private func deriveKey(password: String, salt: Data, iterations: UInt32? = nil) -> Data {
        let passwordData = Array(password.utf8)
        var derivedKey = Data(count: Self.keyLength)
        _ = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordData, passwordData.count,
                    saltPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                    iterations ?? Self.iterations,
                    derivedKeyPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), Self.keyLength
                )
            }
        }
        return derivedKey
    }

    private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(a, b) {
            result |= x ^ y
        }
        return result == 0
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(config)
        let configFile = configDir.appendingPathComponent("config.json")
        try data.write(to: configFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
    }
}

struct PasswordConfig: Codable {
    let passwordHash: String
    let salt: String
    let iterations: UInt32
    let createdAt: String
}
