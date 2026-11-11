# Shopar iOS SDK

This public Swift Package contains two independently importable products:

- **ShoparAgency** — Shopar email OTP, creator profile and social account surfaces, app-scoped links, performance, current-app sessions, and native `ShareLink` handoff.
- **ShoparDiscovery** — anonymous full-page feed, horizontal rail, and single-card Product or Deal placements.

The allowlisted protobuf and gRPC Swift bindings are checked into `Sources/ShoparProtocol`; a clean public checkout builds without the private `shopar-proto` repository or credentials. Both products use the same protocol module, so a host app can add both without duplicate generated types.

## App registration

Create a separate app property for each platform bundle in Agency Dashboard or App Studio. Save its real `app_id`. Discovery also requires at least one Placement created in App Studio; its `placement_id` is used to render Product or Deal cards. Web app properties are coming later.

## Swift Package installation

The first version tag has not been published. Once published, add this repository at the exact release version displayed on the app Setup / Docs page. That generated setup page is pinned to the tagged source and matching dependency release.

```swift
dependencies: [
    .package(url: "https://github.com/mobinova/shopar-ios-sdk.git", exact: "<exact-version>")
]
```

Add only the product(s) you use:

```swift
.product(name: "ShoparAgency", package: "shopar-ios-sdk")
.product(name: "ShoparDiscovery", package: "shopar-ios-sdk")
```

## Agency initialization

```swift
try ShoparAgency.configure(
    AgencyConfiguration(appID: "app_<dashboard-id>")
)

AgencyLinksView()
```

`AgencySignInView` runs Shopar email OTP and displays the relationship disclosure before continuing when the account's referral owner is another Agency. Public results contain safe profile and link fields; access and refresh PWTs stay in SDK-managed Keychain storage. Call `await ShoparAgency.onHostAccountChanged()` when the host app signs out or switches host users so the Shopar session and account-scoped views are ended. `AgencyLinksView(onOpenAccountSecurity:)` can route users to the host's Shopar account-security screen for reviewing and revoking sessions across Shopar and other apps; the SDK's own device screen remains limited to the current Agency app.

Pass `style: AgencyStyle(...)` to `AgencyConfiguration` to customize the bundled SwiftUI screens. Style colors use ARGB `UInt32` values, with card/control corner radii in points. `AgencyStyle.shopar` is the default and `AgencyStyle.midnight` is available. Appearance is immutable after `ShoparAgency.configure`.

```swift
try ShoparAgency.configure(AgencyConfiguration(
    appID: "app_<dashboard-id>",
    style: AgencyStyle(accentColor: 0xFFD8F36A, cardCornerRadius: 18)
))
```

## Discovery initialization

```swift
try ShoparDiscovery.configure(
    DiscoveryConfiguration(appID: "app_<dashboard-id>")
)

ShoparDiscovery.Placement(placementID: "plc_<app-studio-id>")
```

Discovery has a separate anonymous gRPC client and no Agency token storage or authorization interceptor. It renders server-selected Product and Deal cards in the configured placement format. Within the manual catalog rule, selected Products retain their order and precede selected Deals; the owner may place this rule before or after Interest rules. Shopar's Product recommendation fallback always runs last. Product taps resolve the exact ProductListing destination and Deal taps resolve the exact Deal destination. Impressions use the 50%-visible, one-second foreground rule. Item taps open Shopar's public redirect URL; the raw affiliate destination is never returned in the SDK API. Hosts may optionally observe selected Deal IDs with `ShoparDiscovery.Placement(placementID:onProductSelected:onDealSelected:)`; navigation remains SDK-owned.

`collectDeviceMetadata` sets the initial preference. Call `ShoparDiscovery.setOptionalDeviceMetadataCollectionEnabled(_:)` whenever the host privacy preference changes; `false` omits optional model/OS/locale/timezone values from future requests without rotating the `dev_` installation ID. There is no queued optional context to drain. Required app/placement/event attribution continues. The installation ID is not a person identifier.

Call `ShoparDiscovery.resetInstallationIdentity()` only after a user explicitly requests an identity reset. The SDK stores the `dev_` ID in a non-synchronizing, `ThisDeviceOnly` Keychain item and keeps an excluded-from-backup app-private fallback for pre-first-unlock startup. A same-device reinstall may retain the Keychain ID; reset rotates it and leaves prior server history separate. Storage loss can also result in a new ID.

Pass `style: DiscoveryStyle(...)` to `DiscoveryConfiguration` to customize Product/Deal placement cards and controls. Style colors use ARGB `UInt32` values, with card/control corner radii in points. `DiscoveryStyle.shopar` is the default and `DiscoveryStyle.midnight` is available. Appearance is fixed when `ShoparDiscovery.configure` initializes the module. The host still owns placement sizing and layout; the SDK response supplies Product/Deal content and the server-selected format.

```swift
try ShoparDiscovery.configure(DiscoveryConfiguration(
    appID: "app_<dashboard-id>",
    style: DiscoveryStyle(accentColor: 0xFFD8F36A, cardCornerRadius: 18)
))
```

## Privacy and samples

The Agency and Discovery targets each bundle a `PrivacyInfo.xcprivacy` manifest. Review [privacy and Data safety guidance](docs/privacy-and-data-safety.md) before release. `Examples/ShoparIntegrationSample` references both SDK products from one target and can be built for iOS with:

```sh
swift build --package-path Examples/ShoparIntegrationSample --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" --triple arm64-apple-ios16.0
```

The sample IDs are compile-time placeholders; use real Dashboard IDs to load live data.
