import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// Every installed plugin with a bar widget, switched on or not.
Item {
  id: root

  required property var store
  required property string containerId
  property color foreground: Color.popups.text

  signal addRequested(string pluginId)
  signal dragStarted(string pluginId, string label, real sceneX, real sceneY)
  signal dragMoved(real sceneX, real sceneY)
  signal dragFinished()

  readonly property var container: store.containerById(containerId)
  readonly property var memberIds: container ? container.members : []
  readonly property string query: search.text.trim().toLowerCase()

  readonly property var rows: {
    var out = []
    var all = store.catalogue
    for (var i = 0; i < all.length; i++) {
      var plugin = all[i]
      // A plugin in this container has moved to the list above, not vanished.
      if (memberIds.indexOf(plugin.id) !== -1) continue
      if (query !== ""
          && plugin.name.toLowerCase().indexOf(query) === -1
          && plugin.id.toLowerCase().indexOf(query) === -1
          && plugin.category.toLowerCase().indexOf(query) === -1) continue
      out.push(plugin)
    }
    return out
  }

  // Handed to KeyboardPanel.focusTarget.
  readonly property alias searchField: search

  function clearSearch() { search.text = "" }

  // Anchors, not a Column: the Flickable has to absorb the leftover height without a loop.
  Column {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.labelGap

    PanelSectionHeader {
      text: "AVAILABLE PLUGINS"
      foreground: root.foreground
    }

    TextField {
      id: search
      width: parent.width
      foreground: root.foreground
      placeholderText: "Search by name, id or category"
      // A layer surface accepts clicks before Qt focuses anything inside it, hence focusTarget.
    }
  }

  Text {
    id: emptyLabel
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.lg
    anchors.left: parent.left
    anchors.right: parent.right
    visible: root.rows.length === 0
    text: root.store.catalogue.length === 0
      ? "No plugins with a bar widget are installed."
      : search.text !== "" ? "No plugin matches “" + search.text + "”."
      : "Every installed plugin is already in this container."
    textFormat: Text.PlainText
    color: Qt.darker(root.foreground, 1.4)
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.italic: true
    wrapMode: Text.WordWrap
  }

  Flickable {
    id: flick
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.lg
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: root.rows.length > 0
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
        model: root.rows

        delegate: BorderSurface {
          id: row
          required property var modelData

          readonly property bool heldElsewhere: root.store.holderCount(modelData.id) > 0

          width: list.width
          radius: Math.max(Style.cornerRadius, Style.space(4))
          padding: Style.spacing.sm
          leftPadding: Style.spacing.md
          rightPadding: Style.spacing.sm
          implicitHeight: rowLayout.implicitHeight + contentTopInset + contentBottomInset
          color: rowMouse.containsMouse
            ? Style.hoverFillFor(root.foreground, Color.accent)
            : "transparent"

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.containerId !== ""
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            acceptedButtons: Qt.LeftButton

            // Hand-rolled drag, as the bar's own reorder is: the shell has no DragHandler anywhere.
            property bool dragging: false
            property real pressX: 0
            property real pressY: 0
            readonly property real threshold: Style.space(4)

            onPressed: function (mouse) {
              dragging = false
              pressX = mouse.x
              pressY = mouse.y
            }

            onPositionChanged: function (mouse) {
              if (!(mouse.buttons & Qt.LeftButton)) return
              var scene = row.mapToItem(null, mouse.x, mouse.y)
              if (!dragging && Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) >= threshold) {
                dragging = true
                root.dragStarted(row.modelData.id, row.modelData.name, scene.x, scene.y)
              }
              if (dragging) root.dragMoved(scene.x, scene.y)
            }

            onReleased: {
              if (!dragging) return
              dragging = false
              root.dragFinished()
            }

            onCanceled: {
              if (!dragging) return
              dragging = false
              root.dragFinished()
            }

            onClicked: if (!dragging) root.addRequested(row.modelData.id)
          }

          Item {
            id: rowLayout
            x: row.contentLeftInset
            y: row.contentTopInset
            width: row.width - row.contentLeftInset - row.contentRightInset
            implicitHeight: Math.max(text.implicitHeight, addButton.implicitHeight)

            Column {
              id: text
              anchors.left: parent.left
              anchors.right: addButton.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                width: parent.width
                text: row.modelData.name
                textFormat: Text.PlainText
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: row.heldElsewhere
                  ? row.modelData.category + " · also in another container"
                  : row.modelData.category + " · " + row.modelData.id
                textFormat: Text.PlainText
                color: Qt.darker(root.foreground, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              id: addButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              enabled: root.containerId !== ""
              iconText: Glyphs.add
              foreground: root.foreground
              tooltipText: "Add to container"
              onClicked: root.addRequested(row.modelData.id)
            }
          }
        }
      }
    }
  }
}
