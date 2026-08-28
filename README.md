# Plugin containers

Group bar widgets into named containers so the Omarchy bar stops filling up.

A container is one icon in the bar. Click it and the plugins inside it appear,
fully interactive — the same widgets, the same menus, the same settings, just
somewhere else. Nothing about a plugin changes when it goes into a container.

Claude code was heavily involved in the creation of this plugin.

![Plugin containers](preview.png)

## Requirements

Omarchy 4 with the Quickshell bar. Not tested with other QS bars such as Shibumi
or Lacuna — if you try one, let me know on the omarchy discord.

## Install

```bash
omarchy plugin add https://github.com/Leyanora/omarchy-plugin-containers.git --enable
```

Without `--enable`, place it yourself:

```bash
omarchy plugin enable leyanora.plugincontainers --section right
```

Update with `omarchy plugin update leyanora.plugincontainers`, then
`omarchy restart shell`.

## Using it

Click the box icon in the bar to open the manager.

- **New container** — name it and pick an icon. Only the icon goes in the bar,
  so pick a distinct one; the name is its tooltip. The grid offers thirty, and
  the field under it takes any glyph you paste.
- Select a container on the left, then fill it on the right: drag a plugin from
  the catalogue, or press its **+**. A plugin can be in several containers.
- The catalogue lists every installed plugin with a bar widget, switched on or
  not, plus your own custom qml bar modules. Command modules (the ones with an
  `exec`) are not listed: this plugin runs no commands.
- **>** moves a plugin to another container. **×** takes it out and puts it back
  on the bar where it was — nothing is uninstalled or disabled. Deleting a
  container does the same for everything it held.
- Reorder plugins by dragging them. Reorder containers with the up and down
  buttons, or by dragging their icons in the bar like any other widget.
- The bar is left alone until you close the manager, so an editing session costs
  one rearrangement rather than one per click. A new container's icon appears
  then too.

Right-click a container to open the manager; right-click the box to close
whatever is open.

### Two ways to open

By default a container opens into a strip below the bar. It can instead **expand
in the bar**, its plugins taking their own space where the icon sits and folding
back when you close it. Set the default in settings, or per container.

## Settings

The cog beside **CONTAINERS** opens the settings view. These apply to every
container.

| Option | What it does |
| --- | --- |
| Icons per row (1–10) | Where an open container wraps onto another row |
| Hide the container name | Drops the name pill; the bar tooltip still shows it |
| Expand containers in the bar | Open in place rather than into a strip |
| Open a container on hover | Opens on pointer-in, closes shortly after it leaves |
| Hide a container while it is empty | It gives its bar slot back until you fill it |
| Hide the plugin containers icon | Frees the box's slot without disabling anything |

Hiding the box leaves the plugin running and the containers working. Get back in
by right-clicking a container, or with
`omarchy shell leyanora.plugincontainers showIcon`. Both hiding options are
refused when they would leave nothing of this plugin in the bar to click.

**Per container:** the pencil on a container's row offers to take it off the
globals. It then decides its own icons per row, name pill and open mode;
everything else stays global.

## What it does to your bar

Containing a manifest plugin remembers its original `bar.layout` entry in
`~/.config/omarchy/shell.json` and replaces it with an invisible, zero-size
placeholder owned by the container. Omarchy therefore still considers the plugin
enabled, keeps its service, panel and overlay entry points loaded, and continues
to expose it to normal plugin-management tools. Keeping the safe settings on the
placeholder also supports services that read their configuration specifically
from `bar.layout`. Taking the plugin out removes only a placeholder created by
this plugin and writes the original entry back, including safe settings changed
while it was contained. Existing user-owned `plugins[]` entries are never claimed
or removed. An original `disabledPlugins` entry is temporarily suspended only
when necessary and restored on release. Executable entry keys (`source`, `type`,
`exec` and click handlers) cannot be introduced through settings written while a
plugin is contained. Custom QML modules have no manifest entry points, so they
need no placeholder.

