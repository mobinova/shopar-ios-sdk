import Foundation

/// Entry point and capability-limited API for the Shopar Agency SDK.
@MainActor
public enum ShoparAgency {
    static let sdkVersion = "0.1.0"
    private static var storedConfiguration: AgencyConfiguration?
    private static var runtime: AgencyRuntime?

    static var configuredStyle: AgencyStyle { storedConfiguration?.style ?? .shopar }

    public static let sessions=AgencySessionObservable()
    public static var creatorSession: AgencyCreatorSession? { sessions.session }

    public static func configure(_ configuration: AgencyConfiguration) throws {
        if let existing=storedConfiguration,existing != configuration{throw AgencySDKError.alreadyConfiguredForAnotherApp}
        if runtime==nil{runtime=try AgencyRuntime(configuration:configuration)}
        storedConfiguration=configuration
    }

    public static func startSignIn(email:String) async throws -> AgencySignInChallenge { try await requireRuntime().startSignIn(email:email) }

    /// Confirms the Shopar email code. Access and refresh PWTs remain inside the SDK.
    public static func confirmSignIn(requestID:String,code:String) async throws -> AgencyCreatorSession {
        let runtime = try requireRuntime()
        _ = try await runtime.confirmSignIn(requestID:requestID,code:code)
        guard let session = runtime.session else { throw CancellationError() }
        sessions.update(session)
        return session
    }

    /// Restores only the safe profile projection after an app restart.
    @discardableResult public static func restoreSession() async throws -> AgencyCreatorSession? {
        let runtime = try requireRuntime()
        _ = try await runtime.restoreSession()
        let session = runtime.session
        sessions.update(session)
        return session
    }

    public static func getMyProfile() async throws -> AgencyCreatorSession {
        let runtime = try requireRuntime()
        _ = try await runtime.profile()
        guard let session = runtime.session else { throw CancellationError() }
        sessions.update(session)
        return session
    }

    public static func searchCatalog(_ query:String,page:Int32=1,pageSize:Int32=30) async throws -> [AgencyCatalogItem] {
        try await requireRuntime().searchCatalog(query,page:page,pageSize:pageSize)
    }

    public static func createLink(for item:AgencyCatalogItem,idempotencyKey:String=UUID().uuidString) async throws -> AgencyLink {
        try await requireRuntime().createLink(item:item,idempotencyKey:idempotencyKey)
    }

    public static func myLinks() async throws -> [AgencyLink] { try await requireRuntime().links() }
    public static func updateProfile(fullName:String?=nil,publicUsername:String?=nil)async throws->AgencyCreatorSession{let runtime=try requireRuntime();_=try await runtime.updateProfile(fullName:fullName,publicUsername:publicUsername);guard let session=runtime.session else{throw CancellationError()};sessions.update(session);return session}
    public static func mySocialAccounts()async throws->[AgencySocialAccount]{try await requireRuntime().socialAccounts()}
    public static func saveSocialAccount(platform:String,username:String)async throws->AgencySocialAccount{try await requireRuntime().saveSocialAccount(platform:platform,username:username)}
    public static func deleteSocialAccount(platform:String)async throws{try await requireRuntime().deleteSocialAccount(platform:platform)}
    public static func setProfilePhoto(_ image:Data,contentType:String)async throws->String{try await requireRuntime().setProfilePhoto(image,contentType:contentType)}
    public static func linkPerformance(_ sharedLinkID:String,period:String="last_30_days")async throws->AgencyLinkPerformance{try await requireRuntime().linkPerformance(sharedLinkID,period:period)}
    public static func openLink(_ sharedLinkID:String,idempotencyKey:String=UUID().uuidString)async throws->URL{try await requireRuntime().openLink(sharedLinkID,idempotencyKey:idempotencyKey)}
    public static func myAgencySDKSessions() async throws -> [AgencyDeviceSession] { try await requireRuntime().agencySessions() }
    public static func revokeAgencySDKSession(_ sessionID:String) async throws { try await requireRuntime().revokeSession(sessionID) }

    public static func signOut() async {
        sessions.update(nil)
        await runtime?.signOut()
    }

    /// Hosts call this when their own user signs out or switches accounts.
    public static func onHostAccountChanged() async { await signOut() }

    private static func requireRuntime() throws -> AgencyRuntime {
        guard let runtime else{throw AgencySDKError.notConfigured}
        return runtime
    }
}
