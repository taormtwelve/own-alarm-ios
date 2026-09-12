// swift-tools-version: 5.9
import PackageDescription

// Test-only scaffolding. The app itself is built by Xcode from `OwnAlarm/`; this
// package exists so the platform-independent model layer can be compiled and tested
// anywhere Swift runs — including Windows and CI, with no Apple SDK in sight.
//
// It deliberately covers only `OwnAlarm/Model`. Everything else in the app touches
// SwiftUI, UserNotifications or AVFoundation, none of which exist off-platform.
let package = Package(
    name: "OwnAlarmCore",
    products: [
        .library(name: "OwnAlarmCore", targets: ["OwnAlarmCore"])
    ],
    targets: [
        .target(
            name: "OwnAlarmCore",
            path: "OwnAlarm/Model"
        ),
        .testTarget(
            name: "OwnAlarmCoreTests",
            dependencies: ["OwnAlarmCore"],
            path: "Tests/OwnAlarmCoreTests"
        )
    ]
)
