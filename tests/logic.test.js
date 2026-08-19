// Tests for the pure state logic. Run with tests/run.sh.

const fs = require("fs")
const path = require("path")
const vm = require("vm")

function load(name) {
  const file = path.join(__dirname, "..", name)
  const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "")
  const sandbox = {}
  vm.createContext(sandbox)
  vm.runInContext(source, sandbox, { filename: file })
  return sandbox
}

const Store = load("Store.js")
const Stash = load("Stash.js")
const SELF = "leyanora.plugincontainers"

let failures = 0
let checks = 0

function check(label, actual, expected) {
  checks++
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a === e) return
  failures++
  console.error(`FAIL ${label}\n  expected ${e}\n  actual   ${a}`)
}

function ok(label, value) {
  check(label, value === true, true)
}

check("normalize of nothing", Store.normalize(undefined, SELF), { containers: [], stashed: {} })

check("normalize drops junk containers",
  Store.normalize({ containers: [null, 7, { name: "no id" }, { id: "c1", name: "net" }] }, SELF).containers,
  [{ id: "c1", name: "net", icon: "", members: [] }])

check("normalize drops duplicate container ids",
  Store.normalize({ containers: [{ id: "c1", name: "a" }, { id: "c1", name: "b" }] }, SELF).containers.length, 1)

check("normalize refuses self-membership",
  Store.normalize({ containers: [{ id: "c1", name: "n", members: [SELF, "omarchy.tailscale"] }] }, SELF)
    .containers[0].members,
  ["omarchy.tailscale"])

check("normalize dedups members within a container",
  Store.normalize({ containers: [{ id: "c1", name: "n", members: ["a", "a", "b"] }] }, SELF)
    .containers[0].members,
  ["a", "b"])

check("normalize falls back on a blank name",
  Store.normalize({ containers: [{ id: "c1", name: "   " }] }, SELF).containers[0].name, "Container")

check("normalize repairs a bad stash section",
  Store.normalize({ stashed: { a: { inBar: true, section: "nowhere", index: -3 } } }, SELF).stashed.a,
  { inBar: true, section: "right", index: 0, entry: { id: "a" } })

let s = Store.normalize({}, SELF)
const created = Store.addContainer(s, "network", "X")
s = created.state
check("addContainer assigns c1", created.id, "c1")
check("addContainer stores name and icon", s.containers[0], { id: "c1", name: "network", icon: "X", members: [] })

s = Store.addContainer(s, "network").state
check("addContainer disambiguates a duplicate name", s.containers[1].name, "network 2")
check("addContainer assigns the next free id", s.containers[1].id, "c2")

s = Store.updateContainer(s, "c2", "media", "Y")
check("updateContainer renames", s.containers[1].name, "media")
check("updateContainer re-icons", s.containers[1].icon, "Y")

s = Store.updateContainer(s, "c2", "network")
check("updateContainer disambiguates against other containers", s.containers[1].name, "network 2")

s = Store.addContainer(s, "third").state
check("order before move", s.containers.map(c => c.id), ["c1", "c2", "c3"])
s = Store.moveContainer(s, "c3", -1)
check("moveContainer up", s.containers.map(c => c.id), ["c1", "c3", "c2"])
s = Store.moveContainer(s, "c1", -1)
check("moveContainer clamps at the start", s.containers.map(c => c.id), ["c1", "c3", "c2"])
s = Store.moveContainer(s, "c1", +5)
check("moveContainer clamps at the end", s.containers.map(c => c.id), ["c3", "c2", "c1"])

s = Store.normalize({}, SELF)
s = Store.addContainer(s, "network").state   // c1
s = Store.addContainer(s, "vpn").state       // c2

let r = Store.addMember(s, "c1", "omarchy.tailscale")
s = r.state
ok("first container to hold a plugin claims it", r.claimed)

r = Store.addMember(s, "c2", "omarchy.tailscale")
s = r.state
check("second container does not re-claim", r.claimed, false)
check("a plugin may sit in two containers", Store.holderCount(s, "omarchy.tailscale"), 2)

r = Store.addMember(s, "c1", "omarchy.tailscale")
check("re-adding an existing member is a no-op", r.claimed, false)
check("re-adding does not duplicate", Store.containerById(r.state, "c1").members.length, 1)

