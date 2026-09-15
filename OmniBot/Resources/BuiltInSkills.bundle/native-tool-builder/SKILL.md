---
name: native-tool-builder
description: Create and edit persistent SwiftUI native tools inside OmniBot. Use for 创建小工具、修改小工具、原生工具、工具包、TOTP、两步认证、计数器、待办清单 or requests to make an interactive utility available in the Tools tab.
metadata:
  display-name: 原生工具制作
  display-description: 用 AI 制作和修改原生小工具，支持清单、计算、计时和两步认证，并保存到「工具」页面。
---

# 原生工具制作

Create a structured JSON tool package rendered by OmniBot's built-in SwiftUI components. Before authoring, read `references/package-format.md` relative to this skill. Use only its supported components, expressions and actions; never invent native capabilities or generate HTML/JavaScript/Swift as the runnable tool.

## Workflow

1. Read the package format and the relevant example in `assets/`. Discover installed tools with `native_tool_list` when editing. Use `native_tool_read` to retrieve the existing UUID, revision and package; it intentionally excludes the user's runtime data.
2. Write the complete JSON source into a descriptive workspace path with `file_write`. Keep personal sample data fictional. Use empty collections and safe initial values for new tools.
3. Call `native_tool_validate` on that path. Correct reported errors before installation.
4. Call `native_tool_install` when creating or updating the tool requested by the user. For updates, pass the existing `tool_id` and `expected_revision`; preserve state keys/types. Re-read after a revision conflict. Installation preserves user data and retains the previous package version.
5. Return the tool's actual `openURL` as a Markdown link, so the user can open the native tool in OmniBot. State the implemented behavior and any requested capability that is unavailable. Do not claim visual or device verification from JSON validation.

For TOTP, use the built-in `totp` component and declare `capabilities: ["totp"]`. Account enrollment, credentials, display, copying and encrypted backup belong to the host's authenticated native UI. Never ask for an OTP secret or QR code in chat, write it into a package, or implement cryptography with generic expressions. No secrets or current codes are exposed to Agent tools.

The first runtime supports local data, bounded expressions, collection actions, page navigation, foreground countdowns and native TOTP. Network requests, shell commands, background jobs, arbitrary scripts and additional system APIs are unavailable. Explain the boundary when a request needs one; build only the useful supported portion with the user's agreement on a materially reduced scope.

## References and starting points

- `references/package-format.md`: exact schema, component properties, expression syntax, action semantics and update rules.
- `assets/checklist.json`: a persistent checklist with add, complete and delete actions.
- `assets/calculator.json`: a live unit converter using typed inputs and expressions.
- `assets/countdown.json`: a foreground timer based on the device clock.
- `assets/totp.json`: an authenticated native TOTP manager.
