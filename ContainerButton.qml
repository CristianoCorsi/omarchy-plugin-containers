import QtQuick
import qs.Ui
import "Glyphs.js" as Glyphs

// One container's own bar slot, loaded by path as a custom bar module: a plugin manifest
// can name a single barWidget, so this is the only way a container gets a slot of its own.
// Not qs.Ui's BarWidget: this plugin has a BarWidget.qml of its own to be confused with.
Item {
  id: root

  // Injected by the bar into every module slot.
  property QtObject bar: null
  property string moduleName: ""

  readonly property bool vertical: bar ? bar.vertical : false

  // The entry id is `<manager module>.<container id>`; container ids never contain a dot.
  readonly property string ownerModule: {
    var at = moduleName.lastIndexOf(".")
    return at === -1 ? "" : moduleName.substring(0, at)
  }

  readonly property string containerId: {
    var at = moduleName.lastIndexOf(".")
    return at === -1 ? "" : moduleName.substring(at + 1)
  }

  readonly property var container: containerId === "" ? null : store.containerById(containerId)

  // Bar.findPanelWidget requires opened/open/close on the widget root.
  property bool opened: false

  function open() { if (root.container) root.opened = true }
  function close() { root.opened = false }
  function togglePanel() {
    if (root.opened) root.close()
    else root.open()
  }

  function openManager() {
    if (bar && typeof bar.summonBarWidget === "function") bar.summonBarWidget(root.ownerModule)
  }

  // Reads the manager's state; the manager's own instance is the only one that writes the bar.
  Store {
    id: store
    moduleName: root.ownerModule
    shell: root.bar ? root.bar.shell : null
    passive: true
  }

  HostShell {
    id: hostShell
    shell: root.bar ? root.bar.shell : null
    store: store
    members: root.container ? root.container.members : []
  }

  // The proxy shell, not the real one: updateEntryInline cannot reach a stashed plugin.
  HostBar {
    id: hostBar
    bar: root.bar
    shell: hostShell
  }

  // The registry rescans on inotify, so a hosted plugin's entry point can move under us.
  Connections {
    target: store.registry
    function onPluginsChanged() { store.catalogueRevision++ }
  }

  // A slot the manager has not pruned yet: the bar gives an invisible module no width.
  visible: !!root.container
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    bar: root.bar
    text: root.container ? (root.container.icon || Glyphs.container) : ""
    textRotation: root.vertical ? 90 : 0
    tooltipText: root.container ? root.container.name : ""
    onPressed: function (mouseButton) {
      if (mouseButton === Qt.RightButton) root.openManager()
      else root.togglePanel()
    }
  }

  ContainerStrip {
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened && !!root.container
    store: store
    container: root.container
    hostBar: hostBar
  }

  // The manager can delete the container while its strip is showing.
  onContainerChanged: if (!container) close()

  // Disabling the plugin deletes the entry holding the stash, and takes the manager's
  // widget with it. This slot is loaded by path, so it is still running afterwards and is
  // what hands the contained plugins back. Deferred, or the write that orphaned us is still
  // on the stack and the one finishing it overwrites ours; but barely, because
  // `omarchy plugin remove` deletes the folder out from under us right after. A false
  // positive is safe: reconcile re-stashes and re-adds the slots on the next pass.
  readonly property bool orphaned: store.ready && !store.inLayout

  onOrphanedChanged: if (orphaned) orphanTimer.restart()

  // Retried rather than timed: the first tick has to beat `rm`, but a config reload can
  // leave the state unsettled for longer than that. A successful release drops this very
  // slot, so the repeat ends by taking us with it.
  Timer {
    id: orphanTimer
    interval: 120
    repeat: true
    property int tries: 0
    onTriggered: {
      orphanTimer.tries++
      if (root.orphaned) store.releaseAll()
      if (!root.orphaned || orphanTimer.tries >= 8) {
        orphanTimer.tries = 0
        orphanTimer.stop()
      }
    }
  }
}
