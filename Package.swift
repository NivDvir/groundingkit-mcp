// swift-tools-version: 6.0
//
// groundingkit-mcp — Model Context Protocol server exposing GroundingKit's
// VLM-based screen-region grounding to MCP-compatible AI agents (Claude
// Desktop, Cursor, Cline, Continue, etc.).
//
// Single tool: ground_region(image_path, prompt) -> [{label, x1, y1, x2, y2}]
//
// Stack:
//   • Official MCP SDK: modelcontextprotocol/swift-sdk (>= 0.11.0)
//   • Grounder library: NivDvir/screen-overlay-toolkit (>= main)

import PackageDescription

let package = Package(
    name: "groundingkit-mcp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "groundingkit-mcp", targets: ["GroundingKitMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/NivDvir/screen-overlay-toolkit.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "GroundingKitMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "GroundingKit", package: "screen-overlay-toolkit"),
            ]
        ),
    ]
)
