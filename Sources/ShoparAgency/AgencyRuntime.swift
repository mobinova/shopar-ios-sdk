import Foundation
import GRPC
import NIO
import NIOConcurrencyHelpers
import NIOHPACK
import ShoparProtocol
import Security
import SwiftProtobuf

public struct AgencySignInChallenge: Sendable, Equatable {
    public let requestID: String
    public let expiresInSeconds: Int32
}

public struct AgencyCreatorSession: Sendable, Equatable {
    public let fullName: String
    public let publicUsername: String
    public let profileImageURL: String
    public let adultEligibilityMet: Bool
    public let referralRelationship: String
    public let referralAgencyLabel: String
    public let currentAgencyLabel: String
    public let agencyVisibleDataCategories: [String]
    public let isNewAccount: Bool
}

public struct AgencyLink: Sendable, Equatable, Identifiable {
    public let id: String
    public let productID: String
    public let dealID: String
    public let shareURL: String
    public let status: String
    public let uniqueVisitors: Int64
    public let successfulRedirects: Int64
}

public struct AgencySocialAccount:Sendable,Equatable,Identifiable{
    public var id:String{platform}
    public let platform:String
    public let username:String
    public let publicURL:String
}

public struct AgencyLinkPerformance:Sendable,Equatable{
    public let uniqueVisitors:Int64
    public let successfulRedirects:Int64
    public let attributedSPRMinorUnits:Int64
}

public struct AgencyCatalogItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: String
    public let title: String
    public let subtitle: String
    public let imageURL: String
    public let priceMinorUnits: Int64
    public let currency: String
}

public struct AgencyDeviceSession: Sendable, Equatable, Identifiable {
    public let id: String
    public let appName: String
    public let agencyName: String
    public let platform: String
    public let model: String
    public let operatingSystem: String
    public let appVersion: String
    public let lastActiveAt: Date?
    public let isCurrent: Bool
}

@MainActor
final class AgencyRuntime {
    private let configuration: AgencyConfiguration
    private let group: MultiThreadedEventLoopGroup
    private let connection: ClientConnection
    private let client: Shopar_Creator_V1_CreatorSDKServiceAsyncClient
    private let agent: ShoparAgent
    private let tokenStore: AgencyTokenStore
    private var sessionGeneration: UInt64 = 0
    private var pendingRequestID = ""
    private var pendingConfirmationNonce = ""
    private var refreshTask: Task<Void, Error>?
    private var refreshTaskGeneration: UInt64?
    private(set) var session: AgencyCreatorSession?

    init(configuration: AgencyConfiguration) throws {
        self.configuration = configuration
        self.agent = try ShoparAgent(appID: configuration.appID, host: configuration.grpcHost, port: configuration.grpcPort)
        self.tokenStore = AgencyTokenStore(configuration: configuration)
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.connection = configuration.useTLS
            ? ClientConnection.usingTLSBackedByNIOSSL(on: group).connect(host: configuration.grpcHost, port: configuration.grpcPort)
            : ClientConnection.insecure(group: group).connect(host: configuration.grpcHost, port: configuration.grpcPort)
        self.client = Shopar_Creator_V1_CreatorSDKServiceAsyncClient(channel: connection)
    }

    func startSignIn(email: String) async throws -> AgencySignInChallenge {
        let startGeneration = sessionGeneration
        var request = Shopar_Creator_V1_StartAgencySessionRequest()
        request.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        request.appID = configuration.appID
        let response = try await client.startAgencySession(request, callOptions: callOptions(authenticated: false))
        guard startGeneration == sessionGeneration else { throw CancellationError() }
        pendingRequestID = response.requestID
        pendingConfirmationNonce = Self.confirmationNonce()
        return AgencySignInChallenge(requestID: response.requestID, expiresInSeconds: response.expiresInSeconds)
    }

    func confirmSignIn(requestID: String, code: String) async throws -> AgencyCreatorSession {
        guard requestID == pendingRequestID, !pendingConfirmationNonce.isEmpty else { throw AgencySDKError.signInRequestMismatch }
        let startGeneration = sessionGeneration
        let confirmationNonce = pendingConfirmationNonce
        var request = Shopar_Creator_V1_ConfirmAgencySessionRequest()
        request.requestID = requestID
        request.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        request.confirmationNonce = confirmationNonce
        let response = try await client.confirmAgencySession(request, callOptions: callOptions(authenticated: false))
        guard startGeneration == sessionGeneration, requestID == pendingRequestID else { throw CancellationError() }
        guard response.hasTokens, response.hasProfile, response.hasReferralDisclosure else { throw AgencySDKError.invalidSessionResponse }
        try tokenStore.write(AgencyStoredTokens(
            accessToken: response.tokens.accessToken,
            refreshToken: response.tokens.refreshToken,
            accessTokenExpiresAt: response.tokens.accessTokenExpiresAt,
            refreshTokenExpiresAt: response.tokens.refreshTokenExpiresAt
        ))
        sessionGeneration &+= 1
        let safe = mapSession(response)
        session = safe
        ShoparAgency.sessions.update(safe)
        pendingRequestID = ""
        pendingConfirmationNonce = ""
        return safe
    }

