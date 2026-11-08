import SwiftUI

/// Anonymous product placements. This module has no Agency token store or authorization metadata.
@MainActor
public enum ShoparDiscovery {
    static let sdkVersion="0.1.0"
    private static var storedConfiguration:DiscoveryConfiguration?
    private static var runtime:DiscoveryRuntime?

    public static func configure(_ configuration:DiscoveryConfiguration)throws{
        if let current=storedConfiguration,current != configuration{throw DiscoverySDKError.alreadyConfiguredForAnotherApp}
        if runtime==nil{runtime=try DiscoveryRuntime(configuration:configuration)}
        storedConfiguration=configuration
    }

    /// Call whenever the host's current privacy preference changes. Required installation IDs remain stable.
    public static func setOptionalDeviceMetadataCollectionEnabled(_ enabled:Bool)throws{
        try requireRuntime().setOptionalDeviceMetadataCollectionEnabled(enabled)
    }

    /// Call only after the user explicitly asks to reset this app's Discovery installation identity.
    public static func resetInstallationIdentity()throws{
        try requireRuntime().resetInstallationIdentity()
    }

    @ViewBuilder public static func Placement(placementID:String)->some View{
        if let runtime{DiscoveryPlacementView(placementID:placementID,runtime:runtime)}
        else{DiscoveryUnavailableView(message:"Call ShoparDiscovery.configure before displaying this placement.")}
    }

    static func requireRuntime()throws->DiscoveryRuntime{guard let runtime else{throw DiscoverySDKError.notConfigured};return runtime}
}

struct DiscoveryUnavailableView:View{
    let message:String
    var body:some View{Text(message).font(.footnote).foregroundStyle(.secondary).padding()}
}
