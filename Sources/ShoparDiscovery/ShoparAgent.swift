import Foundation
import UIKit
import Darwin
import Security

@MainActor
final class ShoparAgent {
    private(set) var installationID: String
    private(set) var collectDeviceMetadata: Bool
    private let installationFile: URL
    private let keychainService: String

    init(configuration: DiscoveryConfiguration) throws {
        collectDeviceMetadata = configuration.collectDeviceMetadata
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        var excludedDirectory = directory
        try excludedDirectory.setResourceValues(directoryValues)
        let safeHost = configuration.grpcHost.replacingOccurrences(of: ".", with: "-")
        installationFile = directory.appendingPathComponent("shopar-discovery-\(safeHost)-\(configuration.grpcPort)-\(configuration.appID).installation", isDirectory: false)
        keychainService = "com.mobinova.shopar.discovery.\(configuration.grpcHost).\(configuration.grpcPort).\(configuration.appID)"
        installationID = try Self.loadOrCreateInstallationID(file: installationFile, service: keychainService)
    }

    func setOptionalDeviceMetadataCollectionEnabled(_ enabled: Bool) {
        collectDeviceMetadata = enabled
    }

    /// Explicitly rotate only after the host has obtained user consent to reset this installation identity.
    func resetInstallationIdentity() throws {
        try Self.deleteKeychainInstallationID(service: keychainService)
        if FileManager.default.fileExists(atPath: installationFile.path) {
            try FileManager.default.removeItem(at: installationFile)
        }
        installationID = try Self.createInstallationID(file: installationFile, service: keychainService)
    }

    var header: String {
        let collect = collectDeviceMetadata
        let device = collect ? (UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone") : "unknown"
        let vendor = collect ? "Apple" : "unknown"
        let model = collect ? Self.machineIdentifier() : "unknown"
        let os = collect ? "iOS \(UIDevice.current.systemVersion)" : "unknown"
        let locale = collect ? Locale.current.identifier : "unknown"
        let timezone = collect ? TimeZone.current.identifier : "unknown"
        return "Shopar/1/\(ShoparDiscovery.sdkVersion) (\(vendor); \(Self.clean(model)); \(Self.clean(os)); \(device); \(installationID); \(Self.clean(locale)); \(Self.clean(timezone))) native"
    }

    private static func loadOrCreateInstallationID(file: URL, service: String) throws -> String {
        if let value = try readKeychainInstallationID(service: service), isDeviceID(value) {
            return value
        }
        // Keep a no-backup fallback for launches before the first device unlock,
        // when ThisDeviceOnly Keychain data may not yet be readable.
        if let saved = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), isDeviceID(saved) {
            try? storeKeychainInstallationID(saved, service: service)
            return saved
        }
        return try createInstallationID(file: file, service: service)
    }

    private static func createInstallationID(file: URL, service: String) throws -> String {
        let value = "dev_" + ulid()
        try Data(value.utf8).write(to: file, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excludedFile = file
        try excludedFile.setResourceValues(values)
        try? storeKeychainInstallationID(value, service: service)
        return value
    }

    private static func readKeychainInstallationID(service: String) throws -> String? {
        var query = keychainQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound || status == errSecInteractionNotAllowed { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    private static func storeKeychainInstallationID(_ value: String, service: String) throws {
        let data = Data(value.utf8)
        let query = keychainQuery(service: service)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func deleteKeychainInstallationID(service: String) throws {
        let status = SecItemDelete(keychainQuery(service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func keychainQuery(service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "discovery-installation-id"]
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ";", with: "-")
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "-")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func isDeviceID(_ value: String) -> Bool {
        value.range(of: #"^dev_[0-9A-HJKMNP-TV-Z]{26}$"#, options: .regularExpression) != nil
    }

    private static func machineIdentifier() -> String {
        var value = utsname()
        guard uname(&value) == 0 else { return UIDevice.current.model }
        let machine = value.machine
        return withUnsafeBytes(of: machine) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }

    private static func ulid() -> String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)
        var bytes = [UInt8](repeating: 0, count: 16)
        var milliseconds = UInt64(Date().timeIntervalSince1970 * 1000)
        for index in (0..<6).reversed() { bytes[index] = UInt8(milliseconds & 0xff); milliseconds >>= 8 }
        var generator = SystemRandomNumberGenerator()
        for index in 6..<16 { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
        var digits = [UInt8](repeating: 0, count: 26)
        for output in (0..<26).reversed() {
            var remainder = 0
            for index in bytes.indices {
                let current = remainder * 256 + Int(bytes[index])
                bytes[index] = UInt8(current / 32)
                remainder = current % 32
            }
            digits[output] = alphabet[remainder]
        }
        return String(decoding: digits, as: UTF8.self)
    }

    static func newEventID() -> String { "ipev_" + ulid() }
}
