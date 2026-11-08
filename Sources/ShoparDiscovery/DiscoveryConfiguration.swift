import Foundation

/// Public, non-secret configuration for one Discovery SDK app property.
public struct DiscoveryConfiguration: Sendable, Equatable {
    public let appID: String
    public let grpcHost: String
    public let grpcPort: Int
    public let useTLS: Bool
    /// Public device attributes are optional. The installation ID is still used for event deduplication.
    public let collectDeviceMetadata: Bool

    public init(appID: String, grpcHost: String = "grpc.shopar.app", grpcPort: Int = 443, useTLS: Bool = true, collectDeviceMetadata: Bool = false) throws {
        guard appID.range(of: #"^app_[0-9A-HJKMNP-TV-Z]{26}$"#, options: .regularExpression) != nil else {
            throw DiscoverySDKError.invalidAppID
        }
        guard !grpcHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !grpcHost.contains("/"), (1...65535).contains(grpcPort) else {
            throw DiscoverySDKError.invalidEndpoint
        }
        self.appID = appID
        self.grpcHost = grpcHost
        self.grpcPort = grpcPort
        self.useTLS = useTLS
        self.collectDeviceMetadata = collectDeviceMetadata
    }
}

public enum DiscoverySDKError: Error, Equatable {
    case invalidAppID
    case invalidEndpoint
    case notConfigured
    case alreadyConfiguredForAnotherApp
}
