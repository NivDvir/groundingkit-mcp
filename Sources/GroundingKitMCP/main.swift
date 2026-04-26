// SPDX-License-Identifier: MIT
//
// groundingkit-mcp — MCP server exposing GroundingKit's VLM-based screen-region
// grounding to MCP-compatible AI agents.
//
// Single tool: `ground_region(image_path, prompt)` returns a JSON array of
// bounding boxes in the model's resize coordinate space (max 1280 px on the
// longest side). The model loads lazily on first tool call (~25 s cold).
//
// Transport: stdio. Run via `swift run groundingkit-mcp` or wire into Claude
// Desktop's `claude_desktop_config.json` — see README.

import Foundation
import AppKit
import MCP
import GroundingKit

// MARK: - Lazy model loading

/// The Grounder is expensive to construct (loads ~6 GB of weights and compiles
/// Metal kernels). Defer until the first tool call so MCP clients can perform
/// the `initialize` handshake immediately on startup. Wrapping inside an actor
/// keeps Grounder (non-Sendable, holds MLX state) confined to a single
/// isolation domain — only the Sendable result `[BoundingBox]` crosses the
/// boundary.
actor GrounderHolder {
    private var instance: Grounder?

    func ground(image: CGImage, prompt: String) async throws -> [BoundingBox] {
        if instance == nil {
            instance = try await Grounder()
        }
        return try await instance!.ground(image: image, prompt: prompt)
    }
}

let holder = GrounderHolder()

// MARK: - Image loading

enum LoadError: Error, LocalizedError {
    case fileNotFound(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "File not found: \(p)"
        case .decodeFailed(let p): return "Could not decode image at \(p) — supported formats: PNG, JPEG, TIFF, HEIF"
        }
    }
}

func loadCGImage(from path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw LoadError.fileNotFound(path)
    }
    guard let nsImage = NSImage(contentsOf: url),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        throw LoadError.decodeFailed(path)
    }
    return cgImage
}

// MARK: - Tool implementation

/// Encode bounding boxes as a JSON-string the MCP client can parse.
func encodeBoxes(_ boxes: [BoundingBox]) -> String {
    let dicts = boxes.map { box -> [String: Any] in
        [
            "label": box.label,
            "x1": box.x1,
            "y1": box.y1,
            "x2": box.x2,
            "y2": box.y2,
        ]
    }
    let data = (try? JSONSerialization.data(withJSONObject: dicts, options: [.prettyPrinted])) ?? Data()
    return String(data: data, encoding: .utf8) ?? "[]"
}

// MARK: - Server setup

let server = Server(
    name: "groundingkit-mcp",
    version: "0.1.0",
    capabilities: .init(
        tools: .init(listChanged: false)
    )
)

// Register tool list
await server.withMethodHandler(ListTools.self) { _ in
    let groundRegionTool = Tool(
        name: "ground_region",
        description: """
        Detect bounding-box regions in an image using a vision-language model \
        (Qwen2.5-VL on Apple Silicon, via mlx-swift-lm). Pass a path to a local \
        PNG/JPEG/TIFF/HEIF and a natural-language prompt describing what to find. \
        Returns model-coordinate bounding boxes (max 1280 px on the longest side, \
        snapped to multiples of 28 — the patch grid Qwen2.5-VL was trained on). \
        First call loads the model (~25 s); subsequent calls are fast.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "image_path": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to a local image file (PNG/JPEG/TIFF/HEIF)."),
                ]),
                "prompt": .object([
                    "type": .string("string"),
                    "description": .string("Natural-language description of what regions to detect. Best results when the prompt asks for `bbox_2d` JSON output explicitly and names each region. Example: \"Detect the question panel on the left and the editor panel on the right; output bbox_2d as a JSON array.\""),
                ]),
            ]),
            "required": .array([.string("image_path"), .string("prompt")]),
        ])
    )
    return .init(tools: [groundRegionTool])
}

// Register tool call handler
await server.withMethodHandler(CallTool.self) { params in
    guard params.name == "ground_region" else {
        return .init(content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)], isError: true)
    }
    guard let imagePath = params.arguments?["image_path"]?.stringValue,
          let prompt = params.arguments?["prompt"]?.stringValue
    else {
        return .init(
            content: [.text(text: "Missing required arguments: image_path (string), prompt (string)", annotations: nil, _meta: nil)],
            isError: true
        )
    }

    do {
        let image = try loadCGImage(from: imagePath)
        let boxes = try await holder.ground(image: image, prompt: prompt)
        let json = encodeBoxes(boxes)
        return .init(content: [.text(text: json, annotations: nil, _meta: nil)], isError: false)
    } catch {
        let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        return .init(content: [.text(text: "ground_region error: \(msg)", annotations: nil, _meta: nil)], isError: true)
    }
}

// Start server
let transport = StdioTransport()
try await server.start(transport: transport)

// Keep the process alive while the server runs over stdio
try await Task.sleep(nanoseconds: .max)
