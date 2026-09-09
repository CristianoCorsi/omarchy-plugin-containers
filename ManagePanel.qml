import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Glyphs.js" as Glyphs
import "Store.js" as Model

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

  // The plugin the move sheet is asking a destination for.
  property string movingPluginId: ""

  property bool errorDismissed: false

  property bool dragActive: false
  property string dragPluginId: ""
  property string dragLabel: ""
  property real dragSceneX: 0
  property real dragSceneY: 0

  readonly property bool hasSelection: selectedId !== "" && !!store
    && store.containerById(selectedId) !== null

  function beginCreate() {
    namingId = ""
    namingIcon = Glyphs.container
    nameField.text = ""
    glyphField.text = ""
    naming = true
    Qt.callLater(function () { if (root.naming) nameField.forceActiveFocus() })
  }

  function beginRename(containerId) {
    var container = store.containerById(containerId)
    if (!container) return
    namingId = containerId
    namingIcon = container.icon || Glyphs.container
    nameField.text = container.name
    // A glyph the grid does not offer is only visible if the field shows it.
    glyphField.text = Glyphs.choices.indexOf(namingIcon) === -1 ? namingIcon : ""
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
    glyphField.text = ""
    picker.searchField.forceActiveFocus()
  }

  // Both read store.state through the store's own helpers, so they follow a write.
  readonly property var containerOptions: store.effectiveSettings(namingId)
  readonly property bool overridden: namingId !== "" && store.hasOverrides(namingId)

  readonly property var moveTargets: {
    var out = []
    for (var i = 0; i < store.containers.length; i++) {
      if (store.containers[i].id !== selectedId) out.push(store.containers[i])
    }
    return out
  }

  function moveTo(containerId) {
    store.movePluginToContainer(selectedId, containerId, movingPluginId)
    movingPluginId = ""
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
      movingPluginId = ""
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
      function onStateChanged() { Qt.callLater(root.syncSelection) }
      function onErrorChanged() { root.errorDismissed = false }
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
      onReorderRequested: function (containerId, delta) {
        root.store.reorderContainer(containerId, delta)
      }
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
        onMoveRequested: function (pluginId) { root.movingPluginId = pluginId }
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
        id: nameSheet
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.spacing.panelPadding * 2, Style.space(380))
        height: Math.min(sheet.implicitHeight + padding * 2, parent.height)
        padding: Style.spacing.panelPadding
        radius: Math.max(Style.cornerRadius, Style.space(6))
        color: Color.popups.background
        borderSpec: Border.flat(Color.popups.border, Math.max(1, Style.space(2)))

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
        }

        Flickable {
          id: sheetFlick
          x: nameSheet.padding
          y: nameSheet.padding
          width: nameSheet.width - nameSheet.padding * 2
          height: nameSheet.height - nameSheet.padding * 2
          contentWidth: width
          contentHeight: sheet.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: sheet
            width: sheetFlick.width
            spacing: Style.spacing.lg

            Text {
              text: root.namingId === "" ? "New container" : "Edit container"
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
                    onClicked: {
                      root.namingIcon = modelData
                      glyphField.text = ""
                    }
                  }
                }
              }

              // Any glyph the bar can draw, not only the thirty offered above.
              Row {
                width: parent.width
                spacing: Style.spacing.md

                TextField {
                  id: glyphField
                  width: parent.width - glyphPreview.width - parent.spacing
                  foreground: root.foreground
                  placeholderText: "or paste a glyph"
                  onTextChanged: {
                    var glyph = Model.icon(text)
                    if (glyph !== "") root.namingIcon = glyph
                  }
                  onAccepted: root.commitNaming()
                  Keys.onEscapePressed: root.cancelNaming()
                }

                Text {
                  id: glyphPreview
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(30)
                  text: root.namingIcon
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.icon
                  horizontalAlignment: Text.AlignHCenter
                }
              }

              Text {
                width: parent.width
                visible: glyphField.text !== "" && Model.icon(glyphField.text) === ""
                text: "The bar cannot draw that as an icon; the last valid one is kept."
                textFormat: Text.PlainText
                color: Color.urgent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            // Only on an existing container: there is nothing to override until it has an id.
            // Written as they are changed, like the global settings view, not on Save.
            Column {
              width: parent.width
              spacing: Style.spacing.labelGap
              visible: root.namingId !== ""

              PanelSectionHeader {
                text: "THIS CONTAINER"
                foreground: root.foreground
              }

              Toggle {
                width: parent.width
                label: "Follow the global settings"
                description: "Off lets this container wrap and label itself its own way."
                titleSize: Style.font.bodySmall
                checked: !root.overridden
                foreground: root.foreground
                onClicked: {
                  if (root.overridden) root.store.clearContainerSettings(root.namingId)
                  // Seeded with what is in force, so switching over changes nothing by itself.
                  else root.store.setContainerSettings(root.namingId, {
                    iconsPerRow: root.containerOptions.iconsPerRow,
                    hideTitle: root.containerOptions.hideTitle,
                    mode: root.containerOptions.mode
                  })
                }
              }

              Toggle {
                width: parent.width
                visible: root.overridden
                label: "Expand in the bar"
                titleSize: Style.font.bodySmall
                checked: root.containerOptions.mode === "inline"
                foreground: root.foreground
                onClicked: root.store.setContainerSetting(root.namingId, "mode",
                  root.containerOptions.mode === "inline" ? "strip" : "inline")
              }

              Toggle {
                width: parent.width
                visible: root.overridden
                label: "Hide the container name"
                titleSize: Style.font.bodySmall
                checked: root.containerOptions.hideTitle
                foreground: root.foreground
                onClicked: root.store.setContainerSetting(root.namingId, "hideTitle",
                  !root.containerOptions.hideTitle)
              }

              Row {
                width: parent.width
                visible: root.overridden
                spacing: Style.spacing.md

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - perRowField.width - parent.spacing
                  text: "Icons per row"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                NumberField {
                  id: perRowField
                  anchors.verticalCenter: parent.verticalCenter
                  value: root.containerOptions.iconsPerRow
                  from: 1
                  to: 10
                  stepSize: 1
                  foreground: root.foreground
                  onModified: function (next) {
                    root.store.setContainerSetting(root.namingId, "iconsPerRow", next)
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
    }

    Rectangle {
      anchors.fill: parent
      visible: root.movingPluginId !== ""
      color: Util.alpha(Color.popups.background, 0.85)
      z: 220

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.movingPluginId = ""
      }

      BorderSurface {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.spacing.panelPadding * 2, Style.space(380))
        height: moveSheet.implicitHeight + padding * 2
        padding: Style.spacing.panelPadding
        radius: Math.max(Style.cornerRadius, Style.space(6))
        color: Color.popups.background
        borderSpec: Border.flat(Color.popups.border, Math.max(1, Style.space(2)))

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
        }

        Column {
          id: moveSheet
          x: parent.padding
          y: parent.padding
          width: parent.width - parent.padding * 2
          spacing: Style.spacing.lg

          Text {
            width: parent.width
            text: "Move “" + root.store.pluginInfo(root.movingPluginId).name + "” to"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Flickable {
            id: targetFlick
            width: parent.width
            height: Math.min(targets.implicitHeight, Style.space(280))
            contentWidth: width
            contentHeight: targets.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height

            Column {
              id: targets
              width: targetFlick.width
              spacing: Style.spacing.xxs

              Repeater {
                model: root.moveTargets

                delegate: Button {
                  required property var modelData

                  readonly property bool alreadyHere:
                    modelData.members.indexOf(root.movingPluginId) !== -1

                  width: targets.width
                  iconText: modelData.icon || Glyphs.container
                  text: alreadyHere ? modelData.name + " — already in there" : modelData.name
                  foreground: root.foreground
                  leftAlign: true
                  enabled: !alreadyHere
                  opacity: enabled ? 1 : 0.5
                  onClicked: root.moveTo(modelData.id)
                }
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: moveCancel.implicitHeight

            Button {
              id: moveCancel
              anchors.right: parent.right
              text: "Cancel"
              foreground: root.foreground
              onClicked: root.movingPluginId = ""
            }
          }
        }
      }
    }

    // A write that did not land is otherwise silent: commit() sets error and returns.
    BorderSurface {
      id: errorBanner
      visible: root.store.error !== "" && !root.errorDismissed
      z: 150
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      padding: Style.spacing.sm
      radius: Math.max(Style.cornerRadius, Style.space(4))
      color: Color.popups.background
      borderSpec: Border.flat(Color.urgent, Math.max(1, Style.space(2)))
      implicitHeight: Math.max(errorText.implicitHeight, dismissError.implicitHeight)
        + contentTopInset + contentBottomInset

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
      }

      Text {
        id: errorText
        x: errorBanner.contentLeftInset
        y: errorBanner.contentTopInset
        width: errorBanner.width - errorBanner.contentLeftInset - errorBanner.contentRightInset
          - dismissError.width - Style.spacing.sm
        text: "Not saved — " + root.store.error
        textFormat: Text.PlainText
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      PanelActionButton {
        id: dismissError
        anchors.right: parent.right
        anchors.rightMargin: errorBanner.contentRightInset
        anchors.verticalCenter: parent.verticalCenter
        iconText: Glyphs.close
        foreground: root.foreground
        tooltipText: "Dismiss"
        onClicked: root.errorDismissed = true
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
