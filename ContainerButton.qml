import QtQuick
import qs.Commons
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

  readonly property var options: store.effectiveSettings(root.containerId)

  // Inline containers open into their own bar slot; the strip is not built for them at all.
  readonly property bool inline: options.mode === "inline"
  readonly property bool expanded: root.opened && root.inline && !!root.container
  readonly property var members: root.container ? root.container.members : []

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
    id: hostProxy
    bar: root.bar
    shell: hostShell
    inline: root.inline
  }

  // The registry rescans on inotify, so a hosted plugin's entry point can move under us.
  Connections {
    target: store.registry
    function onPluginsChanged() { store.catalogueRevision++ }
  }

  readonly property bool hoverOpen: store.settings.openOnHover === true

  // Neither the button nor the card: crossing the gap between them leaves both false,
  // which is what the close grace is for.
  readonly property bool pointerNear: buttonHover.hovered || strip.cardHovered

  // A click that closes the container must not be undone by the pointer still resting on it.
  property bool hoverSuppressed: false

  HoverHandler {
    id: buttonHover
  }

  Timer {
    id: hoverOpenTimer
    interval: 180
    onTriggered: if (root.hoverOpen && root.pointerNear && !root.hoverSuppressed) root.open()
  }

  Timer {
    id: hoverCloseTimer
    interval: 300
    // A popup opened from inside the container keeps it open: the pointer is on that popup.
    onTriggered: if (root.hoverOpen && !root.pointerNear && !hostProxy.activePopout) root.close()
  }

  onPointerNearChanged: {
    if (!root.hoverOpen) return
    if (root.pointerNear) {
      hoverCloseTimer.stop()
      if (!root.opened) hoverOpenTimer.restart()
    } else {
      hoverSuppressed = false
      hoverOpenTimer.stop()
      hoverCloseTimer.restart()
    }
  }

  // A slot the manager has not pruned yet: the bar gives an invisible module no width.
  // An empty container can be hidden too, and then it is the manager that brings it back.
  visible: !!root.container
    && (store.settings.hideEmpty !== true || root.container.members.length > 0)
  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  // The bar centres this mark on the slot and exposes no offset for it, so it spans the
  // whole expanded container rather than landing under whichever cell sits in the middle.
  readonly property real openPanelIndicatorWidth: layout.width
  readonly property real openPanelIndicatorHeight: layout.height

  // A Grid rather than a Row: on a vertical bar the slot's width is pinned to the bar's,
  // so an expanded container there can only grow downwards.
  Grid {
    id: layout
    rows: root.vertical ? (root.expanded ? root.members.length + 1 : 1) : 1
    columns: root.vertical ? 1 : (root.expanded ? root.members.length + 1 : 1)
    spacing: root.expanded ? Style.spacing.xs : 0
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter

    BarIconButton {
      id: button
      bar: root.bar
      text: root.container ? (root.container.icon || Glyphs.container) : ""
      textRotation: root.vertical ? 90 : 0
      tooltipText: root.container ? root.container.name : ""
      onPressed: function (mouseButton) {
        if (mouseButton === Qt.RightButton) root.openManager()
        else {
          root.hoverSuppressed = root.opened
          root.togglePanel()
        }
      }
    }

    Repeater {
      id: cells
      // Kept loaded while the container is collapsed, as the strip keeps its own: a hosted
      // plugin that is torn down every time loses whatever it was tracking.
      model: root.inline ? root.members : []

      delegate: Item {
        id: cell
        required property var modelData

        readonly property var widget: hosted.widget

        // A Grid skips an invisible child, so this is also what collapses the slot again.
        visible: root.expanded
        implicitWidth: visible ? hosted.implicitWidth : 0
        implicitHeight: visible ? hosted.implicitHeight : 0

        HostedWidget {
          id: hosted
          anchors.centerIn: parent
          inline: true
          pluginId: cell.modelData
          label: store.pluginInfo(cell.modelData).name
          source: store.entryUrlFor(cell.modelData)
          hostBar: hostProxy
          hostSettings: store.settingsFor(cell.modelData)
          foreground: root.bar ? root.bar.foreground : Color.foreground
          barPosition: root.bar ? root.bar.position : "top"
          onWidgetChanged: Qt.callLater(root.collectPeers)
        }

        // The bar routes a left click through its own registry, which cannot see a hosted
        // button's target: this is what it finds in its place. Left only — the bar's own
        // area takes no other button, so those reach the widget directly.
        Item {
          id: clickProxy
          anchors.fill: parent

          function triggerPress(button) { hosted.press(button) }

          Component.onCompleted: if (root.bar && typeof root.bar.registerClickTarget === "function")
            root.bar.registerClickTarget(clickProxy)

          Component.onDestruction: if (root.bar && typeof root.bar.unregisterClickTarget === "function")
            root.bar.unregisterClickTarget(clickProxy)
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.RightButton | Qt.MiddleButton
          onClicked: function (mouse) { hosted.press(mouse.button) }
        }
      }
    }
  }

  // Hosted instances, so a plugin's broadcast() reaches its peers here and not an empty bar.
  function collectPeers() {
    if (!root.inline) return
    var out = []
    for (var i = 0; i < cells.count; i++) {
      var cell = cells.itemAt(i)
      if (cell && cell.widget) out.push(cell.widget)
    }
    hostProxy.peers = out
  }

  ContainerStrip {
    id: strip
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened && !root.inline && !!root.container
    store: store
    container: root.container
    hostBar: hostProxy
  }

  // The strip claims the bar's popout token when it opens; expanded in place there is no
  // strip to do it, and without it the bar draws no open mark, evicts nothing, and lets a
  // reconcile rebuild the slot from under the widgets.
  onExpandedChanged: {
    if (!bar) return
    if (expanded) bar.requestPopout(root)
    else if (bar.activePopout === root) bar.releasePopout(root)
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
      if (root.orphaned) store.releaseAll(root.moduleName)
      if (!root.orphaned || orphanTimer.tries >= 8) {
        orphanTimer.tries = 0
        orphanTimer.stop()
      }
    }
  }
}
