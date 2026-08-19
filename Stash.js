.pragma library

// Takes a plugin off the bar and puts it back exactly as it was, mutating a config copy.

var SECTIONS = ["left", "center", "right"]

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

// shell.json is user-editable, so no shape is guaranteed.
function ensureShape(config) {
  if (!isObject(config.bar)) config.bar = {}
  if (!isObject(config.bar.layout)) config.bar.layout = {}
  for (var i = 0; i < SECTIONS.length; i++) {
    if (!Array.isArray(config.bar.layout[SECTIONS[i]])) config.bar.layout[SECTIONS[i]] = []
  }
  return config
}

function findInLayout(config, pluginId) {
  ensureShape(config)
  for (var s = 0; s < SECTIONS.length; s++) {
    var section = SECTIONS[s]
    var entries = config.bar.layout[section]
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (isObject(entry) && String(entry.id || "") === pluginId) {
        return { found: true, section: section, index: i, entry: entry }
      }
    }
  }
  return { found: false }
}

// `inBar: false` records a plugin that was already off the bar, so restore leaves it off.
function stash(config, pluginId, defaultSection) {
  var location = findInLayout(config, pluginId)
  if (!location.found) {
    return {
      inBar: false,
      section: defaultSection || "right",
      index: 0,
      entry: { id: pluginId }
    }
  }
  config.bar.layout[location.section].splice(location.index, 1)
  return {
    inBar: true,
    section: location.section,
    index: location.index,
    entry: clone(location.entry)
  }
}

// The saved index is a hint: the section may have changed size, so it is clamped.
function restore(config, pluginId, record) {
  ensureShape(config)
  if (!isObject(record) || record.inBar !== true) return false

  // The user may have re-added it by hand while it was stashed.
  if (findInLayout(config, pluginId).found) return false

  var section = SECTIONS.indexOf(String(record.section || "")) !== -1 ? record.section : "right"
  var entries = config.bar.layout[section]
  var index = Math.max(0, Math.min(entries.length, Math.floor(Number(record.index)) || 0))
  var entry = isObject(record.entry) ? clone(record.entry) : { id: pluginId }
  entry.id = pluginId
  entries.splice(index, 0, entry)
  return true
}

// Routed here because updateEntryInline cannot find a plugin that is not in the layout.
function mergeEntry(record, pluginId, settings) {
  var next = isObject(record) ? clone(record) : { inBar: false, section: "right", index: 0 }
  var entry = { id: pluginId }
  for (var key in settings) {
    if (key !== "id") entry[key] = settings[key]
  }
  next.entry = entry
  return next
}

// So a layout change and the state describing it land in one shell.json write.
function writeSelf(config, moduleName, entry) {
  var location = findInLayout(config, moduleName)
  if (!location.found) return false
  var next = { id: moduleName }
  for (var key in entry) {
    if (key !== "id") next[key] = entry[key]
  }
  config.bar.layout[location.section][location.index] = next
  return true
}

// Positions are read before any removal, or each removal shifts the ones after it.
function stashMany(config, pluginIds, defaultSectionFor) {
  ensureShape(config)
  var records = {}
  var located = []

  for (var i = 0; i < pluginIds.length; i++) {
    var pluginId = pluginIds[i]
    var location = findInLayout(config, pluginId)
    if (location.found) {
      records[pluginId] = {
        inBar: true,
        section: location.section,
        index: location.index,
        entry: clone(location.entry)
      }
      located.push(location)
    } else {
      records[pluginId] = {
        inBar: false,
        section: defaultSectionFor ? defaultSectionFor(pluginId) : "right",
        index: 0,
        entry: { id: pluginId }
      }
    }
  }

  located.sort(function (left, right) { return right.index - left.index })
  for (var r = 0; r < located.length; r++) {
    config.bar.layout[located[r].section].splice(located[r].index, 1)
  }
  return records
}

// Lowest index first, so each insertion makes room for the next.
function restoreMany(config, records) {
  var ids = []
  for (var key in records) {
    if (isObject(records[key]) && records[key].inBar === true) ids.push(key)
  }
  ids.sort(function (left, right) {
    return (Number(records[left].index) || 0) - (Number(records[right].index) || 0)
  })
  var restored = 0
  for (var i = 0; i < ids.length; i++) {
    if (restore(config, ids[i], records[ids[i]])) restored++
  }
  return restored
}