    func restoreSession() async throws -> AgencyCreatorSession? {
        let generation = sessionGeneration
        guard try tokenStore.read() != nil else { return nil }
        try await refreshIfNeeded(expectedGeneration: generation)
        try ensureCurrent(generation)
        let profile = try await client.getMyAgencyProfile(SwiftProtobuf.Google_Protobuf_Empty(), callOptions: callOptions(authenticated: true))
        let disclosure = try await client.getMyAgencyReferralDisclosure(SwiftProtobuf.Google_Protobuf_Empty(), callOptions: callOptions(authenticated: true))
        try ensureCurrent(generation)
        let result = mapSession(profile: profile, disclosure: disclosure, isNewAccount: false)
        session = result
        ShoparAgency.sessions.update(result)
        return result
    }

    func profile() async throws -> AgencyCreatorSession {
        let generation = try await beginAuthenticatedOperation()
        return try await profile(expectedGeneration: generation)
    }

    private func profile(expectedGeneration generation: UInt64) async throws -> AgencyCreatorSession {
        try ensureCurrent(generation)
        let profile=try await client.getMyAgencyProfile(SwiftProtobuf.Google_Protobuf_Empty(),callOptions:callOptions(authenticated:true))
        let disclosure=try await client.getMyAgencyReferralDisclosure(SwiftProtobuf.Google_Protobuf_Empty(),callOptions:callOptions(authenticated:true))
        try ensureCurrent(generation);let result=mapSession(profile:profile,disclosure:disclosure,isNewAccount:false);session=result;ShoparAgency.sessions.update(result);return result
    }

    func searchCatalog(_ query: String, page: Int32 = 1, pageSize: Int32 = 30) async throws -> [AgencyCatalogItem] {
        let generation = try await beginAuthenticatedOperation()
        var request=Shopar_Creator_V1_SearchAgencyCatalogRequest();request.query=query
        var pageRequest=Shopar_Common_V1_PageRequest();pageRequest.page=page;pageRequest.pageSize=pageSize;request.page=pageRequest
        let response=try await client.searchShareableCatalog(request,callOptions:callOptions(authenticated:true));try ensureCurrent(generation)
        return response.items.map{AgencyCatalogItem(id:$0.itemID,kind:$0.itemKind,title:$0.title,subtitle:$0.subtitle,imageURL:$0.imageURL,priceMinorUnits:$0.price.minorUnits,currency:$0.price.currency)}
    }

    func createLink(item: AgencyCatalogItem, idempotencyKey: String) async throws -> AgencyLink {
        let generation = try await beginAuthenticatedOperation()
        var request=Shopar_Creator_V1_CreateAgencyCreatorLinkRequest();request.idempotencyKey=idempotencyKey
        if item.kind=="deal"{request.subject = .dealID(item.id)}else{request.subject = .productID(item.id)}
        let result=try await client.createLink(request,callOptions:callOptions(authenticated:true));try ensureCurrent(generation);return mapLink(result)
    }

    func links() async throws -> [AgencyLink] {
        let generation = try await beginAuthenticatedOperation()
        let result=try await client.listMyLinks(Shopar_Creator_V1_AgencyCreatorLinkListRequest(),callOptions:callOptions(authenticated:true));try ensureCurrent(generation);return result.links.map(mapLink)
    }

    func updateProfile(fullName:String?,publicUsername:String?)async throws->AgencyCreatorSession{
        let generation = try await beginAuthenticatedOperation();var request=Shopar_Creator_V1_UpdateAgencyCreatorProfileRequest();if let fullName{request.fullName=fullName};if let publicUsername{request.publicUsername=publicUsername};_=try await client.updateMyAgencyProfile(request,callOptions:callOptions(authenticated:true));try ensureCurrent(generation);return try await profile(expectedGeneration:generation)
    }

    func socialAccounts()async throws->[AgencySocialAccount]{let generation=try await beginAuthenticatedOperation();let response=try await client.listMySocialAccounts(SwiftProtobuf.Google_Protobuf_Empty(),callOptions:callOptions(authenticated:true));try ensureCurrent(generation);return response.accounts.map{AgencySocialAccount(platform:$0.platform,username:$0.username,publicURL:$0.publicURL)}}

