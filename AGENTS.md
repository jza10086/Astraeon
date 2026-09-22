# Astraeon Development Rules

## Scope and priorities
- Build an indie-scale 3D voxel survival and building game. Complete small playable loops before expanding systems.
- Use simple, direct implementations and feature-oriented folders. Avoid speculative frameworks and premature optimization. Follow the current module layout in docs/project_structure.md and the directory rules below.
- The project is in the prototype stage. Maintain only the current contract: do not retain or add backward-compatibility aliases, adapters, legacy branches, old-format readers, version-range fallbacks, or migration converters. Update callers, assets, tests, and documentation together when a contract changes; reject unsupported save/config formats explicitly. Historical benchmarks may remain isolated as comparison evidence, never as production compatibility paths. Recoverable writes within the current format remain required.
- Treat the current README and implemented features as the source of project status. Camera perspective, voxel representation, world limits, multiplayer, and progression require explicit design decisions; update these rules as decisions are approved.
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
- When no verified live MCP editor is available, authorized filesystem edits are allowed with validation appropriate to the change; cold-start engine/plugin bootstrapping requires a full import. Do not launch a second editor or import against a checkout already open in an editor; prefer its MCP diagnostics.
- After external edits with an editor connected, call targeted editor_refresh and editor_wait_for_idle before relying on editor state.
- Use typed script/scene/resource deletion tools to keep UID companions consistent. Never delete generated caches as routine repair.
- Discover only needed MCP groups and reset them after the task.
- Repository rules override generic companion-skill advice. Maintain project-specific adaptations in .agents/skills/; preserve the upstream copies under addons/godot_mcp_toolkit/CompanionSkills/.
- Vendored third-party code is exempt from project-authored style rules. New project-authored extensions, including those under addons/, follow explicit typing and naming rules.

## Modules and directories
- Organize production code by function under game/: data, world, entities, shading, gameplay, core, and ui. Use shading as the module name; do not introduce a lighting module or compatibility alias.
- Put project-authored C++ in game/<module>/native/ and GDScript in the nearby gdscript/ directory. Split large modules into feature subdirectories first (for example entities/player/gdscript/). Keep scenes/, resources/, assets/, and shaders/ with the owning feature; do not mix .cpp/.h files with GDScript or put native implementations in a global project-code bucket.
- Current world native features are game/world/native/generation/, persistence/, and streaming/. Native directories carry .gdignore. The build stages game/*/native into tmp and compiles an explicit current source manifest into the existing Voxel Tools GDExtension; never compile old staged sources by a broad fallback glob.
- Keep upstream Voxel Tools and godot-cpp sources under native/voxel_tools/ and native/deps/godot-cpp/. Upstream integration patches remain there; standalone project features belong in game/<module>/native/. Build outputs belong in tmp/ and deployed binaries in addons/zylann.voxel/bin/ (ignored by Git).
- data owns static authoring definitions; world owns authoritative voxel state, generation, streaming, meshing/collision and persistence; entities owns instance behavior and animation; shading owns rendering/environment effects; gameplay owns interaction and game rules; core assembles modules and ui presents them. Share static templates read-only, and do not create a second authoritative voxel mirror.
- The root test/ directory, alongside game/, is the target for ALL test-purpose content: test code, test scenes, demonstrations, benchmarks, fixtures, test-only assets/resources, runners and versioned reports. Group it by module (test/world, test/entities, test/shader, etc.), separating native/ and gdscript/ when both are needed. Disposable logs, generated worlds, transient results and binaries still go to tmp/.
- test/ has only been established and documented in this change. Existing tests/, benchmarks/ and other test-only content will be migrated by the agent responsible for each module at the user's direction; do not perform that bulk migration as part of this production-folder cleanup. No legacy path aliases or duplicate compatibility copies.
- Preserve resource UID and import settings when moving files; update scene/script references, build source manifests, active documentation and tests together. Avoid speculative empty feature directories.

## Block appearance contract
- Follow docs/voxel_chunks.md for the approved 1-unit (1-meter) block and material design. BlockAppearance, BlockSurface, and BlockLightAppearance are planned shared read-only Resources owned by shading; do not claim their runtime integration before implementation.
- Static logic definitions reference appearance resources. World/gameplay own instance coordinates, current orientation, and mining state; shading must not duplicate these authoritative states or mutate shared templates for per-instance changes.
- Keep surface emission independent from surrounding illumination. Block canonical axes are up +Y, front -Z, right +X; apply authoring correction before instance orientation, including faces, normals, and light offsets. This does not override character asset axes.
- Compile shared appearances for batched rendering; never create a Resource, Material, or light node per production voxel. Lighting schemes and budgets remain global rendering policy; visual transparency does not implicitly set logical light opacity or collision.

## Language boundaries and scenes
- Use C++ with Voxel Tools GDExtension as the approved production voxel backend; see docs/native_voxel_backend.md. Use GDScript for gameplay orchestration, UI, scene integration, and test drivers. In GDScript, never use :=; explicitly type variables, arguments, return values, signals, arrays, and dictionaries where supported.
- Use explicit Variant only when multiple types are intentional.
- The user explicitly approved C++ voxel infrastructure and secondary development of Voxel Tools beyond the isolated benchmark. Put production voxel storage, generation, streaming/task scheduling, meshing, collision-data generation, and persistence hot paths in C++; avoid per-voxel GDScript/native calls. The old GDScript voxel implementations and their dedicated runners have been removed; retain only historical measurement evidence. Static authoring Resources under game/data are not a runtime voxel backend. This decision does not authorize a C# migration or establish an unmeasured performance guarantee.
- Use snake_case for files, functions, variables, resources, and signals; PascalCase for nodes, enums, and class_name; UPPER_SNAKE_CASE for constants.
- Register class_name only for shared components, custom resources, and reusable data types.
- Prefer composition. Use @export for configurable resources and replaceable node references; validate required references at startup.
- Use %UniqueNode for stable private scene nodes. Use preload() for existing static dependencies without cycles and load() for runtime-selected paths; prefer @export for configurable resources. Keep scenes, scripts, and dedicated resources together.
- Static definitions belong in custom Resources; mutable runtime state must not modify shared resource templates.
- Add autoloads only when a real cross-scene service requires them; no speculative managers.
- Explain module boundaries and non-obvious decisions. Document public or complex APIs with ##.

## Voxel and survival boundaries
- Current intended direction is Minecraft-like block terrain generation, mining, and building. Keep authoritative voxel data separate from derived render meshes and collision shapes.
- A chunk is a horizontal 16x16-voxel column; a section is 16x16x16 voxels. Use horizontal circular streaming with an independent vertical range. See docs/voxel_chunks.md for coordinates and boundary rules.
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