r = Store.removeMember(s, "c1", "omarchy.tailscale")
s = r.state
check("removing one of two holders does not release", r.released, false)

r = Store.removeMember(s, "c2", "omarchy.tailscale")
s = r.state
ok("removing the last holder releases", r.released)
check("removing an absent member is a no-op", Store.removeMember(s, "c1", "nope").released, false)

// deleting a container releases only what nothing else holds
s = Store.normalize({}, SELF)
s = Store.addContainer(s, "a").state
s = Store.addContainer(s, "b").state
s = Store.addMember(s, "c1", "shared").state
s = Store.addMember(s, "c2", "shared").state
s = Store.addMember(s, "c1", "lonely").state
r = Store.removeContainer(s, "c1")
check("removeContainer releases only unheld plugins", r.released, ["lonely"])
check("removeContainer drops the container", r.state.containers.map(c => c.id), ["c2"])

// member reordering
s = Store.normalize({ containers: [{ id: "c1", name: "n", members: ["a", "b", "c"] }] }, SELF)
check("moveMember to the front", Store.moveMember(s, "c1", "c", 0).containers[0].members, ["c", "a", "b"])
check("moveMember to the end", Store.moveMember(s, "c1", "a", 2).containers[0].members, ["b", "c", "a"])
check("moveMember clamps out-of-range", Store.moveMember(s, "c1", "a", 99).containers[0].members, ["b", "c", "a"])

check("allMembers is unique and ordered",
  Store.allMembers(Store.normalize({ containers: [
    { id: "c1", name: "a", members: ["x", "y"] },
    { id: "c2", name: "b", members: ["y", "z"] }
  ] }, SELF)), ["x", "y", "z"])

s = Store.normalize({
  containers: [{ id: "c1", name: "n", members: ["kept", "gone"] }],
  stashed: {
    kept: { inBar: true, section: "right", index: 2 },
    gone: { inBar: true, section: "right", index: 3 },
    orphan: { inBar: true, section: "left", index: 0 }
  }
}, SELF)
r = Store.prune(s, { kept: true })
check("prune drops uninstalled members", r.state.containers[0].members, ["kept"])
check("prune reports dropped members", r.droppedMembers, ["gone"])
check("prune drops unheld stash records", Object.keys(r.state.stashed), ["kept"])
check("prune reports dropped stash records", r.droppedStash.sort(), ["gone", "orphan"])

function layout(right) {
  return { bar: { layout: { left: [], center: [], right: right } } }
}

let config = layout([
  { id: "omarchy.tray" },
  { id: "omarchy.tailscale", refreshIntervalSec: 30 },
  { id: "omarchy.audio" }
])
let record = Stash.stash(config, "omarchy.tailscale", "right")
check("stash records where it was", { inBar: record.inBar, section: record.section, index: record.index },
  { inBar: true, section: "right", index: 1 })
check("stash keeps the whole entry, settings included", record.entry,
  { id: "omarchy.tailscale", refreshIntervalSec: 30 })
check("stash takes it off the bar", config.bar.layout.right.map(e => e.id),
  ["omarchy.tray", "omarchy.audio"])

ok("restore puts it back", Stash.restore(config, "omarchy.tailscale", record))
check("restore lands at the original index", config.bar.layout.right.map(e => e.id),
  ["omarchy.tray", "omarchy.tailscale", "omarchy.audio"])
check("restore keeps the settings", config.bar.layout.right[1].refreshIntervalSec, 30)

// a plugin that was never on the bar stays off
config = layout([{ id: "omarchy.tray" }])
record = Stash.stash(config, "io.example.disabled", "left")
check("stashing an off-bar plugin records inBar false", record.inBar, false)
check("stashing an off-bar plugin changes nothing", config.bar.layout.right.map(e => e.id), ["omarchy.tray"])
check("restoring an off-bar plugin restores nothing", Stash.restore(config, "io.example.disabled", record), false)
check("layout untouched after a no-op restore", config.bar.layout.right.map(e => e.id), ["omarchy.tray"])

// index clamping when the bar shrank underneath
config = layout([{ id: "a" }, { id: "b" }, { id: "c" }, { id: "target" }])
record = Stash.stash(config, "target", "right")
config.bar.layout.right = [{ id: "a" }]
ok("restore into a shrunken section", Stash.restore(config, "target", record))
check("restore clamps the index", config.bar.layout.right.map(e => e.id), ["a", "target"])

