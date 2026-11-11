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

public struct DiscoveryPlacementItem:Sendable,Identifiable,Equatable{
    public let kind:String
    public let id:String
    public let productID:String
    public let dealID:String
    public let title:String
    public let imageURL:String
    public let merchantName:String
    public let sellerName:String
    public let priceMinorUnits:Int64?
    public let currency:String
    public let ctaText:String
    public let disclosureText:String
    public let offerRef:String
    public let selectionSource:String
    public let priceObservationID:String
    public let benefitLabel:String
    public let decisiveCondition:String
    public let dealRevision:String
    public let couponCode:String

    var productProjection:DiscoveryProduct?{
        guard kind=="product" else{return nil}
        return DiscoveryProduct(id:productID,title:title,imageURL:imageURL,merchantName:merchantName,sellerName:sellerName,priceMinorUnits:priceMinorUnits ?? 0,currency:currency,ctaText:ctaText,disclosureText:disclosureText,offerRef:offerRef,selectionSource:selectionSource,priceObservationID:priceObservationID)
    }
}

struct DiscoveryOpenResult:Sendable{
    let outcome:String
    let redirectURL:String
}

struct DiscoveryPage:Sendable{
    let format:String
    let revision:Int64
    let items:[DiscoveryPlacementItem]
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
        let items:[DiscoveryPlacementItem]
        if !response.items.isEmpty{
            items=response.items.map{DiscoveryPlacementItem(kind:$0.itemKind,id:$0.itemID,productID:$0.productID,dealID:$0.dealID,title:$0.title,imageURL:$0.imageURL,merchantName:$0.merchantName,sellerName:$0.sellerName,priceMinorUnits:$0.hasDisplayedPrice ? $0.displayedPrice.minorUnits:nil,currency:$0.hasDisplayedPrice ? $0.displayedPrice.currency:"",ctaText:$0.ctaText,disclosureText:$0.disclosureText,offerRef:$0.offerRef,selectionSource:$0.selectionSource,priceObservationID:$0.priceObservationID,benefitLabel:$0.benefitLabel,decisiveCondition:$0.decisiveCondition,dealRevision:$0.dealRevision,couponCode:$0.couponCode)}
        }else{
            items=response.products.map{DiscoveryPlacementItem(kind:"product",id:$0.productID,productID:$0.productID,dealID:"",title:$0.productTitle,imageURL:$0.productImageURL,merchantName:$0.merchantName,sellerName:$0.sellerName,priceMinorUnits:$0.hasDisplayedPrice ? $0.displayedPrice.minorUnits:nil,currency:$0.hasDisplayedPrice ? $0.displayedPrice.currency:"",ctaText:$0.ctaText,disclosureText:$0.disclosureText,offerRef:$0.offerRef,selectionSource:$0.selectionSource,priceObservationID:$0.priceObservationID,benefitLabel:"",decisiveCondition:"",dealRevision:"",couponCode:"" )}
        }
        return DiscoveryPage(format:response.displayFormat,revision:response.configRevision,items:items,nextPageToken:response.nextPageToken,hasMore:response.hasMore_p,outcome:response.outcome)
    }

    func recordImpression(placementID:String,revision:Int64,screenViewID:String,item:DiscoveryPlacementItem,eventID:String,visibleDurationMs:Int32=1000)async throws{
        var impression=Shopar_Discovery_V1_PlacementImpression();impression.eventID=eventID;impression.screenViewID=screenViewID;impression.itemKind=item.kind;impression.productID=item.productID;impression.dealID=item.dealID;impression.offerRef=item.offerRef;impression.observedAt=SwiftProtobuf.Google_Protobuf_Timestamp(date:Date());impression.visibleDurationMs=visibleDurationMs
        var request=Shopar_Discovery_V1_RecordPlacementImpressionsRequest();request.appID=configuration.appID;request.placementID=placementID;request.configRevision=revision;request.impressions=[impression]
        _=try await client.recordPlacementImpressions(request,callOptions:callOptions())
    }

    func openItem(placementID:String,revision:Int64,screenViewID:String,item:DiscoveryPlacementItem)async throws->DiscoveryOpenResult{
        if item.kind=="deal"{
            var request=Shopar_Discovery_V1_OpenDealRequest();request.appID=configuration.appID;request.placementID=placementID;request.configRevision=revision;request.dealID=item.dealID;request.offerRef=item.offerRef;request.dealRevision=item.dealRevision;request.screenViewID=screenViewID;request.eventID=ShoparAgent.newEventID();request.requestID=UUID().uuidString.lowercased()
            let result=try await client.openDeal(request,callOptions:callOptions())
            return DiscoveryOpenResult(outcome:result.outcome,redirectURL:result.redirectURL)
        }
        var request=Shopar_Discovery_V1_OpenProductRequest();request.appID=configuration.appID;request.placementID=placementID;request.configRevision=revision;request.productID=item.productID;request.offerRef=item.offerRef;request.priceObservationID=item.priceObservationID;request.screenViewID=screenViewID;request.eventID=ShoparAgent.newEventID();request.requestID=UUID().uuidString.lowercased()
        let result=try await client.openProduct(request,callOptions:callOptions())
        return DiscoveryOpenResult(outcome:result.outcome,redirectURL:result.redirectURL)
    }

    private func callOptions()->CallOptions{var metadata=HPACKHeaders();metadata.add(name:"shopar-agent",value:agent.header);return CallOptions(customMetadata:metadata,timeLimit:.timeout(.seconds(15)))}
}
