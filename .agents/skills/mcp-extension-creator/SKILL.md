---
name: mcp-extension-creator
description: Create explicitly requested Astraeon MCP toolkit extensions in Godot 4.7 GDScript. Not for ordinary gameplay work.
---

# Astraeon MCP extensions

Follow [AGENTS](../../../AGENTS.md) and [development workflow](../../../docs/tooling/development.md).
Use GDScript with explicit types and no `:=`. Retain toolkit-required class registration.
Default to implementing the requested extension; guided design is only used when the user asks for it.

## Implement

1. Verify the connected project name ASTRAEON and checkout path before mutations; preserve unsaved scenes.
2. Read the existing `MCPToolkitExtension` and registry contracts. Use a unique custom wire namespace.
3. Declare `@tool`, `class_name`, and direct `extends MCPToolkitExtension`; provide typed register and handler methods.
4. Describe the parameters, result and side effects in `##` comments and JSON schema. Validate input in the handler: schema advertisement alone does not validate execution.
5. Use project/user path guards for paths and Untrusted.wrap for external content, never re-wrap an already wrapped tool response. Read-only annotations must reflect actual behavior; process control is not a harmless read.
6. Return MCPToolkitSuccess/MCPToolkitError envelopes and only registered error codes. Cancellation and scene leases follow the toolkit contract.

## Verify

From the project root, replace the example path with the real extension:

```powershell
& ./.agents/skills/godot-project-tooling/scripts/invoke_godot.ps1 -Mode CheckScript -ProjectPath . -ScriptPath res://addons/your_extension/your_extension.gd
```

Parsing is not runtime validation. Through the verified editor perform full `editor_refresh`, wait for idle, inspect diagnostics, refresh extension discovery, and check registration plus one successful and one invalid-input call. Keep test outputs isolated. Do not cold-import an open checkout or stop an unrelated game.

## Detailed references

- [Bundled extension mechanics](../../../addons/godot_mcp_toolkit/CompanionSkills/mcp-extension-creator/SKILL.md): consult the options, path safety and error-envelope sections as needed. Old-engine, C# and distribution sections do not set Astraeon policy or authorize a language migration.
- [Type coercion](references/type-coercion.md), [cancellation](references/cancellation.md), [exporting](references/exporting.md): read only for the corresponding feature.
- Prefer current Godot 4.7 APIs; no old-version fallback code in project extensions. Use the repository import/refresh and process ownership rules even when an upstream example is less restrictive.
