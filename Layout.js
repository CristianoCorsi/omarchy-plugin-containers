.pragma library

// Pure bar-layout helpers: read and rewrite the `bar` subtree of shell.json, and project
// it into the layout the hosted upstream bar actually renders. No QML, no I/O.

var SECTIONS = ["left", "center", "right"]

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function entryId(entry) {
  return String(isObject(entry) ? (entry.id || "") : (entry || ""))
}

function layoutOf(barConfig) {
  var layout = isObject(barConfig) && isObject(barConfig.layout) ? barConfig.layout : {}
  var out = {}
  for (var i = 0; i < SECTIONS.length; i++) {
    var entries = layout[SECTIONS[i]]
    out[SECTIONS[i]] = Array.isArray(entries) ? clone(entries) : []
  }
  return out
}

// Mutates: the caller is inside mutateShellConfig and wants the section it can splice.
function sectionIn(barConfig, section) {
  if (!isObject(barConfig.layout)) barConfig.layout = {}
  var name = SECTIONS.indexOf(String(section)) === -1 ? "right" : String(section)
  if (!Array.isArray(barConfig.layout[name])) barConfig.layout[name] = []
  return barConfig.layout[name]
}

function locate(barConfig, id) {
  var layout = isObject(barConfig) && isObject(barConfig.layout) ? barConfig.layout : {}
  var key = String(id)
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout[SECTIONS[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === key)
        return { found: true, section: SECTIONS[s], index: i, entry: entries[i] }
    }
  }
  return { found: false }
}

function entryFor(barConfig, id) {
  var at = locate(barConfig, id)
  return at.found && isObject(at.entry) ? clone(at.entry) : { id: String(id) }
}

function inLayout(barConfig, id) {
  return locate(barConfig, id).found
}

// State lives beside the layout rather than in our widget's entry: an entry rewrite is a
// structural change to the bar, and rebuilding it destroys whichever surface is open.
function readBlock(barConfig, key) {
  var raw = isObject(barConfig) ? barConfig[String(key)] : null
  return isObject(raw) ? clone(raw) : {}
}

function writeBlock(barConfig, key, block) {
  barConfig[String(key)] = clone(block)
}

function slotPrefix(moduleName) {
  return String(moduleName) + "."
}

function isSlotId(id, moduleName) {
  return String(id).indexOf(slotPrefix(moduleName)) === 0
}

// Bar order is the truth for container order; this is how the model reads it back.
function slotOrder(barConfig, moduleName) {
  var layout = isObject(barConfig) && isObject(barConfig.layout) ? barConfig.layout : {}
  var out = []
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout[SECTIONS[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      if (isSlotId(id, moduleName)) out.push(id.substring(slotPrefix(moduleName).length))
    }
  }
  return out
}

// Adds a marker entry for every container that has none and drops the ones left behind.
// It never moves an existing one: dragging a container along the bar is how it is ordered.
function syncSlots(barConfig, moduleName, containerIds, section) {
  var wanted = {}
  for (var i = 0; i < containerIds.length; i++)
    wanted[slotPrefix(moduleName) + containerIds[i]] = true

  var changed = false
  if (!isObject(barConfig.layout)) barConfig.layout = {}
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = barConfig.layout[SECTIONS[s]]
    if (!Array.isArray(entries)) continue
    for (var e = entries.length - 1; e >= 0; e--) {
      var id = entryId(entries[e])
      if (!isSlotId(id, moduleName) || wanted[id]) continue
      entries.splice(e, 1)
      changed = true
    }
  }

  for (var w in wanted) {
    if (locate(barConfig, w).found) continue
    var target = sectionIn(barConfig, section)
    var self = locate(barConfig, moduleName)
    // Beside the manager's own icon where it has one, so a new container lands in view.
    if (self.found && self.section === String(section)) target.splice(self.index, 0, { id: w })
    else target.push({ id: w })
    changed = true
  }
  return changed
}

function dropSlots(barConfig, moduleName) {
  return syncSlots(barConfig, moduleName, [], "right")
}

// A member has to keep its layout entry: that entry is what keeps the plugin enabled and
// holds its inline settings. Containment only decides whether the bar draws it.
function ensureEntry(barConfig, pluginId, section) {
  if (locate(barConfig, pluginId).found) return false
  sectionIn(barConfig, section).push({ id: String(pluginId) })
  return true
}

function removeEntry(barConfig, pluginId) {
  var at = locate(barConfig, pluginId)
  if (!at.found) return false
  barConfig.layout[at.section].splice(at.index, 1)
  return true
}

function hiddenSet(containers) {
  var out = {}
  for (var i = 0; i < containers.length; i++) {
    var members = containers[i].members || []
    for (var m = 0; m < members.length; m++) out[members[m]] = true
  }
  return out
}

// What the hosted bar is handed: members drop out of the sections and every container
// marker becomes the custom qml module that draws it. Nothing here is written to disk.
function project(barConfig, containers, moduleName, slotSource) {
  var next = isObject(barConfig) ? clone(barConfig) : {}
  var hidden = hiddenSet(containers)
  var known = {}
  for (var c = 0; c < containers.length; c++)
    known[slotPrefix(moduleName) + containers[c].id] = true

  var layout = layoutOf(barConfig)
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout[SECTIONS[s]]
    var kept = []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var id = entryId(entry)
      if (known[id]) {
        kept.push({ id: id, type: "qml", source: String(slotSource) })
        continue
      }
      // A marker whose container is gone would load nothing and collapse to a 0x0 slot.
      if (isSlotId(id, moduleName)) continue
      if (hidden[id]) continue
      kept.push(entry)
    }
    layout[SECTIONS[s]] = kept
  }
  next.layout = layout

  // Anchoring the centre on a widget that is now inside a container leaves it unanchored.
  if (hidden[String(next.centerAnchor || "")]) next.centerAnchor = ""
  return next
}

// A bar entry naming no registered widget is a custom module the user wrote. It can be
// contained like anything else, so the picker has to list it beside the plugins.
function customModules(barConfig, moduleName, registered, moduleTypeOf) {
  var out = []
  var layout = layoutOf(barConfig)
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layout[SECTIONS[s]]
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      if (!id || registered[id] || isSlotId(id, moduleName) || id === String(moduleName)) continue
      if (moduleTypeOf(entries[i]) !== "qml") continue
      out.push({ id: id, entry: clone(entries[i]) })
    }
  }
  return out
}
