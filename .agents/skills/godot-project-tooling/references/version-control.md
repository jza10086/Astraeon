# Godot version-control guidance

Read this reference when auditing, creating, or changing Godot version-control metadata. Check the documentation for the selected engine version if the project uses Godot 4.0 or Godot 3.x; their generated files and credential rules differ from Godot 4.1 and later.

## Godot 4.1 and later

- Ignore `.godot/`, which contains generated project cache data.
- Ignore `*.translation`, which contains binary translations imported from CSV files.
- Commit source assets, scenes, scripts, resources, `project.godot`, and `export_presets.cfg` unless the project has a specific reason not to.
- Do not commit `.godot/export_credentials.cfg`; it can contain passwords or encryption keys and is already covered by `.godot/`.
- Commit generated `.uid` files. Do not add `*.uid` to `.gitignore`; stable resource references can break on other machines when UID files are missing.
- Use `.gitattributes` to normalize text files to LF, especially for Git for Windows.

Official sources:

- https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html
- https://godotengine.org/article/uid-changes-coming-to-godot-4-4/

## Editing behavior

Run `scripts/audit_godot_vcs.ps1` first. Treat its output as findings, not authorization to edit. When the user requests initialization or repair:

1. Inspect existing `.gitignore` and `.gitattributes` files.
2. Merge only missing rules from the matching asset template.
3. Preserve comments, project-specific patterns, and unrelated rules.
4. Show the focused diff.
5. Rerun the audit.

Do not automatically remove tracked generated files, credentials, or ignore rules. Explain the finding and obtain an explicit request before destructive cleanup.

## `.gdignore` is different

An empty `.gdignore` tells Godot not to scan a directory. Its contents are ignored and it does not support `.gitignore` patterns. Files below that directory disappear from Godot's FileSystem dock and cannot be loaded with `load()` or `preload()`. Create it only when the user wants to exclude a directory from Godot import scanning.
