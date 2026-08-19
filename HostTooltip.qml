import QtQuick
import Quickshell
import qs.Commons

// The bar only paints tooltips for its own windows, so the strip hosts its own.
PopupWindow {
  id: root

  required property Item anchorItem
  property color foreground: Color.tooltip.text
  property string fontFamily: Style.font.family

  property var target: null
  property string label: ""
  property bool shown: false

  readonly property var borderSpec: Border.localOrSurfaceSpec(
    "tooltip", "border", Color.tooltip.border, Color.tooltip.border, Math.max(1, Style.space(1)))

  // A widget hidden or destroyed under the cursor must not strand its tooltip.
  function stillHovered() {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function show(item, text) {
    clear()
    if (!item || !text) return
    target = item
    label = String(text)
    delayTimer.restart()
  }

  function hide(item) {
    if (target !== item) return
    clear()
  }

  function clear() {
    delayTimer.stop()
    shown = false
    target = null
    label = ""
  }

  Timer {
    id: delayTimer
    interval: 400
    onTriggered: root.shown = root.stillHovered()
  }

  // The pointer can leave without the widget saying so, so poll while shown.
  Timer {
    interval: 100
    repeat: true
    running: root.shown
    onTriggered: if (!root.stillHovered()) root.clear()
  }

  visible: shown && label !== "" && !!target
  color: "transparent"
  implicitWidth: content.implicitWidth
  implicitHeight: content.implicitHeight

  anchor {
    id: tooltipAnchor
    window: root.anchorItem ? root.anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      var item = root.target
      var window = root.anchorItem ? root.anchorItem.QsWindow.window : null
      if (!item || !window) return
      var point = window.contentItem.mapFromItem(item, item.width / 2 - root.implicitWidth / 2, item.height + Style.gapsOut)
      point.x = Math.max(Style.gapsOut, Math.min(point.x, window.width - root.implicitWidth - Style.gapsOut))
      tooltipAnchor.rect.x = Math.round(point.x)
      tooltipAnchor.rect.y = Math.round(point.y)
    }
  }

  Rectangle {
    id: content
    anchors.fill: parent
    color: Color.tooltip.background
    radius: Style.cornerRadius
    border.color: Border.canUseNative(root.borderSpec) ? Border.color(root.borderSpec) : "transparent"
    border.width: Border.canUseNative(root.borderSpec) ? Border.uniformWidth(root.borderSpec) : 0
    implicitWidth: text.implicitWidth + Style.spacing.controlPaddingX * 2
    implicitHeight: text.implicitHeight + Style.spacing.controlPaddingY * 2

    Text {
      id: text
      anchors.centerIn: parent
      text: root.label
      // Tooltip text is third-party; AutoText would parse any markup in it.
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
