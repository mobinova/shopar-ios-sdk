import SwiftUI

@MainActor
public struct AgencySignInView: View {
    private let onSignedIn: (AgencyCreatorSession) -> Void
    @State private var email = ""
    @State private var code = ""
    @State private var challenge: AgencySignInChallenge?
    @State private var result: AgencyCreatorSession?
    @State private var errorMessage = ""
    @State private var busy = false
    @State private var showRelationshipDetails = false
    private var style: AgencyStyle { ShoparAgency.configuredStyle }

    public init(onSignedIn: @escaping (AgencyCreatorSession) -> Void = { _ in }) {
        self.onSignedIn = onSignedIn
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Shopar hesabına giriş yap")
                .font(.largeTitle.bold())
            Text("Link oluşturup performansını bu uygulamadan yönetebilirsin.")
                .foregroundStyle(style.secondaryTextColor.shoparAgencyColor)
            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundStyle(style.dangerColor.shoparAgencyColor).font(.footnote)
            }

            if let result {
                signedInView(result)
            } else if let challenge {
                codeEntry(challenge)
            } else {
                emailEntry
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: 560, alignment: .leading)
        .foregroundStyle(style.textColor.shoparAgencyColor)
        .tint(style.primaryColor.shoparAgencyColor)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .background(style.backgroundColor.shoparAgencyColor)
    }

    private var emailEntry: some View {
        VStack(spacing: 14) {
            TextField("E-posta", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Button {
                Task {
                    busy = true
                    errorMessage = ""
                    do { challenge = try await ShoparAgency.startSignIn(email: email) }
                    catch { errorMessage = "Giriş kodu gönderilemedi. Biraz sonra tekrar dene." }
                    busy = false
                }
            } label: {
                if busy { ProgressView() } else { Text("Doğrulama kodu gönder") }
            }
            .buttonStyle(ShoparAgencyPrimaryButtonStyle(style: style))
            .disabled(busy || !email.contains("@"))
            .frame(maxWidth: .infinity)
        }
    }

    private func codeEntry(_ challenge: AgencySignInChallenge) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("E-postana gönderilen 6 haneli kodu gir. Kod \(max(1, challenge.expiresInSeconds / 60)) dakika geçerli.")
                .font(.subheadline).foregroundStyle(style.secondaryTextColor.shoparAgencyColor)
            TextField("Doğrulama kodu", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .textFieldStyle(.roundedBorder)
                .onChange(of: code) { value in code = String(value.filter(\.isNumber).prefix(6)) }
            Button {
                Task {
                    busy = true
                    errorMessage = ""
                    do { result = try await ShoparAgency.confirmSignIn(requestID: challenge.requestID, code: code) }
                    catch { errorMessage = "Kod doğrulanamadı. Kontrol edip tekrar dene." }
                    busy = false
                }
            } label: {
                if busy { ProgressView() } else { Text("Giriş yap") }
            }
            .buttonStyle(ShoparAgencyPrimaryButtonStyle(style: style))
            .disabled(busy || code.count != 6)
            .frame(maxWidth: .infinity)
            Button("E-postayı değiştir") { self.challenge = nil; code = "" }
                .font(.footnote)
        }
    }

    @ViewBuilder private func signedInView(_ value: AgencyCreatorSession) -> some View {
        Text("Merhaba, \(value.fullName.isEmpty ? "Shopar kullanıcısı" : value.fullName)")
            .font(.title2.weight(.semibold))
        if value.referralRelationship == "referred_to_another_agency" {
            VStack(alignment: .leading, spacing: 8) {
                Text("Shopar hesabın başka bir ajansla ilişkilendirilmiş.").font(.headline)
                Text("Bu uygulamadaki Shopar oturumunla hesabına giriş yapabilirsin. Bu, ajansın panel erişimini değiştirmez.")
                    .font(.subheadline)
                if !value.referralAgencyLabel.isEmpty {
                    Text("Yönlendiren ajans: \(value.referralAgencyLabel)").font(.subheadline)
                }
                if showRelationshipDetails {
                    Text("Yönlendiren ajans, mevcut Shopar referral kuralları kapsamında ilişkilendirilir. Bu uygulamanın oturumu ve uygulama paneli erişimi ayrı yetkilendirilir.")
                        .font(.footnote).foregroundStyle(style.secondaryTextColor.shoparAgencyColor)
                }
                Button(showRelationshipDetails ? "Daha az bilgi" : "Bu ne demek?") {
                    showRelationshipDetails.toggle()
                }
                .font(.footnote)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.surfaceSubtleColor.shoparAgencyColor, in: RoundedRectangle(cornerRadius: style.cardCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: style.cardCornerRadius).stroke(style.borderColor.shoparAgencyColor))
        }
        Text("Devam ederek Shopar hesabını bu uygulamada kullanırsın.")
            .font(.footnote).foregroundStyle(style.secondaryTextColor.shoparAgencyColor)
        Button("Devam et") { onSignedIn(value) }
            .buttonStyle(ShoparAgencyPrimaryButtonStyle(style: style))
            .frame(maxWidth: .infinity)
    }
}

