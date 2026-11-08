// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "shopar-ios-sdk",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "ShoparAgency", targets: ["ShoparAgency"]),
        .library(name: "ShoparDiscovery", targets: ["ShoparDiscovery"]),
        .library(name: "ShoparProtocol", targets: ["ShoparProtocol"]),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift", exact: "1.26.1"),
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.28.1"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.83.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", exact: "1.46.0"),
        // Keep the transitive graph compatible with the minimum CI compiler (Swift 6.1).
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.2.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.7.1"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", exact: "2.9.1"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", exact: "1.0.4"),
        .package(url: "https://github.com/apple/swift-certificates.git", exact: "1.20.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", exact: "1.7.2"),
    ],
    targets: [
        .target(
            name: "ShoparProtocol",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOHPACK", package: "swift-nio-http2"),
            ],
            path: "Sources/ShoparProtocol"
        ),
        .target(
            name: "ShoparAgency",
            dependencies: [
                "ShoparProtocol",
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            resources: [.process("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "ShoparDiscovery",
            dependencies: [
                "ShoparProtocol",
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "NIOHPACK", package: "swift-nio-http2"),
            ],
            resources: [.process("PrivacyInfo.xcprivacy")]
        ),
    ]
)
