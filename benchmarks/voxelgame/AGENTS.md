# Voxelgame benchmark boundary
- This is a separate Godot project under project/. Its res:// differs from Astraeon's main res://.
- Upstream files are vendored; preserve style and document compatibility fixes.
- Project-authored astraeon_benchmark/ code follows Astraeon's explicit typing rules.
- Voxel Tools v1.7x is an explicitly approved native dependency for this evaluation.
- During preparation do not run performance tests or gameplay smoke tests. Wait for a subsequent user instruction.
- Imports, dependency introspection, resource loading without instantiation, and check-only parsing are allowed.
- The default scene creates no terrain until Start or --run-benchmark. Do not add @tool terrain/viewer nodes.
- Never assume Astraeon's MCP client targets this nested project.
- Results go to tmp/voxel-bench-results or the dedicated user://. Never use an existing player save.
