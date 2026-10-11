# Astraeon Development Rules

## Scope and priorities
- Build an indie-scale 3D voxel survival and building game. Complete small playable loops before expanding systems.
- Use simple, direct implementations and feature-oriented folders. Avoid speculative frameworks and premature optimization. Follow the current module layout in total_development.md and the directory rules below.
- The project is in the prototype stage. Maintain only the current contract: do not retain or add backward-compatibility aliases, adapters, legacy branches, old-format readers, version-range fallbacks, or migration converters. Update callers, assets, tests, and documentation together when a contract changes; reject unsupported save/config formats explicitly. Historical benchmarks may remain isolated as comparison evidence, never as production compatibility paths. Recoverable writes within the current format remain required.
- **Fail fast in the prototype:** unexpected creation, validation, or runtime I/O failures must report the exact error and stop the affected operation/system. Do not add retries, alternative implementations, substitute objects, automatic item returns, or compensating gameplay branches to keep running. In particular, dropped-item generation failure stops the world; it does not restore items or try another spawn position. Expected gameplay outcomes (full inventory, partial pickup, unloaded terrain, invalid player placement) remain ordinary validation results. Maintain atomic/recoverable writes within the current save format; crash recovery is a persistence contract, not permission to silently repair invalid content. Do not persist partially applied failed runtime operations.
- Treat total_development.md, module documentation and implemented features as the source of project status. Camera perspective, final world limits, multiplayer, and progression require explicit design decisions; update these rules as decisions are approved.
- Do not import GodotParty activities, its SDK, party-game rules, player limits, or networking assumptions.

## Editing and permissions
- Carry out authorized, reversible project work without repeated confirmation. Respect platform permissions.
- If access is denied, stop the blocked operation and report the exact reason; do not cycle through privileged workarounds.
- Never modify another project when working on Astraeon.

## Godot tooling and skills
- Engine: Godot 4.7 stable. Use .godot-version and .agents/skills/godot-project-tooling/SKILL.md for engine discovery, headless validation, and VCS hygiene.
- For a live editor workflow read .agents/skills/godot-mcp-toolkit/SKILL.md. For an explicitly requested MCP extension read .agents/skills/mcp-extension-creator/SKILL.md.
- **Identify the target:** set GODOT_MCP_PROJECT_PATH to this checkout before starting the MCP client; read project_get_settings with prefix application/config/name and require ASTRAEON before MCP mutations. Verify the connected path when available; a matching name alone cannot distinguish checkouts. A Godot process name or blank window title does not identify its project or whether it is an editor. A failed MCP connection does not prove the editor is closed.
- **Choose one editor/import route:** reuse the verified editor and its MCP diagnostics. Do not launch a second editor or a separate import against the same checkout while its editor is open. Without a verified MCP connection, authorized filesystem edits remain allowed; determine whether this checkout is open before a cold import. Unknown process identity only leaves the conflicting editor/import operation unresolved, not all work or tests.
- **Keep editor state current:** prefer structured MCP edits; preserve unsaved scenes. After external changes to engine-consumed files, call targeted editor_refresh and editor_wait_for_idle before relying on editor state. Documentation-only edits need text review, not import or refresh. Cold-start engine/plugin setup and changes listed under Validation require full import through the chosen route.
- **Manage native builds and processes:** run one native build at a time. After a DLL rebuild, restart the editor before validating new native APIs; filesystem refresh cannot replace its loaded DLL. New game processes use the current extension descriptor. Do not terminate unidentified or user-owned processes automatically; normally close only task-owned test processes. Record PID, start time, executable, project path and purpose at launch, then recheck before stopping to avoid PID reuse. ALREADY_PLAYING is not permission to stop a game. Authorized launches do not require repeated confirmation.
- **Keep measurements isolated:** game/test processes are not categorically blocked by an editor's existence. During performance measurements, do not run other tests or builds; identify and report competing workloads separately from editor/import conflicts.
- Use typed script/scene/resource deletion tools to keep UID companions consistent. Never delete generated caches as routine repair.
- Discover only needed MCP groups and reset them after the task.
- Repository rules override generic companion-skill advice. Maintain project-specific adaptations in .agents/skills/; keep narrowly scoped corrections to bundled CompanionSkills and plugin hints consistent with project rules; record these local patches in docs/tooling/mcp_local_changes.md and review them on plugin updates.
- Vendored third-party code is exempt from project-authored style rules. New project-authored extensions, including those under addons/, follow explicit typing and naming rules.

