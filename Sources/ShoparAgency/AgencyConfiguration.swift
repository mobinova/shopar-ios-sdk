import Foundation

/// Public, non-secret configuration for one Agency SDK app property.
public struct AgencyConfiguration: Sendable, Equatable {
    public let appID: String
    public let grpcHost: String
    public let grpcPort: Int
    public let useTLS: Bool
    public let style: AgencyStyle

    public init(appID: String, grpcHost: String = "grpc.shopar.app", grpcPort: Int = 443, useTLS: Bool = true, style: AgencyStyle = .shopar) throws {
        guard appID.range(of: #"^app_[0-9A-HJKMNP-TV-Z]{26}$"#, options: .regularExpression) != nil else {
            throw AgencySDKError.invalidAppID
        }
        guard !grpcHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !grpcHost.contains("/"), (1...65535).contains(grpcPort) else {
            throw AgencySDKError.invalidEndpoint
        }
        self.appID = appID
        self.grpcHost = grpcHost
        self.grpcPort = grpcPort
        self.useTLS = useTLS
        self.style = style
    }
}

public enum AgencySDKError: Error, Equatable {
    case invalidAppID
    case invalidEndpoint
    case notConfigured
    case alreadyConfiguredForAnotherApp
    case signInRequestMismatch
    case invalidSessionResponse
    case sessionRequired
}
