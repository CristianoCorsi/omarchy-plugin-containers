import QtQuick
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs
import "Bridge.js" as Bridge

// One container's own bar slot, loaded by the hosted bar as a custom qml module.
// Not qs.Ui's BarWidget: this plugin has a BarWidget.qml of its own to be confused with.
Item {
  id: root

  // Injected by the bar into every module slot.
  property QtObject bar: null
  property string moduleName: ""

  readonly property bool vertical: bar ? bar.vertical : false

  // The bar hands a module a capability facade, so the plugin's own root — the catalogue,
  // the store, the bar object — is reachable only through the library the two share.
  property var host: Bridge.host()
  Component.onCompleted: if (!host) host = Bridge.host()

  readonly property var store: host ? host.containerStore : null

  // The entry id is `<manager module>.<container id>`; container ids never contain a dot.
  readonly property string ownerModule: {
    var at = moduleName.lastIndexOf(".")
    return at === -1 ? "" : moduleName.substring(0, at)
  }

  readonly property string containerId: {
    var at = moduleName.lastIndexOf(".")
    return at === -1 ? "" : moduleName.substring(at + 1)
  }

  readonly property var container: containerId === "" || !store
    ? null : store.containerById(containerId)

  readonly property var options: store ? store.effectiveSettings(root.containerId) : ({})

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
    if (host) host.summonBarWidget(root.ownerModule)
  }

  HostCoordinator {
    id: hostCoordinator
    bar: root.host ? root.host.inner : null
    inline: root.inline
  }

  readonly property bool hoverOpen: store ? store.settings.openOnHover === true : false

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
    onTriggered: if (root.hoverOpen && !root.pointerNear && !hostCoordinator.activePopout) root.close()
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
          label: root.store.pluginInfo(cell.modelData).name
          widgetComponent: root.store.componentFor(cell.modelData)
          source: root.store.entryUrlFor(cell.modelData)
          coordinator: hostCoordinator
          store: root.store
          hostSettings: root.store.settingsFor(cell.modelData)
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
    hostCoordinator.peers = out
  }

  ContainerStrip {
    id: strip
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.opened && !root.inline && !!root.container
    store: root.store
    container: root.container
    coordinator: hostCoordinator
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
}