## Modules and directories
- Organize production code by function under game/: data, world, entities, shading, gameplay, core, and ui. Use shading as the module name; do not introduce a lighting module or compatibility alias.
- Put project-authored C++ in game/<module>/native/ and GDScript in the nearby gdscript/ directory. Split large modules into feature subdirectories first (for example entities/player/gdscript/). Keep scenes/, resources/, assets/, and shaders/ with the owning feature; do not mix .cpp/.h files with GDScript or put native implementations in a global project-code bucket.
- Current world native features are game/world/native/generation/, persistence/, and streaming/. Native directories carry .gdignore. The build stages game/*/native into tmp and compiles an explicit current source manifest into the existing Voxel Tools GDExtension; never compile old staged sources by a broad fallback glob.
- Keep upstream Voxel Tools and godot-cpp sources under native/voxel_tools/ and native/deps/godot-cpp/. Upstream integration patches remain there; standalone project features belong in game/<module>/native/. Build outputs belong in tmp/ and deployed binaries in addons/zylann.voxel/bin/ (ignored by Git).
- data owns static authoring definitions; world owns authoritative voxel state, generation, streaming, meshing/collision and persistence; entities owns instance behavior and animation; shading owns rendering/environment effects; gameplay owns interaction and game rules; core assembles modules and ui presents them. Share static templates read-only, and do not create a second authoritative voxel mirror.
- The root test/ directory, alongside game/, is the target for ALL test-purpose content: test code, test scenes, demonstrations, benchmarks, fixtures, test-only assets/resources, runners and versioned reports. Group it by test name (test/world, test/native_world, test/entities, test/shading, etc.), separating native/ and gdscript/ when both are needed. Disposable logs, generated worlds, transient results and binaries still go to tmp/.
- Group test-purpose content under test/<test_name>/ (currently data, world, native_world, entities, shading). The old tests directory has been removed; do not recreate it or add path aliases. Historical measurement source paths remain evidence only.
- Preserve resource UID and import settings when moving files; update scene/script references, build source manifests, active documentation and tests together. Avoid speculative empty feature directories.

## Block appearance contract
- Authoring uses format-2 content projects indexing complete BlockAsset files (embedded logic, appearance and optional paired item), independent ItemAsset files and fluids. The builtin project is game/data/content/authoring/astraeon/pack.tres. Developer-selected source images are explicit absolute or project-relative filesystem indexes; offline tools may read them in place. Runtime only reads compiled .aebpack pixels. Do not put source Texture2D references or imported source images in production content. content_sources/ holds this repository's original art and is excluded from game exports.
- Follow docs/resource_specifications.md for the approved 1m x 1m x 1m block and material design. BlockAppearance, BlockSurface, and BlockLightAppearance are implemented shared authoring Resources owned by shading, read-only by consumer contract; native rendering consumes the current opaque/cutout albedo-textured and constant-emission block subset and water shading through the main-world assembly; normal/ORM/emission textures and blended block surfaces remain pending.
- Static logic definitions reference appearance resources. World/gameplay own instance coordinates, current orientation, and mining state; shading must not duplicate these authoritative states or mutate shared templates for per-instance changes.
- Keep surface emission independent from surrounding illumination. Block canonical axes are up +Y, front -Z, right +X; apply authoring correction before instance orientation, including faces, normals, and light offsets. This does not override character asset axes.
- Compile shared appearances for batched rendering; never create a Resource, Material, or light node per production voxel. Lighting schemes and budgets remain global rendering policy; visual transparency does not implicitly set logical light opacity or collision.

## Language boundaries and scenes
- Use C++ with Voxel Tools GDExtension as the approved production voxel backend; see docs/world/native_voxel_backend.md. Use GDScript for gameplay orchestration, UI, scene integration, and test drivers. In GDScript, never use :=; explicitly type variables, arguments, return values, signals, arrays, and dictionaries where supported.
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
- A chunk is a horizontal 16x16-voxel column; a section is 16x16x16 voxels. Use horizontal circular streaming with an independent vertical range. See docs/world/voxel_chunks.md for coordinates and boundary rules.
- Plan chunk coordinates and local voxel coordinates explicitly; include negative coordinates in future coordinate tests.
- Avoid one Node per voxel for production terrain. Choose chunk sizing, meshing, streaming, and threading based on a measured prototype.
- Background work must not mutate the active scene tree. Commit scene/resource changes on the main thread.
- Maintain versioned saves with seed, generation version, terrain edits and recoverable writes. Player entity state saving is not yet implemented.
- Keep world generation, mining/building, inventory, crafting, and survival responsibilities in their feature folders.
- Multiplayer is undecided. Do not create transport or authority layers until requested.

## Input, UI, and assets
- Keyboard and mouse are the initial input target; gameplay reads named InputMap actions.
- Add bindings with their actual feature, rather than shipping inactive controls.
- Maintain docs/input_mapping.md as the project-wide keyboard/mouse mapping reference. Update it with static InputMap bindings, runtime-registered actions, consumers and on-screen hints whenever bindings change; document scene/menu conditions and shared-key conflicts. Distinguish game actions, test-scene controls and editor shortcuts.
- **Project-local storage is mandatory:** project-authored code must never read or write application files through `user://`, AppData, or other OS user directories. Use `game/core/gdscript/project_paths.gd`; development data lives under this checkout, exported desktop data beside the executable. No fallback to old locations and no automatic old-format/path migration.
- External imports live in root `external_data/`: `characters/` for self-contained GLBs, `blocks/` for installed .aebpack content. Runtime state lives in root `runtime_data/`: `settings.cfg` for ConfigFile settings, `worlds/` for all save slots (including inventory and derived caches), and `logs/` for application logs. Test output stays in root `tmp/`.
- Keep `external_data/.gdignore` and `runtime_data/.gdignore`; imported/runtime files are read as filesystem data, never editor-imported assets. Ignore contents in Git except the directory scaffolding and guide. Preserve atomic/recoverable writes; report exact I/O errors without switching storage locations.
- ConfigFile defaults apply only when the project-local settings file is absent. Core paths are not based on the process working directory. User-selected runtime imports are copied to external_data before use. Offline content-authoring images are the explicit exception: the package project indexes developer-selected source files in place, and compilation embeds pixels into .aebpack.
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

## Documentation ownership and maintenance
- This root AGENTS.md is the project-wide authority for development and documentation rules, not a user-wide Codex configuration. Nested rules may add local constraints; skills and MCP hints must not establish conflicting project policy.
- README.md is a short startup and navigation entry. total_development.md owns concise overall progress, playable loops, module architecture and remaining boundaries. Do not append session diaries to either.
- docs/resource_specifications.md is the single resource authoring/delivery contract (units, block dimensions, axes, material/texture conventions, character skeleton/animation and import settings). Runtime algorithms and APIs belong to module documents.
- docs/<module>/README.md owns detailed progress, responsibilities, architecture/data flow, implementation entrypoints, limitations and evidence links. Modules are data, world, entities, shading, gameplay, core, ui; tooling owns development infrastructure. Split substantive topics only when needed. Code-folder READMEs link here instead of duplicating detailed state.
- Every module has docs/<module>/tmp/ for versioned research, algorithm investigations, alternatives, diagnoses and stage plans. These documents ARE committed to Git. Use YYYY-MM-DD_topic.md; record date, status, applicable version/code evidence, conclusions and links. Status: 研究中 / 待决策 / 已采纳 / 已否决 / 已过时. Accepted conclusions move into formal module/specification documents with an adoption link from the research; research never overrides current contracts.
- Versioned test evidence belongs to test/<test_name>/reports/. Root tmp/ remains ignored disposable output for logs, generated worlds and binaries. Do not confuse it with docs/<module>/tmp/. The existing benchmarks/voxelgame checkout is an explicit historical location exception; new test content belongs under test/.
- Change behavior and module docs together. Update total_development.md when a playable loop or architecture changes, resource_specifications.md when delivery contracts change, and rules/tooling docs when workflows change.
- Formal documents describe only current contracts. Preserve dates, original commands, measurements and source fingerprints in historical evidence; never recast historical passes as fresh validation. Move documents once and update links, anchors, skill references and active command descriptions; do not retain redirect stubs or duplicate contracts.
- Cold imports through tools/check.ps1 or the skill Import mode must pass the shared process preflight. A matching editor, ambiguous candidate or failed process query blocks only that import; do not add force bypasses, automatic elevation or process termination.