Each container also gets a `bar.layout` entry of its own, so it is a bar module
like any other: its own slot, its own open-panel mark, and its own place you can
drag anywhere, including a different section from the box.

```json
{ "id": "leyanora.plugincontainers.c1",
  "source": "~/.config/omarchy/plugins/leyanora.plugincontainers/ContainerButton.qml" }
```

State lives inline on the plugin's own bar entry: `containers` (each with `id`,
`name`, `icon` and `members`), `stashed` (per plugin, the bar position and
settings it had before a container claimed it, plus optional ownership metadata
for temporary enablement), and `settings`. A container may carry a `settings`
object of its own holding `iconsPerRow`, `hideTitle` or `mode` (`"strip"` or
`"inline"`); a key it does not name is inherited. Editing by hand works — the
plugin reconciles whatever it finds.

## Uninstall

Current Omarchy does not provide plugins with a synchronous hook that runs before
their files and configuration entry are removed. Direct removal still triggers a
best-effort fallback while the shell notices the disappearing widget, but that
asynchronous path is not the deterministic cleanup procedure.

For a clean removal, keep the shell running and unlocked, then run these commands
in order:

```bash
omarchy shell leyanora.plugincontainers prepareUninstall
# The command above must print: ok

omarchy plugin remove leyanora.plugincontainers
```

Stop and do **not** run `omarchy plugin remove` if the first command prints
`failed`, is unavailable or does not print `ok`.

`prepareUninstall` performs one atomic `shell.json` write before any plugin file
is removed. It:

- restores the final copy of every contained plugin to its recorded bar section
  and index, carrying back safe settings changed while it was contained;
- removes every owned invisible `KeepAliveWidget.qml` placeholder;
- restores an original `disabledPlugins` entry only when this plugin had removed
  it, and leaves pre-existing user-owned `plugins[]` entries untouched;
- clears the container and stash records from the manager entry;
- removes only container slots whose ID belongs to
  `leyanora.plugincontainers.*` **and** whose exact source is this installation's
  `ContainerButton.qml`.

For an optional inspection before removal, the following command must print
`true`; the manager entry itself is expected to remain until the standard remove
command runs:

```bash
omarchy shell shell listShellConfig | jq -e '
  ([.bar.layout[][] |
    select((.id | startswith("leyanora.plugincontainers.")) or
           ((.source // "") | endswith("/leyanora.plugincontainers/KeepAliveWidget.qml")))] |
   length) == 0 and
  ([.bar.layout[][] |
    select(.id == "leyanora.plugincontainers") |
    select((.containers | length) == 0 and (.stashed | keys | length) == 0)] |
   length) == 1
'
```

`restoreAll` is different: it returns every member to the bar but deliberately
keeps the empty containers and their slots. It is not the pre-uninstall cleanup
command. A direct `omarchy plugin disable` also relies on the best-effort fallback.

## IPC

```bash
omarchy shell leyanora.plugincontainers manage              # open the manager
omarchy shell leyanora.plugincontainers openContainer NAME  # open one by name
omarchy shell leyanora.plugincontainers toggle
omarchy shell leyanora.plugincontainers close
omarchy shell leyanora.plugincontainers restoreAll          # empty every container
omarchy shell leyanora.plugincontainers prepareUninstall    # deterministic pre-remove cleanup
omarchy shell leyanora.plugincontainers refresh             # re-check against the bar
omarchy shell leyanora.plugincontainers showIcon            # or hideIcon
```

## What it touches

Writes only `~/.config/omarchy/shell.json`, through the shell's own atomic-write
helpers, and reads the qml file of a custom module it hosts — the same file the
bar itself would load. No other files, no commands, no subprocesses, no network
requests, nothing privileged.

Contained plugins are ordinary Omarchy plugins running unchanged — this plugin
does not sandbox them, and they keep whatever access they already had.

## License

MIT — see [LICENSE](LICENSE).
