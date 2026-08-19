import QtQuick

// The `shell` a hosted plugin sees: the real one, with settings writes intercepted.
QtObject {
  id: proxy

  property var shell: null
  property var store: null

  // A hosted plugin names its own module, so writes are held to this container's members.
  property var members: []

  readonly property var pluginRegistry: shell ? shell.pluginRegistry : null
  readonly property var barWidgetRegistry: shell ? shell.barWidgetRegistry : null
  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property var shellConfig: shell ? shell.shellConfig : null
  readonly property var barConfig: shell ? shell.barConfig : null
  readonly property var bar: shell ? shell.bar : null
  readonly property string omarchyPath: shell ? shell.omarchyPath : ""
  readonly property string shellPath: shell ? shell.shellPath : ""
  readonly property string userConfigPath: shell ? shell.userConfigPath : ""
  readonly property string home: shell ? shell.home : ""

  function mutateShellConfig(mutator) { return proxy.shell.mutateShellConfig(mutator) }
  function persistShellConfig(next) { return proxy.shell.persistShellConfig(next) }
  function serviceFor(pluginId) { return proxy.shell.serviceFor(pluginId) }
  function firstPartyServiceFor(pluginId) { return proxy.shell.firstPartyServiceFor(pluginId) }
  function summon(pluginId, payloadJson) { return proxy.shell.summon(pluginId, payloadJson) }
  function hide(pluginId) { return proxy.shell.hide(pluginId) }
  function toggle(pluginId, payloadJson) { return proxy.shell.toggle(pluginId, payloadJson) }
  function isPluginOpen(pluginId) { return proxy.shell.isPluginOpen(pluginId) }
  function callIfLoaded(pluginId, method, arg) { return proxy.shell.callIfLoaded(pluginId, method, arg) }
  function invokeIfLoaded(pluginId, method, arg) { return proxy.shell.invokeIfLoaded(pluginId, method, arg) }
  function imagePickerItem() { return proxy.shell.imagePickerItem() }

  // updateEntryInline would silently drop a write for a plugin that is not in the layout.

  function updateEntryInline(moduleName, settings) {
    if (!proxy.store) return false
    var id = String(moduleName)
    if ((proxy.members || []).indexOf(id) === -1) return false
    return proxy.store.writeHostedSettings(id, settings)
  }
}
