# Astraeon Development Rules

## Scope and priorities
- Build an indie-scale 3D voxel survival and building game. Complete small playable loops before expanding systems.
- Use simple, direct implementations and feature-oriented folders. Avoid speculative frameworks and premature optimization.
- The current project is an environment scaffold. Camera perspective, voxel representation, world limits, multiplayer, and progression are not yet product decisions.
- Do not import GodotParty activities, its SDK, party-game rules, player limits, or networking assumptions.

## Editing and permissions
- Carry out authorized, reversible project work without repeated confirmation. Respect platform permissions.
- If access is denied, stop the blocked operation and report the exact reason; do not cycle through privileged workarounds.
- Never modify another project when working on Astraeon.

## Godot tooling and skills
- Engine: Godot 4.7 stable. Use .godot-version and .agents/skills/godot-project-tooling/SKILL.md for engine discovery, headless validation, and VCS hygiene.
- For a live editor workflow read .agents/skills/godot-mcp-toolkit/SKILL.md. For an explicitly requested MCP extension read .agents/skills/mcp-extension-creator/SKILL.md.
- Set GODOT_MCP_PROJECT_PATH to this checkout before starting the MCP client. Verify project_get_settings reports application/config/name = ASTRAEON before any mutation; verify the connected path when available.
- Prefer structured MCP tools for scenes, nodes, resources, input, settings, and scripts when connected to the correct editor.
- Cold-start bootstrapping without a verified live editor may use filesystem edits followed by a full headless import.
- After external edits with an editor connected, call targeted editor_refresh and editor_wait_for_idle before relying on editor state.
- Use typed script/scene/resource deletion tools to keep UID companions consistent. Never delete generated caches as routine repair.
- Discover only needed MCP groups and reset them after the task.
- Repository rules override generic companion-skill advice about class_name and references.
- Third-party code under addons/ and copied skills is exempt from project-authored style rules.

## GDScript and scenes
- Default to GDScript. Never use :=. Explicitly type variables, arguments, return values, signals, arrays, and dictionaries where supported.
- Use explicit Variant only when multiple types are intentional.
- Consider GDExtension or C# only after measured, serious performance bottlenecks remain after algorithmic optimization.
- Use snake_case for files, functions, variables, resources, and signals; PascalCase for nodes, enums, and class_name; UPPER_SNAKE_CASE for constants.
- Register class_name only for shared components, custom resources, and reusable data types.
- Prefer composition. Use @export for configurable resources and replaceable node references; validate required references at startup.
- Use %UniqueNode for stable private scene nodes. Keep scenes, scripts, and dedicated resources together.
- Static definitions belong in custom Resources; mutable runtime state must not modify shared resource templates.
- Add autoloads only when a real cross-scene service requires them; no speculative managers.
- Explain module boundaries and non-obvious decisions. Document public or complex APIs with ##.

## Voxel and survival boundaries
- Keep authoritative voxel data separate from derived render meshes and collision shapes.
- Plan chunk coordinates and local voxel coordinates explicitly; include negative coordinates in future coordinate tests.
- Avoid one Node per voxel for production terrain. Choose chunk sizing, meshing, streaming, and threading based on a measured prototype.
- Background work must not mutate the active scene tree. Commit scene/resource changes on the main thread.
- When saves are implemented, version the format and persist seed, generation version, and player changes with recoverable writes.
- Keep world generation, mining/building, inventory, crafting, and survival responsibilities in their feature folders.
- Multiplayer is undecided. Do not create transport or authority layers until requested.

## Input, UI, and assets
- Keyboard and mouse are the initial input target; gameplay reads named InputMap actions.
- Add bindings with their actual feature, rather than shipping inactive controls.
- Local settings use user://settings.cfg with ConfigFile defaults on first run.
- UI baseline is 1920x1080, canvas_items stretch, expand aspect, fractional scaling. Use anchors and containers.
- Check 2560x1440, 3840x2160, and ultrawide when real UI is introduced.
- Record third-party assets and dependencies in docs/credits.md and retain required license files.

## Validation and completion
- Finish a coherent change batch before validation. Use the smallest check that answers the changed behavior.
- Docs need focused review; configuration needs syntax/value checks; engine/plugin/shared-resource changes require a full import.
- Check exit status and SCRIPT ERROR, ERROR:, and parser output. A zero exit code alone does not prove success.
- Use focused future tests for chunk boundaries, deterministic generation, inventory transactions, and save round trips when those features exist.
- Manual visual, physics, interaction, and performance acceptance remains separate from headless checks.
- Do not add tests that merely restate the scaffold or rerun unchanged successful checks.

## Git and temporary files
- Work directly on main unless the user requests another branch. Commit coherent, runnable changes with concise English imperative messages.
- Preserve .uid files; never commit .godot/, local saves/settings, credentials, or import caches.
- Put disposable logs, probes, and generated test artifacts in tmp/ with .gdignore. Do not create temporary sibling projects.
