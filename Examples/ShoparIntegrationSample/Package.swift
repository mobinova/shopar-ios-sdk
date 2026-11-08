// swift-tools-version: 6.0
import PackageDescription

let package=Package(
    name:"ShoparIntegrationSample",
    platforms:[.iOS(.v16)],
    products:[.library(name:"ShoparIntegrationSample",targets:["ShoparIntegrationSample"])],
    dependencies:[.package(path:"../..")],
    targets:[.target(name:"ShoparIntegrationSample",dependencies:[.product(name:"ShoparAgency",package:"shopar-ios-sdk"),.product(name:"ShoparDiscovery",package:"shopar-ios-sdk")])]
)
