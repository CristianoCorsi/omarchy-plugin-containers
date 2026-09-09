.pragma library

.import "Layout.js" as Layout
.import "Store.js" as Model

// One-way upgrade from the 1.x bar-widget layout to the 2.0 bar layout, applied to the
// `bar` subtree inside a single mutateShellConfig call. Idempotent: it looks for the old
// shape and does nothing once the shape is gone.

// A 1.x stash record is config data, and this is the one path that turns it back into a
// bar entry. The bar runs an entry carrying these, so they never come out of a record.
var ENTRY_KEYS = ["source", "type", "exec", "onClick", "onRightClick", "onMiddleClick"]

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function safeEntry(entry, pluginId) {
  var out = { id: String(pluginId) }
  if (!isObject(entry)) return out
  for (var key in entry) {
    if (key === "id" || ENTRY_KEYS.indexOf(key) !== -1) continue
    out[key] = entry[key]
  }
  return out
}

function looksKeptAlive(entry, record) {
  if (!isObject(entry)) return false
  var source = String(entry.source || "")
  if (source === "") return false
  var recorded = isObject(record) && isObject(record.keepAlive)
    ? String(record.keepAlive.layoutSource || "") : ""
  if (recorded !== "") return source === recorded
  return source.indexOf("/KeepAliveWidget.qml") === source.length - 20
}

// 1.1.0 took the member out of the bar; 1.1.1 left a placeholder entry in its place.
function restoreMember(barConfig, pluginId, record) {
  var entry = safeEntry(isObject(record) ? record.entry : null, pluginId)

  var at = Layout.locate(barConfig, pluginId)
  if (at.found) {
    if (!looksKeptAlive(at.entry, record)) return false
    barConfig.layout[at.section][at.index] = entry
    return true
  }

  if (record && record.inBar === false) return false
  var section = ["left", "center", "right"].indexOf(String(record && record.section)) !== -1
    ? String(record.section) : "right"
  var entries = Layout.sectionIn(barConfig, section)
  var index = Math.max(0, Math.min(entries.length, Math.floor(Number(record && record.index)) || 0))
  entries.splice(index, 0, entry)
  return true
}

// The 1.x marker entries carried the path the bar loaded ContainerButton.qml from. The
// projection supplies that now, so an absolute path to this checkout stops being config.
function stripSlotSources(barConfig, moduleName) {
  var changed = false
  for (var s = 0; s < Layout.SECTIONS.length; s++) {
    var entries = barConfig.layout ? barConfig.layout[Layout.SECTIONS[s]] : null
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (!isObject(entry) || !Layout.isSlotId(Layout.entryId(entry), moduleName)) continue
      if (entry.source === undefined && entry.type === undefined) continue
      delete entry.source
      delete entry.type
      changed = true
    }
  }
  return changed
}

// Returns true when it changed something, so the caller can skip a pointless write.
function migrate(barConfig, moduleName) {
  var at = Layout.locate(barConfig, moduleName)
  var legacy = at.found && isObject(at.entry) ? at.entry : null
  var hasLegacy = !!legacy
    && (legacy.containers !== undefined || legacy.stashed !== undefined
      || legacy.settings !== undefined)
  var hasBlock = isObject(barConfig[String(moduleName)])
  if (!hasLegacy && hasBlock) return false

  var state = Model.normalize(hasLegacy ? legacy : Layout.readBlock(barConfig, moduleName),
    moduleName)

  if (hasLegacy) {
    var stashed = isObject(legacy.stashed) ? legacy.stashed : {}
    var members = Model.allMembers(state)
    for (var i = 0; i < members.length; i++) restoreMember(barConfig, members[i], stashed[members[i]])
    // A record nothing holds any more still describes a widget taken off the bar.
    for (var key in stashed) {
      if (members.indexOf(key) === -1) restoreMember(barConfig, key, stashed[key])
    }
    delete legacy.containers
    delete legacy.stashed
    delete legacy.settings
  }

  stripSlotSources(barConfig, moduleName)
  var ids = []
  for (var c = 0; c < state.containers.length; c++) ids.push(state.containers[c].id)
  Layout.syncSlots(barConfig, moduleName, ids, "right")
  Layout.writeBlock(barConfig, moduleName, Model.toBlock(state))
  return true
}
