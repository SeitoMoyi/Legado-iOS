// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "Legado",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "LegadoCore",
            targets: ["LegadoCore"]),
        .library(
            name: "LegadoApp",
            targets: ["LegadoApp"]),
        .library(name: "LegadoRuntime", targets: ["LegadoRuntime"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.16")
    ],
    targets: [
        .target(name: "CQuickJS", path: "Runtime/CQuickJS", publicHeadersPath: "include",
                cSettings: [.define("_GNU_SOURCE"), .define("CONFIG_VERSION", to: "\"2026-06-04\"")]),
        .target(name: "LegadoRuntime", dependencies: ["CQuickJS"], path: "Runtime/LegadoRuntime"),
        .target(
            name: "LegadoCore",
            dependencies: [
                "SwiftSoup",
                "ZIPFoundation"
            ]),
        .target(
            name: "LegadoApp",
            dependencies: [
                "LegadoCore"
            ],
            exclude: ["Info.plist", "Assets.xcassets"]),
        .testTarget(
            name: "LegadoCoreTests",
            dependencies: ["LegadoCore"]),
        .testTarget(
            name: "LegadoAppTests",
            dependencies: ["LegadoApp"]),
        .testTarget(name: "LegadoRuntimeTests", dependencies: ["LegadoRuntime"]),
    ],
    cLanguageStandard: .gnu11
)
