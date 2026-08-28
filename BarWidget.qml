import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// The manager's bar button. Each container draws its own slot from ContainerButton.qml;
// this root owns the state every one of them reads, plus the manager's view state.
BarWidget {
  id: root
  moduleName: "leyanora.plugincontainers"

  property bool manageOpen: false

  // Bar.findPanelWidget requires opened/open/close on the bar-widget root.
  readonly property bool opened: manageOpen

  // True while the manager or any container's strip owns the bar's single popout token.
  readonly property bool surfaceOpenAnywhere: {
    if (!bar || !bar.activePopout) return false
    var name = String(bar.activePopout.moduleName || "")
    return name === root.moduleName || name.indexOf(root.moduleName + ".") === 0
  }

  // The instance a summon should land on. Opening on every screen makes the
  // second one evict the first through the bar's shared popout coordinator.
  function firstInstance() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    return items.length > 0 ? items[0] : root
  }

  function openManager() { manageOpen = true }

  function toggleManager() {
    if (manageOpen) close()
    else openManager()
  }

  function openContainerNamed(name) {
    var wanted = String(name || "").trim().toLowerCase()
    for (var i = 0; i < store.containers.length; i++) {
      if (store.containers[i].name.toLowerCase() !== wanted) continue
      if (!bar || typeof bar.summonBarWidget !== "function") return false
      return bar.summonBarWidget(store.slotIdFor(store.containers[i].id)) === true
    }
    return false
  }

  // Every strip is a slot of its own now, so closing them all means visiting each one.
  function closeAll() {
    root.broadcast("close")
    if (!bar || typeof bar.moduleWidgets !== "function") return
    for (var i = 0; i < store.containers.length; i++) {
      var items = bar.moduleWidgets(store.slotIdFor(store.containers[i].id))
      for (var j = 0; j < items.length; j++) {
        if (items[j] && typeof items[j].close === "function") items[j].close()
      }
    }
  }

  // close() is also how the bar's popout coordinator evicts this widget.
  function open() { openManager() }
  function close() { manageOpen = false }
  function togglePanel() {
    if (opened) close()
    else openManager()
  }
  function restoreAll() { store.restoreAll() }
  function prepareUninstall() { return store.prepareUninstall() }
  function refresh() { store.reconcile() }
  function setIconHidden(hidden) { store.setSetting("hideBarIcon", hidden === true) }

  // No `entry: root.settings`: Store reads the shell's live config instead.
  Store {
    id: store
    moduleName: root.moduleName
    shell: root.bar ? root.bar.shell : null
    // Shared across monitors, not `root.manageOpen`: one Bar object serves every
    // screen, so the other screen's instance would still reconcile and rebuild.
    deferLayout: root.surfaceOpenAnywhere
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

  // The bar gives an invisible module no width, which is the whole trick: the widget, its
  // Store and its IpcHandler keep running, so the containers still reconcile without it.
  readonly property bool iconHidden: store.settings.hideBarIcon

  visible: !iconHidden
  implicitWidth: iconHidden ? 0 : boxButton.implicitWidth
  implicitHeight: iconHidden ? 0 : boxButton.implicitHeight

  // No tint when open: the bar already draws an open-panel indicator for the slot.
  BarIconButton {
    id: boxButton
    bar: root.bar
    text: Glyphs.app
    tooltipText: store.containerCount === 0
      ? "Plugin containers — group bar widgets"
      : "Plugin containers — manage"
    onPressed: function (mouseButton) {
      if (mouseButton === Qt.RightButton) root.closeAll()
      else root.toggleManager()
    }
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
    function close(): void { root.firstInstance().closeAll() }
    function show(): void { root.firstInstance().openManager() }
    function hide(): void { root.firstInstance().closeAll() }
    function toggle(): void { root.firstInstance().togglePanel() }
    function manage(): void { root.firstInstance().openManager() }
    function refresh(): void { root.firstInstance().refresh() }

    // The way back when the box is hidden and there is no container left to right-click.
    function showIcon(): void { root.firstInstance().setIconHidden(false) }
    function hideIcon(): void { root.firstInstance().setIconHidden(true) }

    // Empty containers while retaining their definitions and bar slots.
    function restoreAll(): void { root.firstInstance().restoreAll() }

    // Required deterministic cleanup before the standard Omarchy remove command.
    function prepareUninstall(): string {
      return root.firstInstance().prepareUninstall() ? "ok" : "failed"
    }

    function openContainer(name: string): void { root.firstInstance().openContainerNamed(name) }
  }
}
