# Shopar iOS SDK Guidelines

- Keep `ShoparAgency` and `ShoparDiscovery` independently consumable Swift Package products.
- Never add feature flags, default-disabled activation, staged rollout switches, or a global kill switch.
- Use only allowlisted public protocol bindings checked into this repository; public builds must not fetch private Shopar repositories or credentials.
- Agency sessions use only the capability-limited Agency contract. Discovery requests never attach a PWT, even if both products are installed in one host app.
- Store Agency credentials in an SDK-namespaced Keychain item under the host app's entitlements, using standard Keychain protection only. Do not add custom encryption or token wrapping.
- Never return PWTs/refresh tokens through public APIs/callbacks or write credentials to logs, analytics, crash reports, or deep links.
- Keep `app_id`, `placement_id`, session source, link source, and financial owner as distinct values.
- Do not expose raw affiliate targets in catalog, placement, or SDK callbacks; use Shopar redirect handoff.
- Do not collect advertising IDs, hardware serials, MAC addresses, or fingerprinting data.
- Keep a current `PrivacyInfo.xcprivacy` and build the public checkout without internal credentials.
