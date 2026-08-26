# Changelog

## 1.0.0 — 2026-08-26

### Added

- **Settings view in the manager.** The cog beside `CONTAINERS` opens a second
  view holding the options that apply to every container.
- **Icons per row** (1–10). An open container wraps onto another row past this
  many plugins instead of growing one ever-wider strip.
- **Hide the container name.** Drops the name pill above an open container; the
  name still shows when you hover the container's icon in the bar.
- **Hide the plugin containers icon.** Frees the box's bar slot without
  disabling anything — the plugin keeps running, so containers still work. Get
  back in by right-clicking a container icon, or with the new
  `omarchy-shell leyanora.plugincontainers showIcon`. The option is refused
  while there are no containers, which would leave no way back but IPC.
- `hideIcon` / `showIcon` IPC verbs.

### Changed

- **Contained plugins go back to the bar automatically** when the plugin is
  removed or disabled. `omarchy plugin remove` disables the plugin first, while
  the shell is still running; each container's own bar entry outlives that and
  is what empties itself onto the bar. Best-effort — running `restoreAll` first
  still works and is still the certain path.
- Removing the plugin no longer leaves its containers' `bar.layout` entries
  behind pointing at deleted files.
- The plugin's `shell.json` entry gained a `settings` key alongside
  `containers` and `stashed`.
