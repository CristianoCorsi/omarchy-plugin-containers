import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// Groups bar widgets behind one button each; this root owns view state only.
BarWidget {
  id: root
  moduleName: "leyanora.plugincontainers"

  // Mutually exclusive with the manager: two panels on neighbouring buttons would overlap.
  property string openContainerId: ""
  property bool manageOpen: false

  // Bar.findPanelWidget requires opened/open/close on the bar-widget root.
  readonly property bool opened: manageOpen || openContainerId !== ""
  readonly property var container: openContainerId !== "" ? store.containerById(openContainerId) : null

  // True while any instance of this widget owns the bar's single popout token.
  readonly property bool surfaceOpenAnywhere: !!bar && !!bar.activePopout
    && bar.activePopout.moduleName === root.moduleName

  // The instance a summon should land on. Opening on every screen makes the
  // second one evict the first through the bar's shared popout coordinator.
  function firstInstance() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    return items.length > 0 ? items[0] : root
  }

  function openManager() {
    openContainerId = ""
    manageOpen = true
  }

  function openContainer(containerId) {
    if (!store.containerById(containerId)) return
    manageOpen = false
    openContainerId = containerId
  }

  function openContainerNamed(name) {
    var wanted = String(name || "").trim().toLowerCase()
    for (var i = 0; i < store.containers.length; i++) {
      if (store.containers[i].name.toLowerCase() === wanted) {
        openContainer(store.containers[i].id)
        return true
      }
    }
    return false
  }

  function toggleContainer(containerId) {
    if (openContainerId === containerId) close()
    else openContainer(containerId)
  }

  function toggleManager() {
    if (manageOpen) close()
    else openManager()
  }

  // close() is also how the bar's popout coordinator evicts this widget.
  function open() { openManager() }
  function close() {
    manageOpen = false
    openContainerId = ""
  }
  function togglePanel() {
    if (opened) close()
    else openManager()
  }
  function restoreAll() { store.restoreAll() }
  function refresh() { store.reconcile() }

  // No `entry: root.settings`: Store reads the shell's live config instead.
  Store {
    id: store
    moduleName: root.moduleName
    shell: root.bar ? root.bar.shell : null
    // Shared across monitors, not `root.manageOpen`: one Bar object serves every
    // screen, so the other screen's instance would still reconcile and rebuild.
    deferLayout: root.surfaceOpenAnywhere
  }

  // One proxy pair per instance, shared by whichever strip is open.
  HostBar {
    id: hostBar
    bar: root.bar
    shell: root.bar ? root.bar.shell : null
  }

  HostShell {
    id: hostShell
    shell: root.bar ? root.bar.shell : null
    store: store
  }

  // The registry rescans on inotify, so plugins can appear or vanish at any moment.
  Connections {
    target: store.registry
    function onPluginsChanged() {
      store.catalogueRevision++
      store.scheduleReconcile()
    }
  }

  Component.onCompleted: store.scheduleReconcile()

  // The open container can be deleted or pruned while its strip is showing.
  Connections {
    target: store
    function onPersisted(next) {
      Qt.callLater(function () {
        if (root.openContainerId !== "" && !store.containerById(root.openContainerId)) root.close()
      })
    }
  }

  implicitWidth: buttons.implicitWidth
  implicitHeight: buttons.implicitHeight

  // One item tree that reflows, so the two orientations cannot drift apart.
  GridLayout {
    id: buttons
    anchors.fill: parent
    columns: root.vertical ? 1 : 1 + store.containerCount
    columnSpacing: 0
    rowSpacing: 0

    // No tint when open: the bar already draws an open-panel indicator for the slot.
    BarIconButton {
      id: boxButton
      bar: root.bar
      text: Glyphs.app
      tooltipText: store.containerCount === 0
        ? "Plugin containers — create one to group bar widgets"
        : "Plugin containers — manage"
      onPressed: function (mouseButton) {
        if (mouseButton === Qt.RightButton) root.close()
        else root.toggleManager()
      }
    }

    Repeater {
      id: containerButtons
      model: store.containers

      // Icon only, so a container costs one bar slot however long its name is.
      delegate: BarIconButton {
        required property var modelData

        bar: root.bar
        text: modelData.icon || Glyphs.container
        textRotation: root.vertical ? 90 : 0
        tooltipText: modelData.name
        onPressed: function (mouseButton) {
          if (mouseButton === Qt.RightButton) root.openManager()
          else root.toggleContainer(modelData.id)
        }
      }
    }
  }

  // Repeater.itemAt is a function, not a bindable property, so this is recomputed.
  property Item stripAnchor: boxButton

  function refreshAnchor() {
    var target = null
    if (openContainerId !== "") {
      for (var i = 0; i < store.containers.length; i++) {
        if (store.containers[i].id === openContainerId) {
          target = containerButtons.itemAt(i)
          break
        }
      }
    }
    stripAnchor = target || boxButton
  }

  onOpenContainerIdChanged: refreshAnchor()

  Connections {
    target: containerButtons
    function onCountChanged() { Qt.callLater(root.refreshAnchor) }
  }

  // Both take `owner: root`, so the coordinator evicts the pair and close() clears both.

  ContainerStrip {
    anchorItem: root.stripAnchor
    bar: root.bar
    owner: root
    open: !!root.container
    store: store
    container: root.container
    hostBar: hostBar
  }

  ManagePanel {
    anchorItem: boxButton
    bar: root.bar
    owner: root
    open: root.manageOpen
    store: store
  }

  IpcHandler {
    target: "leyanora.plugincontainers"

    function open(): void { root.firstInstance().openManager() }
    function close(): void { root.broadcast("close") }
    function show(): void { root.firstInstance().openManager() }
    function hide(): void { root.broadcast("close") }
    function toggle(): void { root.firstInstance().togglePanel() }
    function manage(): void { root.firstInstance().openManager() }
    function refresh(): void { root.firstInstance().refresh() }

    // Run before uninstalling: removing the plugin deletes the record of where each goes.
    function restoreAll(): void { root.firstInstance().restoreAll() }

    function openContainer(name: string): void { root.firstInstance().openContainerNamed(name) }
  }
}
