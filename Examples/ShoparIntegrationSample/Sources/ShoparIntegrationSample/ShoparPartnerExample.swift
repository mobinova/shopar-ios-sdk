import SwiftUI
import ShoparAgency
import ShoparDiscovery

/// Host-app sample that references both SDK products in the same target.
@MainActor
public enum ShoparPartnerExample {
    public static func configure() throws {
        try ShoparAgency.configure(AgencyConfiguration(appID:"app_00000000000000000000000000"))
        try ShoparDiscovery.configure(DiscoveryConfiguration(appID:"app_00000000000000000000000001"))
    }
}

public struct ShoparPartnerExampleView:View {
    public init(){}
    public var body:some View{
        TabView{
            AgencyLinksView().tabItem{Label("Creator",systemImage:"person.crop.rectangle")}
            ShoparDiscovery.Placement(placementID:"plc_00000000000000000000000000").tabItem{Label("Discovery",systemImage:"rectangle.stack")}
        }
    }
}
