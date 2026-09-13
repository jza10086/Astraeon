---
name: godot-project-tooling
description: Resolve configurable Godot installations, run reliable headless imports or GDScript checks, and audit or initialize common Godot version-control metadata. Use for Godot project setup, CLI validation, engine-version checks, or Godot-specific .gitignore hygiene; do not use for project-specific gameplay architecture or coding-style decisions.
---

# Godot Project Tooling

Use this skill for reusable Godot tooling and project hygiene. Follow the user's request and the nearest `AGENTS.md`; project instructions override the defaults here.

## Choose the operation

- For engine discovery or headless validation, use `scripts/invoke_godot.ps1`.
- For a read-only version-control audit, use `scripts/audit_godot_vcs.ps1`.
- Before creating or changing `.gitignore` or `.gitattributes`, read [references/version-control.md](references/version-control.md). Use the templates in `assets/` as merge inputs, not as permission to overwrite existing files.
- Keep gameplay architecture, naming conventions, language choices, and project-specific test policy in the repository's `AGENTS.md`, not in this skill.

## Resolve the Godot toolchain

The resolver uses this precedence:

1. An explicit `-GodotPath`.
2. `GODOT_BIN` in the current environment.
3. The skill-local toolchain file at `godot-toolchains.json`, or an explicit `-ToolchainsFile` override.
4. `godot`, `godot4`, or `godot_console` available on `PATH`.

Resolve the expected version from explicit `-ExpectedVersion`, then `<project>/.godot-version`, then the toolchain file's `default` entry. Treat the expected version as a required prefix boundary: `4.7.stable` accepts `4.7.stable.official...`, while `4.7` accepts a `4.7.*` build. Stop on mismatch.

The bundled personal toolchain file uses this format:

```json
{
  "default": "4.7.stable",
  "versions": {
    "4.7.stable": "F:\\Godot_v4.7-stable_win64.exe\\Godot_v4.7-stable_win64_console.exe"
  }
}
```

Prefer the console executable on Windows. Do not scan arbitrary drives, download another engine, mutate `PATH`, or change the toolchain file unless the user asks.

## Run headless checks

Use one of these modes:

```powershell
& scripts/invoke_godot.ps1 -Mode Version -ProjectPath <project>
& scripts/invoke_godot.ps1 -Mode Import -ProjectPath <project>
& scripts/invoke_godot.ps1 -Mode CheckScript -ProjectPath <project> -ScriptPath res://path/to/check.gd
& scripts/invoke_godot.ps1 -Mode RunScript -ProjectPath <project> -ScriptPath res://path/to/test.gd
```

`CheckScript` parses a standalone script with `--check-only`; it does not prove runtime behavior. A `RunScript` script must terminate itself, normally by extending `SceneTree` and calling `quit()`. Report engine version, command mode, exit code, and any `SCRIPT ERROR`, `ERROR:`, parser, or parse error output. Separate automated results from editor, multiplayer, device, and deployment acceptance.

## Permissions and elevation

Start with read-only discovery and request additional access only immediately before the command that needs it. Explain the exact path or capability and why it is required.

- Project import and script execution may write `<project>/.godot/` and Godot user data such as `%APPDATA%\Godot`.
- Persisting a toolchain path or changing `PATH` writes outside the project and requires a separate explicit user request.
- Downloads, plugin installation, and remote documentation access use the network and are separate from local Godot execution.

Prefer narrowly scoped approval for the selected Godot console executable with `--headless`. Never request Full access as a convenience, change Codex permission settings, or bypass an approval. If access is denied or the first elevated attempt fails because of permissions, stop that operation and report the exact blocker; do not cycle through privileged workarounds.

## Safe mutation rules

- Do not replace an existing `.gitignore` or `.gitattributes`; merge only missing rules while preserving user entries.
- Do not ignore `*.uid` or remove tracked UID files.
- Do not delete caches, generated files, credentials, or tracked files unless explicitly requested.
- Select post-edit validation according to the changed behavior and the project testing policy. Documentation-only edits need a focused text review; run a VCS audit or headless check only when the affected metadata or Godot behavior warrants it.