    func saveSocialAccount(platform:String,username:String)async throws->AgencySocialAccount{let generation=try await beginAuthenticatedOperation();var request=Shopar_Creator_V1_SaveAgencyCreatorSocialAccountRequest();request.platform=platform;request.username=username;let response=try await client.saveMySocialAccount(request,callOptions:callOptions(authenticated:true));try ensureCurrent(generation);return AgencySocialAccount(platform:response.account.platform,username:response.account.username,publicURL:response.account.publicURL)}

    func deleteSocialAccount(platform:String)async throws{let generation=try await beginAuthenticatedOperation();var request=Shopar_Creator_V1_DeleteAgencyCreatorSocialAccountRequest();request.platform=platform;_=try await client.deleteMySocialAccount(request,callOptions:callOptions(authenticated:true));try ensureCurrent(generation)}

    func setProfilePhoto(_ image:Data,contentType:String)async throws->String{let generation=try await beginAuthenticatedOperation();var request=Shopar_Creator_V1_SetAgencyCreatorProfilePhotoRequest();request.image=image;request.contentType=contentType;let result=try await client.setMyAgencyProfilePhoto(request,callOptions:callOptions(authenticated:true));try ensureCurrent(generation);return result.profileImageURL}

    func linkPerformance(_ linkID:String,period:String)async throws->AgencyLinkPerformance{let generation=try await beginAuthenticatedOperation();var request=Shopar_Creator_V1_AgencyCreatorLinkPerformanceRequest();request.sharedLinkID=linkID;request.period=period;let result=try await client.getMyLinkPerformance(request,callOptions:callOptions(authenticated:true));try ensureCurrent(generation);return AgencyLinkPerformance(uniqueVisitors:result.uniqueVisitors,successfulRedirects:result.successfulRedirects,attributedSPRMinorUnits:result.shareAttributedSpr.minorUnits)}

    func openLink(_ linkID:String,idempotencyKey:String)async throws->URL{let generation=try await beginAuthenticatedOperation();var request=Shopar_Creator_V1_OpenAgencyCreatorLinkRequest();request.sharedLinkID=linkID;request.idempotencyKey=idempotencyKey;let result=try await client.openLink(request,callOptions:callOptions(authenticated:true));try ensureCurrent(generation);guard let url=URL(string:result.shareURL),url.scheme=="https",url.host=="shpr.link" else{throw AgencySDKError.invalidSessionResponse};return url}

    func agencySessions() async throws -> [AgencyDeviceSession] {
        let generation = try await beginAuthenticatedOperation()
        let response=try await client.listMySessions(Shopar_Creator_V1_ListMyAgencySDKSessionsRequest(),callOptions:callOptions(authenticated:true));try ensureCurrent(generation)
        return response.sessions.map{AgencyDeviceSession(id:$0.sessionID,appName:$0.appName,agencyName:$0.agencyLabel,platform:$0.platform,model:$0.deviceModel,operatingSystem:$0.operatingSystem,appVersion:$0.appVersion,lastActiveAt:$0.hasLastActiveAt ? Date(timeIntervalSince1970:TimeInterval($0.lastActiveAt.seconds)) : nil,isCurrent:$0.isCurrentSession)}
    }

    func revokeSession(_ sessionID:String) async throws {
        let generation = try await beginAuthenticatedOperation()
        var request=Shopar_Creator_V1_RevokeMyAgencySDKSessionRequest();request.sessionID=sessionID
        _=try await client.revokeMySession(request,callOptions:callOptions(authenticated:true));try ensureCurrent(generation)
    }

    func signOut() async {
        let previousTokens = try? tokenStore.read()
        sessionGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskGeneration = nil
        session=nil
        pendingRequestID=""
        pendingConfirmationNonce=""
        ShoparAgency.sessions.update(nil)
        try? tokenStore.clear()
        guard let previousTokens else { return }

        // Local account data is gone before any network wait. Revoke using the
        // captured session token so a later login cannot be cleared or revoked.
        var accessToken = previousTokens.accessToken
        if previousTokens.accessTokenExpiresAt <= Int64(Date().timeIntervalSince1970) + 5 {
            var request = Shopar_Creator_V1_RefreshAgencySessionRequest()
            request.refreshToken = previousTokens.refreshToken
            if let refreshed = try? await client.refreshAgencySession(request, callOptions: callOptions(authenticated: false)) {
                accessToken = refreshed.accessToken
            }
        }
        _ = try? await client.endAgencySession(
            SwiftProtobuf.Google_Protobuf_Empty(),
            callOptions: callOptions(authenticated: false, accessTokenOverride: accessToken)
        )
    }

