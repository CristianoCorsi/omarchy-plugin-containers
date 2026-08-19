.pragma library

// Pure state helpers: take a state object, return a new one. No QML, no I/O.

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

// Repairs anything: fresh install, hand-edited shell.json, an older version's state.
function normalize(settings, selfId) {
  var source = isObject(settings) ? settings : {}
  var containers = []
  var seenIds = {}
  var rawContainers = Array.isArray(source.containers) ? source.containers : []

  for (var i = 0; i < rawContainers.length; i++) {
    var raw = rawContainers[i]
    if (!isObject(raw)) continue
    var id = String(raw.id || "")
    if (!id || seenIds[id]) continue
    seenIds[id] = true

    var members = []
    var seenMembers = {}
    var rawMembers = Array.isArray(raw.members) ? raw.members : []
    for (var m = 0; m < rawMembers.length; m++) {
      var pluginId = String(rawMembers[m] || "")
      // Self-membership would recurse; a duplicate gives one plugin two live IpcHandlers.
      if (!pluginId || pluginId === selfId || seenMembers[pluginId]) continue
      seenMembers[pluginId] = true
      members.push(pluginId)
    }

    containers.push({
      id: id,
      name: String(raw.name || "").trim() || "Container",
      icon: String(raw.icon || ""),
      members: members
    })
  }

  var stashed = {}
  var rawStashed = isObject(source.stashed) ? source.stashed : {}
  for (var key in rawStashed) {
    var record = rawStashed[key]
    if (!isObject(record)) continue
    stashed[key] = {
      inBar: record.inBar === true,
      section: ["left", "center", "right"].indexOf(String(record.section || "")) !== -1
        ? String(record.section) : "right",
      index: Math.max(0, Math.floor(Number(record.index)) || 0),
      entry: isObject(record.entry) ? clone(record.entry) : { id: key }
    }
  }

  return { containers: containers, stashed: stashed }
}

function toEntry(state, moduleName) {
  return {
    id: moduleName,
    containers: clone(state.containers),
    stashed: clone(state.stashed)
  }
}

function containerById(state, id) {
  for (var i = 0; i < state.containers.length; i++) {
    if (state.containers[i].id === id) return state.containers[i]
  }
  return null
}

function containerIndex(state, id) {
  for (var i = 0; i < state.containers.length; i++) {
    if (state.containers[i].id === id) return i
  }
  return -1
}

// Refcount: a plugin leaves the bar at 0 -> 1 and comes back at 1 -> 0.
function holderCount(state, pluginId) {
  var count = 0
  for (var i = 0; i < state.containers.length; i++) {
    if (state.containers[i].members.indexOf(pluginId) !== -1) count++
  }
  return count
}

function allMembers(state) {
  var seen = {}
  var out = []
  for (var i = 0; i < state.containers.length; i++) {
    var members = state.containers[i].members
    for (var m = 0; m < members.length; m++) {
      if (seen[members[m]]) continue
      seen[members[m]] = true
      out.push(members[m])
    }
  }
  return out
}

// A counter, not a random id, so shell.json stays readable.
function nextContainerId(state) {
  var n = 1
  while (containerById(state, "c" + n) !== null) n++
  return "c" + n
}

function uniqueName(state, base, exceptId) {
  var wanted = String(base || "").trim() || "Container"
  var candidate = wanted
  var n = 2
  while (true) {
    var clash = false
    for (var i = 0; i < state.containers.length; i++) {
      var c = state.containers[i]
      if (c.id !== exceptId && c.name.toLowerCase() === candidate.toLowerCase()) clash = true
    }
    if (!clash) return candidate
    candidate = wanted + " " + n
    n++
  }
}

function addContainer(state, name, icon) {
  var next = clone(state)
  var id = nextContainerId(next)
  next.containers.push({
    id: id,
    name: uniqueName(next, name),
    icon: String(icon || ""),
    members: []
  })
  return { state: next, id: id }
}

function updateContainer(state, id, name, icon) {
  var next = clone(state)
  var container = containerById(next, id)
  if (!container) return next
  if (name !== undefined && name !== null) container.name = uniqueName(next, name, id)
  if (icon !== undefined && icon !== null) container.icon = String(icon)
  return next
}

