import QtQuick
import qs.Commons
import "Store.js" as Model
import "Stash.js" as Stash

// The only place that reads or writes shell.json, the registry and the bar layout.
QtObject {
  id: store

  property string moduleName: ""
  property var shell: null

  // While the manager is open, model changes are written but the bar is left
  // alone: touching bar.layout makes the bar rebuild every widget, which
  // destroys this one and takes the open dialog with it. Reconcile applies the
  // whole editing session to the bar in one pass once the dialog closes.
  property bool deferLayout: false
  onDeferLayoutChanged: if (!deferLayout) scheduleReconcile()

  // A container's own slot reads the same state but must never write the bar: one
  // reconciler per monitor is already enough, and N of them would race each other.
  property bool passive: false

  // The bar loads a container's slot from this file by path, not through the registry.
  readonly property string slotSource: {
    var manifest = installed[moduleName]
    var dir = manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    return dir === "" ? "" : dir.replace(/\/$/, "") + "/ContainerButton.qml"
  }

  function slotIdFor(containerId) { return Model.slotId(moduleName, containerId) }

  readonly property var registry: shell && shell.pluginRegistry ? shell.pluginRegistry : null
  readonly property bool ready: !!shell && !!registry
    && typeof shell.mutateShellConfig === "function"

  property string error: ""

  signal persisted(var next)

  // Not the injected settings: the bar hands out an empty one while it rebuilds slots.
  readonly property var configEntry: {
    var config = shell ? shell.shellConfig : null
    var found = Stash.findInLayout(Model.clone(config || {}), moduleName)
    return found.found ? found.entry : ({})
  }

  readonly property var state: Model.normalize(configEntry, moduleName)
  readonly property var containers: state.containers

  onConfigEntryChanged: scheduleReconcile()

  // A slot dragged along the bar rewrites no entry of ours, so watch the order itself.
  readonly property string slotOrder: {
    var config = passive || !shell ? null : shell.shellConfig
    return config ? Stash.containerSlotIds(Model.clone(config), moduleName).join(" ") : ""
  }

  onSlotOrderChanged: scheduleReconcile()
  readonly property int containerCount: state.containers.length

  function containerById(id) { return Model.containerById(state, id) }
  function holderCount(pluginId) { return Model.holderCount(state, pluginId) }

  // installedPlugins is a plain object, so reassigning it does not notify on its own.
  property int catalogueRevision: 0

  readonly property var installed: {
    var unused = catalogueRevision
    return registry && registry.installedPlugins ? registry.installedPlugins : ({})
  }

  // Enabled state is deliberately ignored: the picker lists everything installed.
  readonly property var catalogue: {
    var out = []
    var plugins = installed
    for (var id in plugins) {
      var manifest = plugins[id]
      if (!manifest || !Array.isArray(manifest.kinds)) continue
      if (id === moduleName) continue
      if (manifest.kinds.indexOf("bar-widget") === -1) continue
      if (manifest.kinds.indexOf("bar") !== -1) continue
      if (!manifest.entryPoints || !manifest.entryPoints.barWidget) continue

      var meta = manifest.barWidget && typeof manifest.barWidget === "object" ? manifest.barWidget : {}
      out.push({
        id: id,
        name: String(meta.displayName || manifest.name || id),
        description: String(meta.description || manifest.description || ""),
        category: String(meta.category || "Plugin"),
        firstParty: manifest.__isFirstParty === true
      })
    }
    out.sort(function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1 })
    return out
  }

  readonly property var hostableIds: {
    var map = {}
    for (var i = 0; i < catalogue.length; i++) map[catalogue[i].id] = true
    return map
  }

  function pluginInfo(pluginId) {
    for (var i = 0; i < catalogue.length; i++) {
      if (catalogue[i].id === pluginId) return catalogue[i]
    }
    return { id: pluginId, name: pluginId, description: "", category: "", firstParty: false }
  }

  // Not BarWidgetRegistry: it drops a component the moment the plugin leaves shell.json.
  function entryUrlFor(pluginId) {
    if (!registry || typeof registry.entryPointUrl !== "function") return ""
    var manifest = installed[pluginId]
    if (!manifest) return ""
    return registry.entryPointUrl(manifest, "barWidget")
  }

  // Restore target for a plugin that was already off the bar when a container claimed it.
  function defaultSectionFor(pluginId) {
    var manifest = installed[pluginId]
    if (registry && typeof registry.defaultBarWidgetSection === "function")
      return registry.defaultBarWidgetSection(manifest)
    return "right"
  }

  function settingsFor(pluginId) {
    var record = state.stashed[pluginId]
    return record && record.entry ? record.entry : { id: pluginId }
  }

  // A layout change and the state describing it go into one shell.json write.
  function commit(nextState, mutator) {
    if (!ready) {
      store.error = "the shell did not expose mutateShellConfig; state was not saved"
      return false
    }
    var payload = null
    var wrote = false
    shell.mutateShellConfig(function (config) {
      // After the mutator: it finishes filling in nextState from this config.
      if (mutator) mutator(config)
      payload = Model.toEntry(nextState, moduleName)
      wrote = Stash.writeSelf(config, moduleName, payload)
    })
    if (!wrote) {
      // Not in the layout - being removed, or shell.json changed underneath us.
      store.error = "could not find this widget in the bar layout; state was not saved"
      return false
    }
    store.error = ""
    store.persisted(payload)
    return true
  }

  function createContainer(name, icon) {
    var result = Model.addContainer(state, name, icon)
    commit(result.state, null)
    return result.id
  }

  function updateContainer(id, name, icon) {
    commit(Model.updateContainer(state, id, name, icon), null)
  }

  // Never uninstalls: plugins no other container holds go back to the bar.
  function deleteContainer(id) {
    var result = Model.removeContainer(state, id)
    var next = result.state
    if (deferLayout) {
      commit(next, null)
      return
    }
    var released = result.released
    commit(next, function (config) {
      var records = {}
      for (var i = 0; i < released.length; i++) {
        records[released[i]] = next.stashed[released[i]]
        delete next.stashed[released[i]]
      }
      Stash.restoreMany(config, records)
    })
  }

  function addPlugin(containerId, pluginId) {
    if (!hostableIds[pluginId]) return
    var result = Model.addMember(state, containerId, pluginId)
    // Already stashed by another container, or deferred: nothing to take off the bar.
    if (!result.claimed || deferLayout) {
      commit(result.state, null)
      return
    }
    var next = result.state
    var section = defaultSectionFor(pluginId)
    commit(next, function (config) {
      next.stashed[pluginId] = Stash.stash(config, pluginId, section)
    })
  }

  function removePlugin(containerId, pluginId) {
    var result = Model.removeMember(state, containerId, pluginId)
    // Another container still holds it, or deferred: the stash record stands.
    if (!result.released || deferLayout) {
      commit(result.state, null)
      return
    }
    var next = result.state
    var record = next.stashed[pluginId]
    delete next.stashed[pluginId]
    commit(next, function (config) {
      Stash.restore(config, pluginId, record)
    })
  }

  function movePlugin(containerId, pluginId, toIndex) {
    commit(Model.moveMember(state, containerId, pluginId, toIndex), null)
  }

  // Containers are kept: this is the escape hatch before uninstalling, not a reset.
  function restoreAll() {
    var next = Model.clone(state)
    var records = next.stashed
    next.stashed = {}
    for (var i = 0; i < next.containers.length; i++) next.containers[i].members = []
    commit(next, function (config) {
      Stash.restoreMany(config, records)
    })
  }

  // updateEntryInline cannot find a stashed plugin, so the proxy shell routes writes here.
  function writeHostedSettings(pluginId, settings) {
    if (Model.holderCount(state, pluginId) === 0) return false
    var next = Model.clone(state)
    next.stashed[pluginId] = Stash.mergeEntry(next.stashed[pluginId], pluginId, settings)
    if (Model.equal(next.stashed[pluginId], state.stashed[pluginId])) return false
    return commit(next, null)
  }

  // prune drops members missing from the catalogue, so never run before the first scan.
  readonly property bool scanned: !!registry && registry.scanning !== true && catalogue.length > 0

  // One stash causes a write, reload, rebuild and re-inject on every monitor; settle first.
  property Timer reconcileTimer: Timer {
    interval: 250
    onTriggered: store.reconcile()
  }

  function scheduleReconcile() {
    if (!ready || !scanned || deferLayout || passive) return
    reconcileTimer.restart()
  }

  onScannedChanged: if (scanned) scheduleReconcile()

  function containerOrderIn(config) {
    var slots = Stash.containerSlotIds(config, moduleName)
    var ids = []
    for (var i = 0; i < slots.length; i++) ids.push(Model.slotContainerId(moduleName, slots[i]))
    return ids
  }

  // Re-syncs the model with the bar after a rescan or an outside edit; idempotent.
  function reconcile() {
    if (!ready || !scanned || deferLayout || passive) return

    var pruned = Model.prune(state, hostableIds)
    var next = pruned.state
    var reclaim = []

    // Anything a container still holds must not also be on the bar.
    var members = Model.allMembers(next)
    for (var i = 0; i < members.length; i++) {
      if (!next.stashed[members[i]]) reclaim.push(members[i])
    }

    var config = Model.clone(shell.shellConfig || {})
    var strays = []
    for (var m = 0; m < members.length; m++) {
      if (Stash.findInLayout(Model.clone(config), members[m]).found) strays.push(members[m])
    }

    // Nothing to place the slots against until the registry has told us where we live.
    var slotsOk = slotSource === ""
      || Stash.slotsInSync(config, moduleName, Model.slotIds(next, moduleName), slotSource)
    if (slotsOk) next = Model.orderContainers(next, containerOrderIn(config))

    if (slotsOk && Model.equal(next, state) && reclaim.length === 0 && strays.length === 0) return

    commit(next, function (cfg) {
      // One pass, so every recorded position is relative to the same layout.
      var take = strays.slice()
      for (var r = 0; r < reclaim.length; r++) {
        if (take.indexOf(reclaim[r]) === -1) take.push(reclaim[r])
      }
      // A stray's fresh record wins: wherever the user just put it is where it goes back.
      var taken = Stash.stashMany(cfg, take, defaultSectionFor)
      for (var t in taken) next.stashed[t] = taken[t]

      // Anything pruned out that nothing holds any more goes back on the bar.
      var give = {}
      for (var d = 0; d < pruned.droppedStash.length; d++) {
        var id = pruned.droppedStash[d]
        if (Model.holderCount(next, id) > 0) continue
        give[id] = state.stashed[id]
      }
      Stash.restoreMany(cfg, give)

      // After the stashing, so a slot lands beside the entries this pass leaves behind.
      Stash.syncSlots(cfg, moduleName, Model.slotIds(next, moduleName), slotSource)
      next.containers = Model.orderContainers(next, store.containerOrderIn(cfg)).containers
    })
  }
}