    private func beginAuthenticatedOperation() async throws -> UInt64 {
        let generation = sessionGeneration
        try await refreshIfNeeded(expectedGeneration: generation)
        try ensureCurrent(generation)
        return generation
    }

    private func refreshIfNeeded(expectedGeneration: UInt64) async throws {
        try ensureCurrent(expectedGeneration)
        guard let current=try tokenStore.read() else { throw AgencySDKError.sessionRequired }
        if current.accessTokenExpiresAt > Int64(Date().timeIntervalSince1970)+45 { return }
        if let refreshTask, refreshTaskGeneration == expectedGeneration {
            try await refreshTask.value
            try ensureCurrent(expectedGeneration)
            return
        }
        let task=Task { @MainActor [weak self] in
            guard let self else { throw AgencySDKError.sessionRequired }
            try self.ensureCurrent(expectedGeneration)
            var request=Shopar_Creator_V1_RefreshAgencySessionRequest();request.refreshToken=current.refreshToken
            let response=try await self.client.refreshAgencySession(request,callOptions:self.callOptions(authenticated:false))
            try self.ensureCurrent(expectedGeneration)
            try self.tokenStore.write(AgencyStoredTokens(accessToken:response.accessToken,refreshToken:response.refreshToken,accessTokenExpiresAt:response.accessTokenExpiresAt,refreshTokenExpiresAt:response.refreshTokenExpiresAt))
        }
        refreshTask=task
        refreshTaskGeneration=expectedGeneration
        do {
            try await task.value
            try ensureCurrent(expectedGeneration)
        } catch {
            if refreshTaskGeneration == expectedGeneration { refreshTask=nil;refreshTaskGeneration=nil }
            guard sessionGeneration == expectedGeneration else { throw CancellationError() }
            if let status = error as? GRPCStatus, status.code == .unauthenticated {
                invalidateSession(expectedGeneration: expectedGeneration)
            }
            throw error
        }
        if refreshTaskGeneration == expectedGeneration { refreshTask=nil;refreshTaskGeneration=nil }
    }

    private func callOptions(authenticated: Bool, accessTokenOverride: String? = nil) -> CallOptions {
        var metadata=HPACKHeaders()
        metadata.add(name:"shopar-agent",value:agent.header)
        if let accessTokenOverride { metadata.add(name:"authorization",value:"Bearer \(accessTokenOverride)") }
        else if authenticated,let tokens=try? tokenStore.read(){metadata.add(name:"authorization",value:"Bearer \(tokens.accessToken)")}
        return CallOptions(customMetadata:metadata,timeLimit:.timeout(.seconds(15)))
    }

    private func ensureCurrent(_ generation:UInt64)throws {
        guard generation==sessionGeneration,(try? tokenStore.read()) != nil else { throw CancellationError() }
    }

    private func invalidateSession(expectedGeneration: UInt64) {
        guard sessionGeneration == expectedGeneration else { return }
        sessionGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskGeneration = nil
        session = nil
        pendingRequestID = ""
        pendingConfirmationNonce = ""
        try? tokenStore.clear()
        ShoparAgency.sessions.update(nil)
    }

    private func mapSession(_ response:Shopar_Creator_V1_AgencySDKAuthResponse)->AgencyCreatorSession {
        mapSession(profile:response.profile,disclosure:response.referralDisclosure,isNewAccount:response.isNewAccount)
    }
    private func mapSession(profile:Shopar_Creator_V1_AgencyCreatorProfile,disclosure:Shopar_Creator_V1_AgencyReferralDisclosure,isNewAccount:Bool)->AgencyCreatorSession {
        AgencyCreatorSession(fullName:profile.fullName,publicUsername:profile.publicUsername,profileImageURL:profile.profileImageURL,adultEligibilityMet:profile.adultEligibilityMet,referralRelationship:disclosure.relationship,referralAgencyLabel:disclosure.referralAgencyLabel,currentAgencyLabel:disclosure.currentAppAgencyLabel,agencyVisibleDataCategories:disclosure.agencyVisibleDataCategories,isNewAccount:isNewAccount)
    }
    private func mapLink(_ value:Shopar_Creator_V1_AgencyCreatorLink)->AgencyLink { AgencyLink(id:value.id,productID:value.productID,dealID:value.dealID,shareURL:value.shareURL,status:value.status,uniqueVisitors:value.uniqueVisitors,successfulRedirects:value.successfulRedirects) }
    private static func confirmationNonce()->String { var bytes=[UInt8](repeating:0,count:32);_ = SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes);return Data(bytes).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"") }
}
