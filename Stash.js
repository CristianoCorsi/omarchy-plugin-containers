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
// What a layout entry carries decides what the bar makes of it: a `source` is loaded as
// QML and an `exec` is run through `bash -lc`, both by the bar itself once the entry goes
// back. None of them is a hosted widget's to write, so the recorded ones are kept and no
// settings write may introduce one.
var ENTRY_KEYS = ["source", "type", "exec", "onClick", "onRightClick", "onMiddleClick"]

function mergeEntry(record, pluginId, settings) {
  var next = isObject(record) ? clone(record) : { inBar: false, section: "right", index: 0 }
  var entry = { id: pluginId }
  var previous = isObject(next.entry) ? next.entry : null
  for (var k = 0; k < ENTRY_KEYS.length; k++) {
    var kept = ENTRY_KEYS[k]
    if (previous && previous[kept] !== undefined) entry[kept] = previous[kept]
  }
  for (var key in settings) {
    if (key === "id" || ENTRY_KEYS.indexOf(key) !== -1) continue
    entry[key] = settings[key]
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

// Every layout entry in bar order, which is where the custom modules are found.
function allEntries(config) {
  ensureShape(config)
  var out = []
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = config.bar.layout[SECTIONS[s]]
    for (var i = 0; i < entries.length; i++) out.push(entries[i])
  }
  return out
}

function entryIdOf(entry) {
  return isObject(entry) ? String(entry.id || "") : String(entry || "")
}

function slotPrefix(moduleName) {
  return String(moduleName) + "."
}

// Slot ids in the order the bar draws them, which is the order the manager lists them in.
function containerSlotIds(config, moduleName) {
  ensureShape(config)
  var prefix = slotPrefix(moduleName)
  var out = []
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = config.bar.layout[SECTIONS[s]]
    for (var i = 0; i < entries.length; i++) {
      var id = entryIdOf(entries[i])
      if (id.indexOf(prefix) === 0 && out.indexOf(id) === -1) out.push(id)
    }
  }
  return out
}

function slotsInSync(config, moduleName, wantedIds, sourcePath) {
  var present = containerSlotIds(config, moduleName)
  if (present.length !== wantedIds.length) return false
  for (var i = 0; i < wantedIds.length; i++) {
    var at = findInLayout(config, wantedIds[i])
    if (!at.found || String(at.entry.source || "") !== String(sourcePath)) return false
  }
  return true
}

// A container gets its own bar entry, so the bar gives it a slot, an open mark and a drag
// handle of its own. Entries already placed are never moved: that is the user's to decide.
function syncSlots(config, moduleName, wantedIds, sourcePath) {
  ensureShape(config)
  if (!findInLayout(config, moduleName).found || !sourcePath) return false

  var prefix = slotPrefix(moduleName)
  var wanted = {}
  for (var w = 0; w < wantedIds.length; w++) wanted[wantedIds[w]] = true
  var changed = false
  var seen = {}

  // Orphans and hand-edited duplicates go first, or the survivors shift under the insertions.
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = config.bar.layout[SECTIONS[s]]
    var kept = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryIdOf(entries[i])
      if (id.indexOf(prefix) !== 0) { kept.push(entries[i]); continue }
      if (!wanted[id] || seen[id]) { changed = true; continue }
      seen[id] = true
      kept.push(entries[i])
    }
    if (kept.length !== entries.length) config.bar.layout[SECTIONS[s]] = kept
  }

  for (var k = 0; k < wantedIds.length; k++) {
    var slot = wantedIds[k]
    var at = findInLayout(config, slot)
    if (at.found) {
      // The plugin can be reinstalled somewhere else; the entry has to follow the file.
      if (String(at.entry.source || "") !== String(sourcePath)) {
        at.entry.source = String(sourcePath)
        changed = true
      }
      continue
    }
    var previous = k > 0 ? findInLayout(config, wantedIds[k - 1]) : { found: false }
    var after = previous.found ? previous : findInLayout(config, moduleName)
    config.bar.layout[after.section].splice(after.index + 1, 0, {
      id: slot,
      source: String(sourcePath)
    })
    changed = true
  }

  return changed
}

// syncSlots never moves a placed entry, so a reorder made in the manager is written by
// permuting our slots among the seats they already hold. Foreign entries keep their exact
// index; a container can cross a section boundary, because that is what moving past a
// neighbour in the other section means.
function reorderSlots(config, moduleName, wantedIds, sourcePath) {
  ensureShape(config)
  var wanted = String(sourcePath || "")
  if (wanted === "") return false
  var prefix = slotPrefix(moduleName)

  var seats = []
  var owned = {}
  var ownedCount = 0
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = config.bar.layout[SECTIONS[s]]
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var id = entryIdOf(entry)
      if (id.indexOf(prefix) !== 0) continue
      if (String(isObject(entry) ? entry.source || "" : "") !== wanted) continue
      seats.push({ section: SECTIONS[s], index: i })
      if (owned[id] === undefined) ownedCount++
      owned[id] = entry
    }
  }
  // A hand-edited duplicate makes the seats and the entries disagree; syncSlots prunes it.
  if (seats.length !== ownedCount) return false

  var order = []
  for (var w = 0; w < wantedIds.length; w++) {
    if (owned[wantedIds[w]] && order.indexOf(wantedIds[w]) === -1) order.push(wantedIds[w])
  }
  // A slot the model does not know about yet keeps a seat rather than being dropped here.
  for (var key in owned) {
    if (order.indexOf(key) === -1) order.push(key)
  }
  if (order.length !== seats.length) return false

  var changed = false
  for (var t = 0; t < seats.length; t++) {
    var seat = seats[t]
    var next = owned[order[t]]
    if (config.bar.layout[seat.section][seat.index] === next) continue
    config.bar.layout[seat.section][seat.index] = next
    changed = true
  }
  return changed
}

// Every slot this plugin owns, whatever the model says: syncSlots refuses to run once
// our own entry is gone, which is exactly the case when the plugin is being removed.
// The prefix alone is not enough to identify one: a bar entry id is hand-editable and its
// prefix is what names the owner, so `omarchy.c1` would aim this at every omarchy widget.
// Only entries loaded from the same file as the caller are ours to delete.
function dropSlots(config, moduleName, sourcePath) {
  ensureShape(config)
  var wanted = String(sourcePath || "")
  if (wanted === "") return 0
  var prefix = slotPrefix(moduleName)
  var removed = 0
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = config.bar.layout[SECTIONS[s]]
    var kept = []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (entryIdOf(entry).indexOf(prefix) !== 0
          || String(isObject(entry) ? entry.source || "" : "") !== wanted) {
        kept.push(entry)
        continue
      }
      removed++
    }
    if (kept.length !== entries.length) config.bar.layout[SECTIONS[s]] = kept
  }
  return removed
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