// Returns the plugins nothing holds any more; deleting a container deletes no plugin.
function removeContainer(state, id) {
  var next = clone(state)
  var index = containerIndex(next, id)
  if (index === -1) return { state: next, released: [] }
  var members = next.containers[index].members.slice()
  next.containers.splice(index, 1)
  var released = []
  for (var i = 0; i < members.length; i++) {
    if (holderCount(next, members[i]) === 0) released.push(members[i])
  }
  return { state: next, released: released }
}

// Every container owns a bar entry of its own, named after the container it draws.
function slotId(moduleName, containerId) {
  return String(moduleName) + "." + String(containerId)
}

function slotContainerId(moduleName, id) {
  var prefix = String(moduleName) + "."
  var value = String(id || "")
  return value.indexOf(prefix) === 0 ? value.substring(prefix.length) : ""
}

function slotIds(state, moduleName) {
  var out = []
  for (var i = 0; i < state.containers.length; i++) {
    out.push(slotId(moduleName, state.containers[i].id))
  }
  return out
}

// The bar is where containers are reordered now, so the model follows the slots.
function orderContainers(state, containerIds) {
  var next = clone(state)
  var rank = {}
  for (var i = 0; i < containerIds.length; i++) {
    if (rank[containerIds[i]] === undefined) rank[containerIds[i]] = i
  }
  var indexed = []
  for (var c = 0; c < next.containers.length; c++) {
    var at = rank[next.containers[c].id]
    // A container with no slot yet keeps its place behind the ones that have one.
    indexed.push({ at: at === undefined ? containerIds.length + c : at, container: next.containers[c] })
  }
  indexed.sort(function (left, right) { return left.at - right.at })
  var out = []
  for (var k = 0; k < indexed.length; k++) out.push(indexed[k].container)
  next.containers = out
  return next
}

// `claimed` means the caller must take the plugin off the bar.
function addMember(state, containerId, pluginId) {
  var next = clone(state)
  var container = containerById(next, containerId)
  if (!container || !pluginId) return { state: next, claimed: false }
  if (container.members.indexOf(pluginId) !== -1) return { state: next, claimed: false }
  var claimed = holderCount(next, pluginId) === 0
  container.members.push(pluginId)
  return { state: next, claimed: claimed }
}

// `released` means the caller must put the plugin back on the bar.
function removeMember(state, containerId, pluginId) {
  var next = clone(state)
  var container = containerById(next, containerId)
  if (!container) return { state: next, released: false }
  var at = container.members.indexOf(pluginId)
  if (at === -1) return { state: next, released: false }
  container.members.splice(at, 1)
  return { state: next, released: holderCount(next, pluginId) === 0 }
}

function moveMember(state, containerId, pluginId, toIndex) {
  var next = clone(state)
  var container = containerById(next, containerId)
  if (!container) return next
  var from = container.members.indexOf(pluginId)
  if (from === -1) return next
  var to = Math.max(0, Math.min(container.members.length - 1, Math.floor(toIndex)))
  if (to === from) return next
  container.members.splice(from, 1)
  container.members.splice(to, 0, pluginId)
  return next
}

// Drops members whose plugin is gone and stash records nothing holds any more.
function prune(state, hostable) {
  var next = clone(state)
  var droppedMembers = []
  for (var i = 0; i < next.containers.length; i++) {
    var container = next.containers[i]
    var kept = []
    for (var m = 0; m < container.members.length; m++) {
      var pluginId = container.members[m]
      if (hostable[pluginId]) kept.push(pluginId)
      else if (droppedMembers.indexOf(pluginId) === -1) droppedMembers.push(pluginId)
    }
    container.members = kept
  }

  var droppedStash = []
  for (var key in next.stashed) {
    if (holderCount(next, key) === 0) {
      droppedStash.push(key)
      delete next.stashed[key]
    }
  }

  return { state: next, droppedMembers: droppedMembers, droppedStash: droppedStash }
}

function equal(left, right) {
  return JSON.stringify(left) === JSON.stringify(right)
}
