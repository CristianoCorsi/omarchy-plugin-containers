import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// The manager's second view: the handful of options that apply to every container.
Item {
  id: root

  required property var store
  property color foreground: Color.popups.text

  signal backRequested()

  // Or the picker's search field, still instantiated behind this view, keeps the keys.
  function takeFocus() { back.forceActiveFocus() }

  readonly property var options: store.settings

  // Hiding the box with nothing else of ours in the bar leaves no way back but IPC.
  readonly property bool canHideIcon: store.containerCount > 0

  // A label rather than a button: this is navigation, not one of the actions on this page.
  Item {
    id: back
    anchors.top: parent.top
    anchors.left: parent.left
    implicitWidth: backRow.implicitWidth
    implicitHeight: backRow.implicitHeight + Style.spacing.xs * 2

    activeFocusOnTab: true
    Keys.onReturnPressed: root.backRequested()
    Keys.onEnterPressed: root.backRequested()
    Keys.onSpacePressed: root.backRequested()
    Keys.onEscapePressed: root.backRequested()

    readonly property bool hot: backMouse.containsMouse || activeFocus

    Row {
      id: backRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Glyphs.left
        color: back.hot ? root.foreground : Qt.darker(root.foreground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Containers"
        textFormat: Text.PlainText
        color: back.hot ? root.foreground : Qt.darker(root.foreground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: backMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.backRequested()
    }
  }

  Column {
    id: header
    anchors.top: back.bottom
    anchors.topMargin: Style.spacing.lg
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.labelGap

    PanelSectionHeader {
      text: "SETTINGS"
      foreground: root.foreground
    }

    Text {
      width: parent.width
      text: "These apply to every container."
      textFormat: Text.PlainText
      color: Qt.darker(root.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Flickable {
    id: flick
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.lg
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    contentWidth: width
    contentHeight: list.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height

    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: list
      width: flick.width
      spacing: Style.spacing.lg

      Toggle {
        width: parent.width
        label: "Hide the container name"
        description: "The name still shows when you hover the container's icon in the bar."
        titleSize: Style.font.bodySmall
        checked: root.options.hideTitle
        foreground: root.foreground
        onClicked: root.store.setSetting("hideTitle", !root.options.hideTitle)
      }

      Toggle {
        width: parent.width
        label: "Hide the plugin containers icon"
        description: root.canHideIcon
          ? "Frees its bar slot. Right-click a container icon to get back here, or run "
            + "omarchy-shell leyanora.plugincontainers showIcon."
          : "Not while there are no containers: the box would be the only way back."
        titleSize: Style.font.bodySmall
        checked: root.options.hideBarIcon
        foreground: root.foreground
        enabled: root.canHideIcon || root.options.hideBarIcon
        opacity: enabled ? 1 : 0.5
        onClicked: root.store.setSetting("hideBarIcon", !root.options.hideBarIcon)
      }

      // Shaped like a Toggle row at rest, so the three options read as one set. No hover or
      // click on the surface itself: the field beside the label is what takes the input.
      BorderSurface {
        id: perRow
        width: parent.width
        implicitHeight: Math.max(54, perRowContent.implicitHeight + Style.spacing.huge)
        radius: Style.cornerRadius
        color: Style.controlFill(false, false, root.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        Row {
          id: perRowContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: perRow.borderLeft + Style.spacing.rowPaddingX
          anchors.rightMargin: perRow.borderRight + Style.spacing.rowPaddingX
          spacing: Style.spacing.rowPaddingX

          Column {
            width: parent.width - field.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            Text {
              width: parent.width
              text: "Icons per row"
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: "An open container wraps onto another row past this many plugins."
              textFormat: Text.PlainText
              color: Qt.darker(root.foreground, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          NumberField {
            id: field
            anchors.verticalCenter: parent.verticalCenter
            value: root.options.iconsPerRow
            from: 1
            to: 10
            stepSize: 1
            foreground: root.foreground
            onModified: function (next) { root.store.setSetting("iconsPerRow", next) }
          }
        }
      }
    }
  }
}
