import Foundation
import GRPC
import NIO
import NIOConcurrencyHelpers
import NIOHPACK
import ShoparProtocol
import SwiftProtobuf

public struct DiscoveryProduct:Sendable,Identifiable,Equatable{
    public let id:String
    public let title:String
    public let imageURL:String
    public let merchantName:String
    public let sellerName:String
    public let priceMinorUnits:Int64
    public let currency:String
    public let ctaText:String
    public let disclosureText:String
    public let offerRef:String
    public let selectionSource:String
    public let priceObservationID:String
}

struct DiscoveryPage:Sendable{
    let format:String
    let revision:Int64
    let products:[DiscoveryProduct]
    let nextPageToken:String
    let hasMore:Bool
    let outcome:String
}

@MainActor
final class DiscoveryRuntime{
    let configuration:DiscoveryConfiguration
    private let agent:ShoparAgent
    private let group:MultiThreadedEventLoopGroup
    private let connection:ClientConnection
    private let client:Shopar_Discovery_V1_DiscoverySDKServiceAsyncClient

    init(configuration:DiscoveryConfiguration)throws{
        self.configuration=configuration
        self.agent=try ShoparAgent(configuration:configuration)
        self.group=MultiThreadedEventLoopGroup(numberOfThreads:1)
        self.connection=configuration.useTLS ? ClientConnection.usingTLSBackedByNIOSSL(on:group).connect(host:configuration.grpcHost,port:configuration.grpcPort) : ClientConnection.insecure(group:group).connect(host:configuration.grpcHost,port:configuration.grpcPort)
        self.client=Shopar_Discovery_V1_DiscoverySDKServiceAsyncClient(channel:connection)
    }

    func setOptionalDeviceMetadataCollectionEnabled(_ enabled:Bool){agent.setOptionalDeviceMetadataCollectionEnabled(enabled)}
    func resetInstallationIdentity()throws{try agent.resetInstallationIdentity()}

    func placement(_ placementID:String,pageToken:String="",revision:Int64=0)async throws->DiscoveryPage{
        var request=Shopar_Discovery_V1_GetPlacementProductsRequest();request.appID=configuration.appID;request.placementID=placementID;request.pageSize=30;request.pageToken=pageToken;request.expectedConfigRevision=revision;request.requestID=ShoparAgent.newEventID()
        let response=try await client.getPlacementProducts(request,callOptions:callOptions())
        let products=response.products.map{DiscoveryProduct(id:$0.productID,title:$0.productTitle,imageURL:$0.productImageURL,merchantName:$0.merchantName,sellerName:$0.sellerName,priceMinorUnits:$0.displayedPrice.minorUnits,currency:$0.displayedPrice.currency,ctaText:$0.ctaText,disclosureText:$0.disclosureText,offerRef:$0.offerRef,selectionSource:$0.selectionSource,priceObservationID:$0.priceObservationID)}
        return DiscoveryPage(format:response.displayFormat,revision:response.configRevision,products:products,nextPageToken:response.nextPageToken,hasMore:response.hasMore_p,outcome:response.outcome)
    }

    func recordImpression(placementID:String,revision:Int64,screenViewID:String,product:DiscoveryProduct,eventID:String,visibleDurationMs:Int32=1000)async throws{
        var impression=Shopar_Discovery_V1_PlacementImpression();impression.eventID=eventID;impression.screenViewID=screenViewID;impression.productID=product.id;impression.offerRef=product.offerRef;impression.observedAt=SwiftProtobuf.Google_Protobuf_Timestamp(date:Date());impression.visibleDurationMs=visibleDurationMs
        var request=Shopar_Discovery_V1_RecordPlacementImpressionsRequest();request.appID=configuration.appID;request.placementID=placementID;request.configRevision=revision;request.impressions=[impression]
        _=try await client.recordPlacementImpressions(request,callOptions:callOptions())
    }

    func openProduct(placementID:String,revision:Int64,screenViewID:String,product:DiscoveryProduct)async throws->Shopar_Discovery_V1_OpenProductResponse{
        var request=Shopar_Discovery_V1_OpenProductRequest();request.appID=configuration.appID;request.placementID=placementID;request.configRevision=revision;request.productID=product.id;request.offerRef=product.offerRef;request.priceObservationID=product.priceObservationID;request.screenViewID=screenViewID;request.eventID=ShoparAgent.newEventID();request.requestID=UUID().uuidString.lowercased()
        return try await client.openProduct(request,callOptions:callOptions())
    }

    private func callOptions()->CallOptions{var metadata=HPACKHeaders();metadata.add(name:"shopar-agent",value:agent.header);return CallOptions(customMetadata:metadata,timeLimit:.timeout(.seconds(15)))}
}
