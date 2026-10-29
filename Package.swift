// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AgentMeter", platforms: [.macOS(.v14)],
    products: [.executable(name: "AgentMeter", targets: ["AgentMeter"]), .executable(name: "agentmeter-cli", targets: ["AgentMeterCLI"])],
    targets: [
        .target(name: "AgentMeterCore"),
        .executableTarget(name: "AgentMeter", dependencies: ["AgentMeterCore"], resources: [.process("Resources")]),
        .executableTarget(name: "AgentMeterCLI", dependencies: ["AgentMeterCore"]),
        .testTarget(name: "AgentMeterCoreTests", dependencies: ["AgentMeterCore"])
    ], swiftLanguageModes: [.v5]
)
