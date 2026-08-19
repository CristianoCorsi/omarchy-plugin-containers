import QtQuick
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// The selected container's plugins, and the drop target for the picker.
Item {
  id: root

  required property var store
  required property string containerId
  property color foreground: Color.popups.text

  // Pointer position during a drag, fed by the panel.
  property bool dragActive: false
  property string dragPluginId: ""
  property real dragSceneX: 0
  property real dragSceneY: 0

  signal removeRequested(string pluginId)
  signal reorderRequested(string pluginId, int toIndex)

  readonly property var container: store.containerById(containerId)
  readonly property var members: container ? container.members : []

  // Where a drop would land, or -1 when the pointer is elsewhere. Rows are uniform.
  readonly property int dropIndex: {
    if (!dragActive) return -1
    // Measured inside the drop box: the header above it would offset every row.
    var local = dropBox.mapFromItem(null, dragSceneX, dragSceneY)
    if (local.x < 0 || local.x > dropBox.width || local.y < 0 || local.y > dropBox.height) return -1
    var step = rowHeight + list.spacing
    var slot = Math.round((local.y - dropBox.padding) / Math.max(1, step))
    return Math.max(0, Math.min(members.length, slot))
  }

  readonly property bool dropTargeted: dropIndex !== -1
  readonly property real rowHeight: Style.space(34)

  // Content-sized, so an empty container does not reserve a screenful of drop target.
  implicitHeight: layout.implicitHeight

  Column {
    id: layout
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    PanelSectionHeader {
      text: root.container ? "IN " + root.container.name.toUpperCase() : "IN THIS CONTAINER"
      foreground: root.foreground
    }

    BorderSurface {
      id: dropBox
      width: parent.width
      height: Math.max(root.rowHeight, list.implicitHeight + padding * 2)
      radius: Math.max(Style.cornerRadius, Style.space(4))
      padding: Style.spacing.xs
      color: root.dropTargeted ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
      // Outlined only during a drag; a permanent box reads as a clickable control.
      borderSpec: root.dropTargeted
        ? Border.controlSpec("selected", Color.accent, Color.accent)
        : Border.controlSpec("normal", root.foreground, Color.accent)

      Text {
        anchors.centerIn: parent
        visible: root.members.length === 0
        text: root.containerId === ""
          ? "Select a container to fill it."
          : (root.dragActive ? "Drop to add" : "Empty — drag a plugin here, or use its + button")
        textFormat: Text.PlainText
        color: Qt.darker(root.foreground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.italic: true
      }

      Column {
        id: list
        x: parent.padding
        y: parent.padding
        width: parent.width - parent.padding * 2
        spacing: Style.spacing.xxs

        Repeater {
          model: root.members

          delegate: Item {
            id: memberRow
            required property var modelData
            required property int index

            readonly property var info: root.store.pluginInfo(modelData)
            readonly property bool shared: root.store.holderCount(modelData) > 1

            width: list.width
            height: root.rowHeight

            Rectangle {
              anchors.fill: parent
              radius: Math.max(Style.cornerRadius, Style.space(4))
              color: rowMouse.containsMouse
                ? Style.hoverFillFor(root.foreground, Color.accent)
                : "transparent"
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              cursorShape: Qt.PointingHandCursor

              property bool dragging: false
              property real pressY: 0
              readonly property real threshold: Style.space(4)

              onPressed: function (mouse) {
                dragging = false
                pressY = mouse.y
              }

              onPositionChanged: function (mouse) {
                if (!(mouse.buttons & Qt.LeftButton)) return
                if (!dragging && Math.abs(mouse.y - pressY) < threshold) return
                dragging = true
                var local = list.mapFromItem(memberRow, 0, mouse.y)
                var step = root.rowHeight + list.spacing
                var slot = Math.max(0, Math.min(root.members.length - 1,
                  Math.floor(local.y / Math.max(1, step))))
                if (slot !== memberRow.index) root.reorderRequested(memberRow.modelData, slot)
              }

              onReleased: dragging = false
              onCanceled: dragging = false
            }

            Text {
              id: grip
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              text: Glyphs.grip
              color: Qt.darker(root.foreground, 1.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.icon
            }

            Column {
              anchors.left: grip.right
              anchors.leftMargin: Style.spacing.md
              anchors.right: removeButton.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                width: parent.width
                text: memberRow.info.name
                textFormat: Text.PlainText
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: memberRow.shared
                text: "Also in another container"
                textFormat: Text.PlainText
                color: Qt.darker(root.foreground, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              id: removeButton
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.xs
              anchors.verticalCenter: parent.verticalCenter
              iconText: Glyphs.close
              foreground: root.foreground
              hoverColor: Color.urgent
              tooltipText: "Take out of this container (the plugin itself stays installed)"
              onClicked: root.removeRequested(memberRow.modelData)
            }
          }
        }
      }

      // Where the dragged plugin would be inserted.
      Rectangle {
        visible: root.dropTargeted && root.members.length > 0
        x: parent.padding
        y: parent.padding + Math.min(root.dropIndex, root.members.length) * (root.rowHeight + list.spacing)
        width: parent.width - parent.padding * 2
        height: Math.max(1, Style.space(2))
        radius: height / 2
        color: Color.accent
      }
    }
  }
}
