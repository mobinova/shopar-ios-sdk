import Foundation
import UIKit
import Darwin

@MainActor
struct ShoparAgent {
    let installationID: String
    let model: String
    let osVersion: String
    let locale: String
    let timezone: String

    init(appID: String, host: String, port: Int) throws {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        var excludedDirectory = directory
        try excludedDirectory.setResourceValues(directoryValues)
        let safeHost = host.replacingOccurrences(of: ".", with: "-")
        let file = directory.appendingPathComponent("shopar-agency-\(safeHost)-\(port)-\(appID).installation", isDirectory: false)
        if let saved = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), Self.isDeviceID(saved) {
            installationID = saved
        } else {
            let created = "dev_" + Self.ulid()
            try Data(created.utf8).write(to: file, options: .atomic)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var excludedFile = file
            try excludedFile.setResourceValues(values)
            installationID = created
        }
        model = Self.machineIdentifier()
        osVersion = "iOS \(UIDevice.current.systemVersion)"
        locale = Locale.current.identifier
        timezone = TimeZone.current.identifier
    }

    var header: String {
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        return "Shopar/1/\(ShoparAgency.sdkVersion) (Apple; \(Self.clean(model)); \(Self.clean(osVersion)); \(device); \(installationID); \(Self.clean(locale)); \(Self.clean(timezone))) native"
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ";", with: "-").replacingOccurrences(of: "(", with: "-").replacingOccurrences(of: ")", with: "-").replacingOccurrences(of: " ", with: "_")
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
}
