# Changelog

## 1.1.1

### Fixed

- Contained manifest plugins keep an invisible layout placeholder, so Omarchy
  still treats them as enabled and their service, panel and overlay entry points
  keep running.
- The placeholder mirrors safe widget settings for services such as Bambu
  Companion that read configuration specifically from `bar.layout`.
- Removing a plugin, deleting a container, restoring everything or running the
  manual pre-uninstall cleanup now removes only enablement state created by the
  container and restores an explicit disabled state that existed beforehand.
- Settings written by a service, panel or hosted widget while contained stay in
  sync and return to the restored bar entry without allowing executable
  bar-entry keys to be introduced.
- Existing 1.1.0 stashes are upgraded automatically during reconciliation.
- Added `prepareUninstall`, a deterministic manual cleanup command to run before
  `omarchy plugin remove`. Direct removal remains best-effort because current
  Omarchy has no synchronous pre-remove hook for plugins.

## 1.1.0

The release for having more than one container: moving plugins between them,
ordering them from the manager, and letting each one look and open its own way.

### Added

- **Move a plugin between containers** with **>** on its row. One write, so it
  never touches the bar in between and keeps the position it would go back to.
- **Reorder containers from the manager** with the up and down buttons, writing
  the bar order that has always been the source of truth. Dragging the icons in
  the bar still works and still wins.
- **Any glyph as a container icon**, from the field under the icon grid.
- **Per-container settings.** A container can be taken off the globals and then
  wraps, labels and opens itself its own way.
- **Expand in the bar.** A container opens in place instead of dropping a strip,
  with the open mark drawn across the whole group. Global default, or per
  container.
- **Open a container on hover.** It closes shortly after the pointer leaves,
  unless something opened from inside it is still up.
- **Hide a container while it is empty.** Refused, like hiding the box, when it
  would leave nothing of this plugin in the bar to get back through.
- **Custom qml bar modules can be contained.** Their definition lives only in
  their `bar.layout` entry, so a container holds on to it and writes it back
  untouched.
- A write that does not land now says so in the manager instead of failing
  silently.
- An open container that outgrows the screen scrolls instead of losing its last
  row off the edge.

### Changed

- **A contained plugin can no longer put a command in its own bar entry.** A
  settings write from a hosted widget was already refused `source`, which the bar
  loads as QML; it is now refused `type`, `exec` and the `onClick` /
  `onRightClick` / `onMiddleClick` commands as well, all of which the bar acts on
  once the entry goes back. Entries that already carry them keep them.

## 1.0.0

The first release with settings of its own, and the first that cleans up after
itself.

### Added

- **Settings view in the manager**, behind the cog beside `CONTAINERS`.
- **Icons per row** (1–10), where an open container wraps onto another row.
- **Hide the container name.** The bar tooltip still shows it.
- **Hide the plugin containers icon.** Frees the box's bar slot without disabling
  anything — the plugin keeps running, so containers still work. Get back in by
  right-clicking a container icon or with the new `showIcon`. Refused while there
  are no containers, which would leave no way back but IPC.
- `hideIcon` / `showIcon` IPC verbs.

### Changed

- **Contained plugins go back to the bar automatically** when the plugin is
  removed or disabled: each container's own bar entry outlives the disable and
  empties itself onto the bar. Best-effort — `restoreAll` first is still the
  certain path.
- Removing the plugin no longer leaves its containers' `bar.layout` entries
  behind pointing at deleted files.
- The plugin's `shell.json` entry gained a `settings` key alongside `containers`
  and `stashed`.
