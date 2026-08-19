import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// An open container: its plugins in a row, on a layer surface shaped like the bar.
PanelWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  required property var store
  required property var container
  required property var hostBar
  property var owner: null
  property bool open: false

  property int margin: Style.gapsOut
  property int gap: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  readonly property color foreground: Color.popups.text
  readonly property var members: container ? container.members : []
  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPos: bar ? bar.position : "top"

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  // Hosted instances, so a plugin's broadcast() reaches its peers here, not an empty bar.
  function collectPeers() {
    var out = []
    for (var i = 0; i < repeater.count; i++) {
      var cell = repeater.itemAt(i)
      if (cell && cell.widget) out.push(cell.widget)
    }
    root.hostBar.peers = out
  }

  // Shaped like a second bar row: full width along the bar's axis, card-thick across it.

  readonly property bool horizontalBar: barPos === "top" || barPos === "bottom"
  readonly property real barThickness: horizontalBar ? barH : barW
  readonly property real barOffset: barThickness + gap

  screen: anchorWindow ? anchorWindow.screen : null
  visible: open || card.opacity > 0
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "leyanora-plugincontainers-strip"
  WlrLayershell.layer: WlrLayer.Overlay
  // No keyboard focus: hosted popups that want keys still take their own.
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // Starts at the screen edge: a hosted KeyboardPanel opens one window-thickness past it.
  anchors {
    top: root.horizontalBar ? root.barPos === "top" : true
    bottom: root.horizontalBar ? root.barPos === "bottom" : true
    left: root.horizontalBar ? true : root.barPos === "left"
    right: root.horizontalBar ? true : root.barPos === "right"
  }

  implicitWidth: root.horizontalBar ? root.contentWidth : root.barOffset + root.contentWidth
  implicitHeight: root.horizontalBar ? root.barOffset + root.contentHeight : root.contentHeight

  // Only the card takes input; the bar stays clickable underneath.
  mask: Region {
    x: root.horizontalBar ? root.cardAlong : root.cardPerp
    y: root.horizontalBar ? root.cardPerp : root.cardAlong
    width: root.contentWidth
    height: root.contentHeight
  }

  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0
  readonly property real barW: anchorWindow ? anchorWindow.width : screenW
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real anchorW: anchorItem ? anchorItem.width : 0
  readonly property real anchorH: anchorItem ? anchorItem.height : 0

  // mapToItem is a one-shot; the watcher keeps the position binding live.
  TransformWatcher {
    id: anchorWatcher
    a: root.anchorWindow ? root.anchorWindow.contentItem : null
    b: root.anchorItem
  }

  readonly property point anchorScreenPos: {
    anchorWatcher.transform  // reactive dependency
    if (!anchorItem || !anchorWindow) return Qt.point(0, 0)
    return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
  }

  readonly property real availableWidth: screenW > 0
    ? Math.max(120, screenW - (horizontalBar ? margin * 2 : barOffset + margin))
    : 0
  readonly property real availableHeight: screenH > 0
    ? Math.max(120, screenH - (horizontalBar ? barOffset + margin : margin * 2))
    : 0

  readonly property real contentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  // From the widget row, never the column: the column's width comes from the card.
  readonly property int contentWidth: Math.round(Math.min(
    Math.max(strip.implicitWidth, Style.space(260)) + padding * 2, availableWidth))
  readonly property int contentHeight: Math.round(Math.min(
    layout.implicitHeight + contentInset, availableHeight))

  // The card has to clear the bar the surface covers.
  readonly property int cardPerp: barPos === "top" || barPos === "left" ? barOffset : 0

  // Centred under its button, kept on screen.
  readonly property int cardAlong: {
    if (!anchorItem || !bar) return margin
    var along = horizontalBar
      ? anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      : anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    var limit = horizontalBar ? screenW - contentWidth : screenH - contentHeight
    return Math.round(Math.max(margin, Math.min(along, limit - margin)))
  }

  onOpenChanged: {
    if (open) Qt.callLater(collectPeers)
    // Or a hosted popup is left floating with a destroyed anchor.
    else root.hostBar.closeHostedPopouts()

    if (!bar) return
    if (open) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
  }

  // One dismissal surface per monitor, on Top so the card on Overlay stays above them.
  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: dismissWindow
        required property var modelData

        readonly property real strip: root.bar
          ? Math.max(root.bar.barSize, root.barThickness) + root.gap : 0

        screen: modelData
        visible: root.open
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "leyanora-plugincontainers-dismiss"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        mask: Region {
          x: root.barPos === "left" ? dismissWindow.strip : 0
          y: root.barPos === "top" ? dismissWindow.strip : 0
          width: dismissWindow.width - (root.barPos === "left" || root.barPos === "right"
            ? dismissWindow.strip : 0)
          height: dismissWindow.height - (root.barPos === "top" || root.barPos === "bottom"
            ? dismissWindow.strip : 0)
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: root.close()
        }
      }
    }
  }

  BorderSurface {
    id: card
    x: root.horizontalBar ? root.cardAlong : root.cardPerp
    y: root.horizontalBar ? root.cardPerp : root.cardAlong
    width: root.contentWidth
    height: root.contentHeight
    color: Color.popups.background
    borderSpec: root.borderSpec
    padding: root.padding
    radius: Math.max(Style.cornerRadius, Style.space(6))
    opacity: root.open ? 1.0 : 0

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    // Swallow clicks on the card so they do not reach the dismissal area.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    Column {
      id: layout
      x: card.contentLeftInset
      y: card.contentTopInset
      width: card.width - card.contentLeftInset - card.contentRightInset
      spacing: Style.spacing.lg

      Text {
        id: title
        width: parent.width
        text: root.container ? root.container.name : ""
        // Container names are user input; AutoText would parse a `<` in one.
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      PanelSeparator {
        width: parent.width
        foreground: root.foreground
      }

      Column {
        width: parent.width
        spacing: Style.spacing.sm
        visible: root.members.length === 0

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Glyphs.empty
          color: Qt.darker(root.foreground, 1.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.iconLarge
        }

        Text {
          width: parent.width
          text: "No plugins in this container yet. Open the container manager and drag plugins in."
          textFormat: Text.PlainText
          color: Qt.darker(root.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }

      // Last row of the card, so a popup opened from a widget clears the strip.
      Row {
        id: strip
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.spacing.lg
        visible: root.members.length > 0

        Repeater {
          id: repeater
          model: root.members

          delegate: BorderSurface {
            id: cell
            required property var modelData

            readonly property var widget: hosted.widget

            color: Style.normalFillFor(root.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
            radius: Math.max(Style.cornerRadius, Style.space(4))
            padding: Style.spacing.sm
            implicitWidth: hosted.implicitWidth + padding * 2 + borderLeft + borderRight
            implicitHeight: hosted.implicitHeight + padding * 2 + borderTop + borderBottom

            // Before the widget, so the widget's own mouse areas win where they overlap.
            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
              enabled: hosted.routable
              cursorShape: Qt.PointingHandCursor
              onClicked: function (mouse) { hosted.press(mouse.button) }
            }

            HostedWidget {
              id: hosted
              anchors.centerIn: parent
              pluginId: cell.modelData
              label: root.store.pluginInfo(cell.modelData).name
              source: root.store.entryUrlFor(cell.modelData)
              hostBar: root.hostBar
              hostSettings: root.store.settingsFor(cell.modelData)
              foreground: root.foreground
              onWidgetChanged: Qt.callLater(root.collectPeers)
            }
          }
        }
      }
    }
  }

  // Anchored inside the strip: mapFromItem only works within one window.
  HostTooltip {
    id: tooltip
    anchorItem: layout
    foreground: Color.tooltip.text
  }

  Connections {
    target: root.hostBar
    function onTooltipRequested(target, text) { tooltip.show(target, text) }
    function onTooltipDismissed(target) { tooltip.hide(target) }
  }
}
