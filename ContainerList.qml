import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// Create, select, rename, re-icon, reorder, delete. List order is bar order.
Item {
  id: root

  required property var store
  property string selectedId: ""
  property color foreground: Color.popups.text

  signal selected(string containerId)
  signal createRequested()
  signal renameRequested(string containerId)
  signal deleteRequested(string containerId)

  readonly property var containers: store.containers

  Column {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.labelGap

    PanelSectionHeader {
      text: "CONTAINERS"
      foreground: root.foreground
    }

    Text {
      width: parent.width
      text: "Each container is one button in the bar. Select one to fill it."
      textFormat: Text.PlainText
      color: Qt.darker(root.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  Button {
    id: createButton
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    iconText: Glyphs.add
    text: "New container"
    foreground: root.foreground
    // The one primary action here, so it reads differently from the per-row actions.
    bordered: true
    active: true
    leftAlign: true
    onClicked: root.createRequested()
  }

  // Outside the Flickable: its children are parented to the scrolled content item.
  Text {
    anchors.centerIn: flick
    visible: root.containers.length === 0
    text: "No containers yet."
    textFormat: Text.PlainText
    color: Qt.darker(root.foreground, 1.4)
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.italic: true
  }

  Flickable {
    id: flick
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.lg
    anchors.bottom: createButton.top
    anchors.bottomMargin: Style.spacing.lg
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
      spacing: Style.spacing.xxs

      Repeater {
        model: root.containers

        delegate: BorderSurface {
          id: entry
          required property var modelData
          required property int index

          readonly property bool current: modelData.id === root.selectedId

          width: list.width
          radius: Math.max(Style.cornerRadius, Style.space(4))
          padding: Style.spacing.sm
          implicitHeight: content.implicitHeight + contentTopInset + contentBottomInset
          color: entry.current ? Style.selectedFillFor(root.foreground, Color.accent)
            : (entryMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
          borderSpec: entry.current
            ? Border.controlSpec("selected", root.foreground, Color.accent)
            : Border.none()

          MouseArea {
            id: entryMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selected(entry.modelData.id)
          }

          Item {
            id: content
            x: entry.contentLeftInset
            y: entry.contentTopInset
            width: entry.width - entry.contentLeftInset - entry.contentRightInset
            implicitHeight: Math.max(label.implicitHeight, actions.implicitHeight, icon.implicitHeight)

            Text {
              id: icon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: entry.modelData.icon || Glyphs.container
              // Fill and border only; a tinted icon would make a container's colour mean something.
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.icon
            }

            Column {
              id: label
              anchors.left: icon.right
              anchors.leftMargin: Style.spacing.md
              anchors.right: actions.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                width: parent.width
                text: entry.modelData.name
                // Container names are user input.
                textFormat: Text.PlainText
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: entry.current
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: entry.modelData.members.length === 1
                  ? "1 plugin" : entry.modelData.members.length + " plugins"
                textFormat: Text.PlainText
                color: Qt.darker(root.foreground, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              id: actions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs

              PanelActionButton {
                iconText: Glyphs.rename
                foreground: root.foreground
                tooltipText: "Rename this container"
                onClicked: root.renameRequested(entry.modelData.id)
              }

              PanelActionButton {
                iconText: Glyphs.del
                foreground: root.foreground
                hoverColor: Color.urgent
                tooltipText: "Delete this container (its plugins go back to the bar)"
                onClicked: root.deleteRequested(entry.modelData.id)
              }
            }
          }
        }
      }
    }
  }
}