@MainActor
public struct AgencyLinksView: View {
    @StateObject private var sessionStore = ShoparAgency.sessions
    @State private var showCreatorHome = false
    @State private var query = ""
    @State private var catalog: [AgencyCatalogItem] = []
    @State private var links: [AgencyLink] = []
    @State private var errorMessage = ""
    @State private var showingSessions = false
    @State private var busy = false
    private let onOpenAccountSecurity: (() -> Void)?
    private var style: AgencyStyle { ShoparAgency.configuredStyle }

    public init(onOpenAccountSecurity: (() -> Void)? = nil) {
        self.onOpenAccountSecurity = onOpenAccountSecurity
    }

    public var body: some View {
        Group {
            if sessionStore.session == nil || !showCreatorHome {
                AgencySignInView { _ in showCreatorHome = true; loadLinks() }
            } else {
                linksContent
            }
        }
        .onChange(of: sessionStore.session) { value in
            // The host can switch accounts while this view remains mounted.
            // Never carry one creator's cached catalog/links into the next session.
            query = ""
            catalog = []
            links = []
            errorMessage = ""
            if value == nil { showCreatorHome = false }
            else if showCreatorHome { loadLinks() }
        }
        .task {
            do {
                let session=try await ShoparAgency.restoreSession()
                if session != nil { showCreatorHome=true;try await reloadLinks() }
            } catch {
                errorMessage = "Shopar hesabına ulaşılamadı. Bağlantını kontrol et."
            }
        }
        .tint(style.primaryColor.shoparAgencyColor)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .background(style.backgroundColor.shoparAgencyColor.ignoresSafeArea())
    }

