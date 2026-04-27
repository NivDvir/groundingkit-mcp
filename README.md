# groundingkit-mcp

[Model Context Protocol][mcp] server exposing on-device VLM-based screen-region grounding to MCP-compatible AI agents (Claude Desktop, Cursor, Cline, Continue, etc.).

Built on top of [GroundingKit][gk] — native Swift Qwen2.5-VL inference on Apple Silicon with no Python in the inference path.

[mcp]: https://modelcontextprotocol.io
[gk]: https://github.com/NivDvir/screen-overlay-toolkit

## What it does

Exposes one MCP tool:

```
ground_region(image_path: string, prompt: string) -> [{label, x1, y1, x2, y2}]
```

Pass a path to a local PNG/JPEG and a natural-language prompt; get back model-coordinate bounding boxes (max 1280 px on the longest side).

Examples of what an AI agent would call:
- `ground_region("/tmp/screenshot.png", "the OK button at the bottom of the dialog")`
- `ground_region("/tmp/leetcode.png", "the question panel on the left and the editor panel on the right; output bbox_2d JSON array")`
- `ground_region("/tmp/wikipedia.png", "the main article content area, excluding the sidebar")`

## Requirements

- macOS 14+ (Apple Silicon)
- Swift 6.0+ (Xcode 16+) to build from source
- Qwen2.5-VL-7B-Instruct-4bit model weights in HuggingFace cache (~6 GB)

## Install (build from source)

> **Important:** must build via `xcodebuild`, **not** `swift build`. mlx-swift's
> Cmlx target relies on Xcode's auto-discovered Metal-compiler phase to produce
> `default.metallib`. SwiftPM has no equivalent phase and silently skips it,
> producing a binary that crashes the moment the model tries to dispatch the
> first GPU kernel. This is tracked upstream as a SwiftPM-build-plugin gap;
> until that lands, `xcodebuild` is the only working path.

```bash
git clone https://github.com/NivDvir/groundingkit-mcp.git
cd groundingkit-mcp
xcodebuild -scheme groundingkit-mcp -configuration Release \
           -destination 'platform=macOS' build
# Binary lands at:
#   ~/Library/Developer/Xcode/DerivedData/groundingkit-mcp-*/Build/Products/Release/groundingkit-mcp
```

Convenience: copy the binary to a stable path so config files don't break on Xcode rebuilds.
```bash
mkdir -p ~/.local/bin
cp "$(find ~/Library/Developer/Xcode/DerivedData -path '*groundingkit-mcp-*' \
       -name groundingkit-mcp -perm +111 | grep Release/groundingkit-mcp | head -1)" \
   ~/.local/bin/groundingkit-mcp
```

The first run will download the model from HuggingFace if not cached:

```bash
~/.local/bin/groundingkit-mcp  # waits for stdio MCP requests
```

To use a different VLM (any Qwen2.5-VL-architecture derivative — UI-TARS-1.5-7B is verified):

```bash
GK_MODEL=mlx-community/UI-TARS-1.5-7B-4bit ~/.local/bin/groundingkit-mcp
```

## Use with Claude Desktop

Add to your `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "groundingkit": {
      "command": "/Users/YOU/.local/bin/groundingkit-mcp"
    }
  }
}
```

Restart Claude Desktop. The `ground_region` tool will appear in Claude's available-tools list. First call takes ~25 s while the model loads; subsequent calls are fast.

## Use with Cursor / Cline / Continue

Same shape — add the MCP server entry to your client's config (each client has its own location). The server uses **stdio** transport, no port to bind.

## Tool behavior notes

- **Coordinates are in the model's resize space** — the longest side is capped at 1280 px, snapped to multiples of 28 (the patch grid Qwen2.5-VL was trained on). To project back to screen pixels, the caller must scale by `screen.width / 1280`.
- **First call is slow** (~25 s on M-series chips) while the model loads. Subsequent calls in the same server lifetime are fast.
- **Prompts matter.** For Qwen2.5-VL, asking for `bbox_2d` JSON output explicitly and listing each region numerically yields the most reliable results.
- **Image format**: PNG, JPEG, TIFF, HEIF — anything Apple's `NSImage(contentsOf:)` accepts.

## Tool contract

This server implements the [GroundingKit ecosystem `ground_region` spec][spec] — same tool name, input schema, and output shape as [`groundingkit-osaurus`][osa]. AI agents that work with one will work with the other.

## Why this exists

Screen-grounding (semantic "where is X on this screen?") is a missing primitive in the MCP ecosystem. Existing macOS-MCP servers ([applescript-mcp][asmcp] and similar) cover process control and Apple-framework primitives, but not VLM-based visual region detection. This server fills that gap.

[asmcp]: https://github.com/peakmojo/applescript-mcp

## Verifying the server

Quick MCP-protocol smoke test (requires `jq`):

```bash
( echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}'; sleep 1 ) | ~/.local/bin/groundingkit-mcp | jq .
```

You should see an `initialize` response with the server's capabilities and a `ground_region` tool listed via a follow-up `tools/list` call.

## License

MIT — see [LICENSE](LICENSE).

## Related

- [GroundingKit][gk] — the underlying Swift library and consumer macOS overlay app
- [Ecosystem spec][spec] — canonical `ground_region` contract for all adapters
- [groundingkit-osaurus][osa] — same `ground_region` capability exposed as an Osaurus plugin
- [mlx-swift-lm PR #222][pr222] — upstream Qwen2.5-VL fixes that make this possible
- [Official MCP Swift SDK][sdk] — what this server is built on

[spec]: https://github.com/NivDvir/screen-overlay-toolkit/blob/main/docs/ECOSYSTEM_SPEC.md
[osa]: https://github.com/NivDvir/groundingkit-osaurus
[pr222]: https://github.com/ml-explore/mlx-swift-lm/pull/222
[sdk]: https://github.com/modelcontextprotocol/swift-sdk