// never restore a duplicate
config = layout([{ id: "dup" }])
check("restore refuses when already present",
  Stash.restore(config, "dup", { inBar: true, section: "right", index: 0, entry: { id: "dup" } }), false)
check("layout unchanged after a refused restore", config.bar.layout.right.length, 1)

// a missing section is created rather than crashing
config = { bar: {} }
ok("restore repairs a missing layout", Stash.restore(config, "x", { inBar: true, section: "center", index: 9 }))
check("restore created the section", config.bar.layout.center.map(e => e.id), ["x"])

// hosted settings writes land in the stash record
record = { inBar: true, section: "right", index: 4, entry: { id: "p", a: 1 } }
const merged = Stash.mergeEntry(record, "p", { id: "ignored", a: 2, b: "x" })
check("mergeEntry replaces the entry", merged.entry, { id: "p", a: 2, b: "x" })
check("mergeEntry keeps the restore position", { s: merged.section, i: merged.index, b: merged.inBar },
  { s: "right", i: 4, b: true })
check("mergeEntry does not mutate the original", record.entry, { id: "p", a: 1 })

// positions must be recorded against the original layout, not the shrinking one
config = layout([{ id: "a" }, { id: "one" }, { id: "b" }, { id: "two" }, { id: "c" }])
let records = Stash.stashMany(config, ["one", "two"], () => "right")
check("stashMany records the original index of the first", records.one.index, 1)
check("stashMany records the original index of the second", records.two.index, 3)
check("stashMany removes them all", config.bar.layout.right.map(e => e.id), ["a", "b", "c"])

check("restoreMany puts them back in order", (() => {
  Stash.restoreMany(config, records)
  return config.bar.layout.right.map(e => e.id)
})(), ["a", "one", "b", "two", "c"])

// the same, stashed in the reverse order they appear on the bar
config = layout([{ id: "a" }, { id: "one" }, { id: "b" }, { id: "two" }, { id: "c" }])
records = Stash.stashMany(config, ["two", "one"], () => "right")
check("stashMany is order-independent", [records.one.index, records.two.index], [1, 3])
Stash.restoreMany(config, records)
check("restoreMany is order-independent", config.bar.layout.right.map(e => e.id),
  ["a", "one", "b", "two", "c"])

// mixed: one on the bar, one not
config = layout([{ id: "a" }, { id: "onbar" }])
records = Stash.stashMany(config, ["onbar", "offbar"], () => "center")
check("stashMany marks an absent plugin as off-bar", records.offbar,
  { inBar: false, section: "center", index: 0, entry: { id: "offbar" } })
check("stashMany leaves the layout holding only the untouched entry",
  config.bar.layout.right.map(e => e.id), ["a"])
check("restoreMany skips off-bar records", Stash.restoreMany(config, records), 1)
check("restoreMany restored only the one that was on the bar",
  [config.bar.layout.right.map(e => e.id), config.bar.layout.center.map(e => e.id)],
  [["a", "onbar"], []])

// settings survive a batch round trip
config = layout([{ id: "x", n: 1 }, { id: "y", n: 2 }])
records = Stash.stashMany(config, ["x", "y"], () => "right")
Stash.restoreMany(config, records)
check("batch round trip keeps inline settings", config.bar.layout.right, [{ id: "x", n: 1 }, { id: "y", n: 2 }])

config = layout([{ id: "other" }, { id: "me", old: true }])
ok("writeSelf finds and replaces our entry",
  Stash.writeSelf(config, "me", { id: "me", containers: [], stashed: {} }))
check("writeSelf wrote in place", config.bar.layout.right,
  [{ id: "other" }, { id: "me", containers: [], stashed: {} }])
check("writeSelf reports a widget that is not in the layout",
  Stash.writeSelf(layout([{ id: "other" }]), "me", { id: "me" }), false)

s = Store.normalize({}, SELF)
s = Store.addContainer(s, "network", "B").state
s = Store.addMember(s, "c1", "omarchy.tailscale").state
const entry = Store.toEntry(s, SELF)
check("toEntry carries the id", entry.id, SELF)
check("state survives a JSON round trip",
  Store.normalize(JSON.parse(JSON.stringify(entry)), SELF), s)

console.log(`${checks - failures}/${checks} checks passed`)
process.exit(failures === 0 ? 0 : 1)