    private var linksContent: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Shopar kataloğunda ara", text: $query)
                        .textInputAutocapitalization(.never)
                    Button {
                        search()
                    } label: {
                        Label("Ara", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(ShoparAgencyPrimaryButtonStyle(style: style))
                    .disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !catalog.isEmpty {
                    Section("Shopar kataloğu") {
                        ForEach(catalog) { item in
                            HStack(spacing: 12) {
                                if !item.imageURL.isEmpty {
                                    AsyncImage(url: URL(string: item.imageURL)) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.gray.opacity(0.1)
                                    }
                                    .frame(width: 58, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.subheadline.weight(.semibold))
                                    if !item.subtitle.isEmpty {
                                        Text(item.subtitle).font(.caption).foregroundStyle(style.secondaryTextColor.shoparAgencyColor)
                                    }
                                    let price = Decimal(item.priceMinorUnits) / 100
                                    Text("\(price.formatted(.number.precision(.fractionLength(0...2)))) \(item.currency)")
                                        .font(.caption)
                                }
                                Spacer()
                                Button("Link oluştur") { createLink(item) }
                                    .buttonStyle(.bordered)
                                    .disabled(busy)
                            }
                        }
                    }
                }
                Section("Paylaşımlarım") {
                    if links.isEmpty {
                        Text("Henüz paylaşımın yok. Shopar kataloğundan bir ürün seçip link oluştur.")
                            .foregroundStyle(style.secondaryTextColor.shoparAgencyColor)
                    }
                    ForEach(links) { link in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(link.productID.isEmpty ? "Fırsat paylaşımı" : "Ürün paylaşımı")
                                .font(.subheadline.weight(.semibold))
                            Text(link.shareURL).font(.caption).foregroundStyle(.secondary)
                            Text("Ziyaretçi \(link.uniqueVisitors) · Mağaza yönlendirmesi \(link.successfulRedirects)")
                                .font(.caption2).foregroundStyle(style.secondaryTextColor.shoparAgencyColor)
                            if let url = URL(string: link.shareURL) {
                                ShareLink(item: url) { Label("Paylaş", systemImage: "square.and.arrow.up") }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                if !errorMessage.isEmpty {
                    Section { Text(errorMessage).foregroundStyle(style.dangerColor.shoparAgencyColor).font(.footnote) }
                }
            }
            .navigationTitle("Shopar Creator")
            .scrollContentBackground(.hidden)
            .background(style.backgroundColor.shoparAgencyColor)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showingSessions = true } label: { Image(systemName: "iphone.gen3") }
                    Button("Çıkış") {
                        Task { await ShoparAgency.signOut(); links = []; catalog = [] }
                    }
                }
            }
            .sheet(isPresented: $showingSessions) { AgencySessionsView(onOpenAccountSecurity: onOpenAccountSecurity) }
        }
    }

    private func search() {
        busy = true; errorMessage = ""
        Task {
            do { catalog = try await ShoparAgency.searchCatalog(query) }
            catch { errorMessage = "Katalog şu anda yüklenemiyor. Tekrar dene." }
            busy = false
        }
    }

    private func createLink(_ item: AgencyCatalogItem) {
        busy = true; errorMessage = ""
        Task {
            do { links.insert(try await ShoparAgency.createLink(for: item), at: 0) }
            catch { errorMessage = "Shopar linki oluşturulamadı. Tekrar dene." }
            busy = false
        }
    }

    private func loadLinks() { Task { try? await reloadLinks() } }
    private func reloadLinks() async throws { links = try await ShoparAgency.myLinks() }
}

@MainActor
public struct AgencySessionsView: View {
    @State private var sessions: [AgencyDeviceSession] = []
    @State private var errorMessage = ""
    private let onOpenAccountSecurity: (() -> Void)?
    private var style: AgencyStyle { ShoparAgency.configuredStyle }
    public init(onOpenAccountSecurity: (() -> Void)? = nil) { self.onOpenAccountSecurity = onOpenAccountSecurity }

    public var body: some View {
        NavigationStack {
            List {
                if let onOpenAccountSecurity {
                    Section {
                        Button("Shopar hesap güvenliği ve tüm oturumlar", action: onOpenAccountSecurity)
                    } footer: {
                        Text("Bu uygulamadaki oturumların dışında Shopar ve diğer uygulamalardaki oturumları Shopar hesap ayarlarından yönetebilirsin.")
                    }
                }
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.appName).font(.headline)
                        Text("\(session.agencyName) · \(session.platform) · \(session.model)").font(.subheadline)
                        Text("\(session.operatingSystem) · \(session.appVersion)").font(.caption).foregroundStyle(style.secondaryTextColor.shoparAgencyColor)
                        if let lastActiveAt = session.lastActiveAt {
                            Text("Son etkinlik: \(lastActiveAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(style.secondaryTextColor.shoparAgencyColor)
                        }
                        if session.isCurrent { Text("Bu cihaz").font(.caption.weight(.semibold)) }
                        if !session.isCurrent {
                            Button("Oturumu kapat", role: .destructive) {
                                Task {
                                    do {
                                        try await ShoparAgency.revokeAgencySDKSession(session.id)
                                        sessions = try await ShoparAgency.myAgencySDKSessions()
                                    } catch { errorMessage = "Oturum kapatılamadı." }
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                if !errorMessage.isEmpty { Text(errorMessage).foregroundStyle(style.dangerColor.shoparAgencyColor) }
            }
            .navigationTitle("Bu uygulamadaki cihazlar")
            .scrollContentBackground(.hidden)
            .background(style.backgroundColor.shoparAgencyColor)
            .tint(style.primaryColor.shoparAgencyColor)
            .environment(\.colorScheme, style.isDark ? .dark : .light)
            .task {
                do { sessions = try await ShoparAgency.myAgencySDKSessions() }
                catch { errorMessage = "Cihaz listesi yüklenemedi." }
            }
        }
    }
}
