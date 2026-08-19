import QtQuick
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// One plugin in an open container, built from its manifest rather than the registry.
Item {
  id: root

  required property string pluginId
  required property string label
  required property url source
  required property var hostBar
  required property var hostSettings
  property color foreground: Color.popups.text

  readonly property var widget: loader.item
  readonly property bool failed: loader.status === Loader.Error || String(root.source) === ""

  // Activate the plugin for a click on the caption or padding, where it has no handler.
  function press(button) {
    var target = primaryTarget()
    if (target) {
      target.triggerPress(button)
      return true
    }

    // A plugin using a bare MouseArea registers no target; fall back, most specific first.
    var item = loader.item
    if (!item) return false
    if (typeof item.togglePanel === "function") { item.togglePanel(); return true }
    if (typeof item.toggle === "function") { item.toggle(); return true }
    // The shell's summon contract: `opened` says which way to go.
    if (typeof item.opened === "boolean"
        && typeof item.open === "function" && typeof item.close === "function") {
      if (item.opened) item.close()
      else item.open()
      return true
    }
    // Not a contract, but what widgets name the flag their own button toggles.
    if (typeof item.popupOpen === "boolean") { item.popupOpen = !item.popupOpen; return true }
    return false
  }

  // The cell only offers a pointer cursor for a click it can actually route.
  readonly property bool routable: {
    var item = loader.item
    if (!item) return false
    if (primaryTarget()) return true
    if (typeof item.togglePanel === "function") return true
    if (typeof item.toggle === "function") return true
    if (typeof item.opened === "boolean"
        && typeof item.open === "function" && typeof item.close === "function") return true
    return typeof item.popupOpen === "boolean"
  }

  function ownsItem(item) {
    var node = item
    while (node) {
      if (node === loader.item) return true
      node = node.parent
    }
    return false
  }

  function primaryTarget() {
    var item = loader.item
    if (!item || !root.hostBar) return null
    var targets = root.hostBar.clickTargets || []
    var centre = item.width / 2
    var best = null
    var bestDistance = Infinity
    for (var i = 0; i < targets.length; i++) {
      var target = targets[i]
      if (!target || typeof target.triggerPress !== "function") continue
      if (target.visible === false || target.opacity === 0) continue
      if (!ownsItem(target)) continue
      var mapped = target.mapToItem(item, target.width / 2, target.height / 2)
      var distance = Math.abs(mapped.x - centre)
      if (distance < bestDistance) {
        bestDistance = distance
        best = target
      }
    }
    return best
  }

  implicitWidth: Math.max(column.implicitWidth, Style.space(48))
  implicitHeight: column.implicitHeight

  Column {
    id: column
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.spacing.xs

    // Reserves the bar's slot height so a widget sized off barSize is not squeezed.
    Item {
      id: slot
      width: Math.max(loader.implicitWidth, Style.bar.iconSlot)
      height: Style.bar.sizeHorizontal
      anchors.horizontalCenter: parent.horizontalCenter

      Loader {
        id: loader
        anchors.centerIn: parent
        // Synchronous: async would resize the strip under the cursor as each widget lands.
        asynchronous: false
        source: root.source
        onLoaded: {
          injectProps()
          // Twice, as the bar does: a root binding against `bar` reads it before the assignment.
          Qt.callLater(injectProps)
        }

        function injectProps() {
          var target = loader.item
          if (!target) return
          if ("bar" in target) target.bar = root.hostBar
          if ("moduleName" in target) target.moduleName = root.pluginId
          if ("settings" in target) target.settings = root.hostSettings
        }
      }

      // Keep a live widget in step with settings written while it is open.
      Connections {
        target: root
        function onHostSettingsChanged() { loader.injectProps() }
      }

      Text {
        anchors.centerIn: parent
        visible: root.failed
        text: Glyphs.warn
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.icon
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(implicitWidth, Style.space(120))
      text: root.failed ? "failed to load" : root.label
      // Plugin display names are third-party strings; AutoText would parse markup in them.
      textFormat: Text.PlainText
      color: root.failed ? Color.urgent : Qt.darker(root.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }
}
