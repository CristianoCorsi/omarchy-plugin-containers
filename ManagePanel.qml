import QtQuick
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// The container manager: containers on the left, contents and catalogue on the right.
KeyboardPanel {
  id: root

  required property var store

  readonly property color foreground: Color.popups.text
  property string selectedId: ""

  property string view: "containers"
  readonly property bool onContainers: view === "containers"

  // One sheet for create and rename: they ask for exactly the same two things.
  property bool naming: false
  property string namingId: ""
  property string namingIcon: Glyphs.container

  property bool dragActive: false
  property string dragPluginId: ""
  property string dragLabel: ""
  property real dragSceneX: 0
  property real dragSceneY: 0

  readonly property bool hasSelection: selectedId !== "" && store.containerById(selectedId) !== null

  function beginCreate() {
    namingId = ""
    namingIcon = Glyphs.container
    nameField.text = ""
    naming = true
    Qt.callLater(function () { if (root.naming) nameField.forceActiveFocus() })
  }

  function beginRename(containerId) {
    var container = store.containerById(containerId)
    if (!container) return
    namingId = containerId
    namingIcon = container.icon || Glyphs.container
    nameField.text = container.name
    naming = true
    Qt.callLater(function () { if (root.naming) nameField.forceActiveFocus() })
  }

  function commitNaming() {
    var name = nameField.text.trim()
    if (name === "") return
    if (namingId === "") root.selectedId = store.createContainer(name, namingIcon)
    else store.updateContainer(namingId, name, namingIcon)
    cancelNaming()
  }

  function cancelNaming() {
    naming = false
    namingId = ""
    nameField.text = ""
    picker.searchField.forceActiveFocus()
  }

  // Keeps a selection alive as containers come and go.
  function syncSelection() {
    if (hasSelection) return
    selectedId = store.containerCount > 0 ? store.containers[0].id : ""
  }

  // The picker's field is always instantiated, so it would take focus behind the settings view.
  focusTarget: naming ? nameField : (onContainers ? picker.searchField : null)
  contentWidth: fittedContentWidth(Style.space(720))
  contentHeight: fittedContentHeight(Style.space(460), Style.space(560))

  onOpenChanged: {
    if (open) {
      syncSelection()
      picker.clearSearch()
    } else {
      cancelNaming()
      confirmDelete.opened = false
      dragActive = false
      view = "containers"
    }
  }

  Item {
    id: body
    anchors.fill: parent

    // Inside `body` because KeyboardPanel's default property only accepts Items.
    Connections {
      target: root.store
      function onPersisted(next) { Qt.callLater(root.syncSelection) }
    }

    ContainerList {
      id: containerList
      visible: root.onContainers
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      width: Math.round(parent.width * 0.42)
      store: root.store
      selectedId: root.selectedId
      foreground: root.foreground
      onSelected: function (containerId) { root.selectedId = containerId }
      onSettingsRequested: {
        root.view = "settings"
        settingsView.takeFocus()
      }
      onCreateRequested: root.beginCreate()
      onRenameRequested: function (containerId) { root.beginRename(containerId) }
      onDeleteRequested: function (containerId) {
        confirmDelete.pendingId = containerId
        confirmDelete.opened = true
      }
    }

    Rectangle {
      id: divider
      visible: root.onContainers
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: containerList.right
      anchors.leftMargin: Style.spacing.panelGap
      width: 1
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
    }

    Item {
      id: rightPane
      visible: root.onContainers
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: divider.right
      anchors.leftMargin: Style.spacing.panelGap
      anchors.right: parent.right

      MemberList {
        id: memberList
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.min(memberList.implicitHeight, Math.round(rightPane.height * 0.55))
        store: root.store
        containerId: root.hasSelection ? root.selectedId : ""
        foreground: root.foreground
        dragActive: root.dragActive
        dragPluginId: root.dragPluginId
        dragSceneX: root.dragSceneX
        dragSceneY: root.dragSceneY
        onRemoveRequested: function (pluginId) { root.store.removePlugin(root.selectedId, pluginId) }
        onReorderRequested: function (pluginId, toIndex) {
          root.store.movePlugin(root.selectedId, pluginId, toIndex)
        }
      }

      PluginPicker {
        id: picker
        anchors.top: memberList.bottom
        anchors.topMargin: Style.spacing.panelGap
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        store: root.store
        containerId: root.hasSelection ? root.selectedId : ""
        foreground: root.foreground

        onAddRequested: function (pluginId) {
          if (!root.hasSelection) return
          root.store.addPlugin(root.selectedId, pluginId)
        }

        onDragStarted: function (pluginId, label, sceneX, sceneY) {
          root.dragPluginId = pluginId
          root.dragLabel = label
          root.dragSceneX = sceneX
          root.dragSceneY = sceneY
          root.dragActive = true
        }

        onDragMoved: function (sceneX, sceneY) {
          root.dragSceneX = sceneX
          root.dragSceneY = sceneY
        }

        onDragFinished: {
          // Read the drop target before clearing the drag; it derives from the live pointer.
          var index = memberList.dropIndex
          var pluginId = root.dragPluginId
          root.dragActive = false
          root.dragPluginId = ""
          if (index === -1 || !root.hasSelection) return
          root.store.addPlugin(root.selectedId, pluginId)
          root.store.movePlugin(root.selectedId, pluginId, index)
        }
      }
    }

    SettingsView {
      id: settingsView
      anchors.fill: parent
      visible: !root.onContainers
      store: root.store
      foreground: root.foreground
      onBackRequested: {
        root.view = "containers"
        picker.searchField.forceActiveFocus()
      }
    }

    // A plain Item suffices: only the bar needs an overlay window, for cross-monitor drags.
    BorderSurface {
      id: ghost
      visible: root.dragActive
      z: 100
      readonly property point local: body.mapFromItem(null, root.dragSceneX, root.dragSceneY)
      x: local.x + Style.spacing.md
      y: local.y - height / 2
      width: ghostLabel.implicitWidth + Style.spacing.rowPaddingX * 2
      height: ghostLabel.implicitHeight + Style.spacing.sm * 2
      radius: Math.max(Style.cornerRadius, Style.space(4))
      color: Color.popups.background
      borderSpec: Border.flat(Color.accent, Math.max(1, Style.space(1)))
      opacity: 0.94

      Text {
        id: ghostLabel
        anchors.centerIn: parent
        text: root.dragLabel
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    Rectangle {
      anchors.fill: parent
      visible: root.naming
      color: Util.alpha(Color.popups.background, 0.85)
      z: 200

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.cancelNaming()
      }

      BorderSurface {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.spacing.panelPadding * 2, Style.space(380))
        height: sheet.implicitHeight + padding * 2
        padding: Style.spacing.panelPadding
        radius: Math.max(Style.cornerRadius, Style.space(6))
        color: Color.popups.background
        borderSpec: Border.flat(Color.popups.border, Math.max(1, Style.space(2)))

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
        }

        Column {
          id: sheet
          x: parent.padding
          y: parent.padding
          width: parent.width - parent.padding * 2
          spacing: Style.spacing.lg

          Text {
            text: root.namingId === "" ? "New container" : "Rename container"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            PanelSectionHeader {
              text: "NAME"
              foreground: root.foreground
            }

            TextField {
              id: nameField
              width: parent.width
              foreground: root.foreground
              placeholderText: "e.g. network"
              onAccepted: root.commitNaming()
              Keys.onEscapePressed: root.cancelNaming()
            }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            PanelSectionHeader {
              text: "ICON"
              foreground: root.foreground
            }

            // Sized to the name field above it, wrapping onto as many rows as the icons need.
            Grid {
              id: iconGrid
              width: parent.width
              spacing: Style.spacing.xs

              readonly property int span: Math.floor(width)
              readonly property int gaps: spacing * (columns - 1)
              readonly property int track: Math.floor((span - gaps) / columns)
              readonly property int wide: span - gaps - track * columns

              columns: Math.max(1, Math.floor((span + spacing) / (Style.space(30) + spacing)))

              Repeater {
                model: Glyphs.choices

                delegate: Button {
                  required property var modelData
                  required property int index
                  // Leftover pixels go one per column, so the grid ends flush with the field above.
                  width: iconGrid.track + (index % iconGrid.columns < iconGrid.wide ? 1 : 0)
                  text: modelData
                  fontSize: Style.font.icon
                  foreground: root.foreground
                  selected: root.namingIcon === modelData
                  bordered: true
                  horizontalPadding: Style.spacing.xs
                  verticalPadding: Style.spacing.xs
                  onClicked: root.namingIcon = modelData
                }
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: confirmRow.implicitHeight

            Row {
              id: confirmRow
              anchors.right: parent.right
              spacing: Style.spacing.controlGap

              Button {
                text: "Cancel"
                foreground: root.foreground
                onClicked: root.cancelNaming()
              }

              Button {
                text: root.namingId === "" ? "Create" : "Save"
                foreground: root.foreground
                bordered: true
                active: true
                enabled: nameField.text.trim() !== ""
                opacity: enabled ? 1 : 0.5
                onClicked: root.commitNaming()
              }
            }
          }
        }
      }
    }

    ConfirmDialog {
      id: confirmDelete
      property string pendingId: ""

      anchors.fill: parent
      z: 300
      foreground: root.foreground
      background: Color.popups.background
      confirmText: "Delete"
      message: {
        var container = root.store.containerById(confirmDelete.pendingId)
        if (!container) return ""
        return container.members.length === 0
          ? "Delete “" + container.name + "”?"
          : "Delete “" + container.name + "”? Its " + container.members.length
            + " plugin(s) go back to the bar."
      }
      onCanceled: {
        confirmDelete.opened = false
        confirmDelete.pendingId = ""
      }
      onConfirmed: {
        root.store.deleteContainer(confirmDelete.pendingId)
        confirmDelete.opened = false
        confirmDelete.pendingId = ""
        Qt.callLater(root.syncSelection)
      }
    }
  }
}
