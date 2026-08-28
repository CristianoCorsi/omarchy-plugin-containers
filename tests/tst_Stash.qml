import QtQuick
import QtTest
import "../Stash.js" as Stash
import "../Store.js" as Store

TestCase {
  name: "Stash"

  function config(left, center, right) {
    return {
      bar: { layout: {
        left: left || [],
        center: center || [],
        right: right || []
      }},
      plugins: []
    }
  }

  function thirdParty() { return { __isFirstParty: false } }
  function firstParty() { return { __isFirstParty: true } }
  function keepAliveSource() { return "/tmp/KeepAliveWidget.qml" }

  function test_thirdPartyGetsInvisibleLayoutEntryWithSettings() {
    var cfg = config([{ id: "example.plugin", color: "blue" }])
    var record = Stash.stash(cfg, "example.plugin", "right", thirdParty(), keepAliveSource())

    compare(cfg.bar.layout.left.length, 1)
    compare(cfg.bar.layout.left[0].id, "example.plugin")
    compare(cfg.bar.layout.left[0].color, "blue")
    compare(cfg.bar.layout.left[0].source, keepAliveSource())
    compare(cfg.plugins.length, 0)
    verify(record.keepAlive.layoutEntryAdded)

    verify(Stash.restore(cfg, "example.plugin", record))
    verify(cfg.bar.layout.left[0].source === undefined)
    compare(cfg.bar.layout.left[0].id, "example.plugin")
    compare(cfg.bar.layout.left[0].color, "blue")
  }

  function test_existingPluginEntryIsNeverClaimedOrRemoved() {
    var cfg = config([{ id: "example.plugin" }])
    cfg.plugins = [{ id: "example.plugin", userSetting: 7 }]
    var record = Stash.stash(cfg, "example.plugin", "right", thirdParty(), keepAliveSource())

    verify(record.keepAlive.layoutEntryAdded)
    verify(Stash.restore(cfg, "example.plugin", record))
    compare(cfg.plugins.length, 1)
    compare(cfg.plugins[0].userSetting, 7)
  }

  function test_firstPartyDisabledStateIsSuspendedAndRestored() {
    var cfg = config([{ id: "omarchy.example" }])
    cfg.disabledPlugins = ["other.plugin", "omarchy.example"]
    var record = Stash.stash(cfg, "omarchy.example", "right", firstParty(), keepAliveSource())

    compare(cfg.plugins.length, 0)
    compare(cfg.bar.layout.left[0].source, keepAliveSource())
    compare(cfg.disabledPlugins.length, 1)
    compare(cfg.disabledPlugins[0], "other.plugin")
    verify(record.keepAlive.disabledEntryRemoved)

    verify(Stash.restore(cfg, "omarchy.example", record))
    compare(cfg.disabledPlugins.length, 2)
    compare(cfg.disabledPlugins[1], "omarchy.example")
  }

  function test_pluginOriginallyOffBarReturnsToDisabledState() {
    var cfg = config()
    var record = Stash.stash(cfg, "example.plugin", "center", thirdParty(), keepAliveSource())

    verify(!record.inBar)
    compare(cfg.bar.layout.center.length, 1)
    compare(cfg.bar.layout.center[0].source, keepAliveSource())
    verify(!Stash.restore(cfg, "example.plugin", record))
    compare(cfg.plugins.length, 0)
    compare(cfg.bar.layout.center.length, 0)
  }

  function test_customQmlModuleGetsNoRegistryKeepAliveEntry() {
    var cfg = config([{ id: "custom.module", source: "/tmp/custom.qml" }])
    var record = Stash.stash(cfg, "custom.module", "left", null)

    compare(cfg.plugins.length, 0)
    verify(record.keepAlive === undefined)
    verify(Stash.restore(cfg, "custom.module", record))
    compare(cfg.bar.layout.left[0].source, "/tmp/custom.qml")
  }

  function test_sharedMemberReleasesOnlyAfterLastContainer() {
    var state = Store.normalize({
      containers: [
        { id: "c1", name: "One", members: ["example.plugin"] },
        { id: "c2", name: "Two", members: ["example.plugin"] }
      ]
    }, "leyanora.plugincontainers")

    var first = Store.removeMember(state, "c1", "example.plugin")
    verify(!first.released)
    compare(Store.holderCount(first.state, "example.plugin"), 1)

    var last = Store.removeMember(first.state, "c2", "example.plugin")
    verify(last.released)
    compare(Store.holderCount(last.state, "example.plugin"), 0)
  }

  function test_legacyStashIsMigratedInPlace() {
    var cfg = config()
    var records = {
      "example.plugin": {
        inBar: true,
        section: "left",
        index: 0,
        entry: { id: "example.plugin" }
      }
    }

    var migrated = Stash.keepManyEnabled(cfg, records, ["example.plugin"], function (id) {
      return thirdParty()
    }, keepAliveSource())

    compare(cfg.bar.layout.left.length, 1)
    compare(cfg.bar.layout.left[0].source, keepAliveSource())
    verify(migrated["example.plugin"].keepAlive.layoutEntryAdded)

    var repeated = Stash.keepManyEnabled(cfg, migrated, ["example.plugin"], function (id) {
      return thirdParty()
    }, keepAliveSource())
    compare(cfg.bar.layout.left.length, 1)
    verify(repeated["example.plugin"].keepAlive.layoutEntryAdded)
  }

  function test_pluginsArrayKeepAliveMigratesWithoutLosingServiceSettings() {
    var cfg = config()
    cfg.plugins = [{ id: "example.plugin", host: "printer.local", serial: "ABC" }]
    var records = {
      "example.plugin": {
        inBar: true,
        section: "right",
        index: 2,
        entry: { id: "example.plugin", host: "old" },
        keepAlive: { pluginEntryAdded: true }
      }
    }

    var migrated = Stash.keepManyEnabled(cfg, records, ["example.plugin"], function (id) {
      return thirdParty()
    }, keepAliveSource())

    compare(cfg.plugins.length, 0)
    compare(cfg.bar.layout.right.length, 1)
    compare(cfg.bar.layout.right[0].source, keepAliveSource())
    compare(cfg.bar.layout.right[0].host, "printer.local")
    compare(migrated["example.plugin"].entry.serial, "ABC")
    verify(migrated["example.plugin"].keepAlive.pluginEntryAdded === undefined)
    verify(migrated["example.plugin"].keepAlive.layoutEntryAdded)
  }

  function test_serviceSettingsRepairOwnedPlaceholderWhileContained() {
    var cfg = config([{ id: "example.plugin", host: "old", serial: "ABC" }])
    var record = Stash.stash(cfg, "example.plugin", "right", thirdParty(), keepAliveSource())

    // A service can replace its layout entry wholesale through updateEntryInline().
    cfg.bar.layout.left[0] = { id: "example.plugin", host: "new", serial: "XYZ" }
    record = Stash.keepEnabled(cfg, "example.plugin", record, thirdParty(), keepAliveSource())

    compare(record.entry.host, "new")
    compare(record.entry.serial, "XYZ")
    compare(cfg.bar.layout.left[0].host, "new")
    compare(cfg.bar.layout.left[0].source, keepAliveSource())
    verify(Stash.ownsLayoutEntry(record))
  }

  function test_temporarySettingsReturnWithoutExecutableKeys() {
    var cfg = config([{
      id: "example.plugin",
      color: "old",
      onClick: "trusted-command"
    }])
    var record = Stash.stash(cfg, "example.plugin", "right", thirdParty(), keepAliveSource())
    cfg.bar.layout.left[0] = {
      id: "example.plugin",
      color: "new",
      extra: 2,
      source: "/tmp/untrusted.qml",
      exec: "untrusted-command",
      onClick: "untrusted-command"
    }

    verify(Stash.restore(cfg, "example.plugin", record))
    var restored = cfg.bar.layout.left[0]
    compare(restored.color, "new")
    compare(restored.extra, 2)
    compare(restored.onClick, "trusted-command")
    verify(restored.source === undefined)
    verify(restored.exec === undefined)
  }

  function test_restoreManyPreservesOrderAndCleansKeepAliveEntries() {
    var cfg = config([
      { id: "plugin.a", value: "a" },
      { id: "middle" },
      { id: "plugin.b", value: "b" }
    ])
    var records = Stash.stashMany(cfg, ["plugin.a", "plugin.b"], function (id) {
      return "right"
    }, function (id) {
      return thirdParty()
    }, keepAliveSource())

    compare(cfg.bar.layout.left.length, 3)
    compare(cfg.bar.layout.left[0].source, keepAliveSource())
    compare(cfg.bar.layout.left[2].source, keepAliveSource())
    compare(Stash.restoreMany(cfg, records), 2)
    compare(cfg.plugins.length, 0)
    compare(cfg.bar.layout.left[0].id, "plugin.a")
    compare(cfg.bar.layout.left[1].id, "middle")
    compare(cfg.bar.layout.left[2].id, "plugin.b")
  }

  function test_manualUninstallRestoresMembersAndDropsOnlyOwnedSlots() {
    var slotSource = "/plugin/ContainerButton.qml"
    var cfg = config([
      { id: "plugin.a", value: "a" },
      { id: "middle" },
      { id: "plugin.b", value: "b" }
    ])
    cfg.plugins = [{ id: "user.enabled", value: 7 }]
    var records = Stash.stashMany(cfg, ["plugin.a", "plugin.b"], function (id) {
      return "right"
    }, function (id) {
      return thirdParty()
    }, keepAliveSource())
    cfg.bar.layout.right.push(
      { id: "leyanora.plugincontainers.c1", source: slotSource },
      { id: "leyanora.plugincontainers.c2", source: slotSource },
      { id: "leyanora.plugincontainers.foreign", source: "/other/ContainerButton.qml" }
    )

    compare(Stash.restoreMany(cfg, records), 2)
    compare(Stash.dropSlots(cfg, "leyanora.plugincontainers", slotSource), 2)

    compare(cfg.bar.layout.left[0].id, "plugin.a")
    compare(cfg.bar.layout.left[1].id, "middle")
    compare(cfg.bar.layout.left[2].id, "plugin.b")
    compare(cfg.bar.layout.right.length, 1)
    compare(cfg.bar.layout.right[0].id, "leyanora.plugincontainers.foreign")
    compare(cfg.plugins.length, 1)
    compare(cfg.plugins[0].id, "user.enabled")
    compare(cfg.plugins[0].value, 7)
  }

  function test_disabledStateCleanupDoesNotDuplicateEntries() {
    var cfg = config([{ id: "omarchy.example" }])
    cfg.disabledPlugins = ["omarchy.example"]
    var record = Stash.stash(cfg, "omarchy.example", "right", firstParty(), keepAliveSource())
    cfg.disabledPlugins = ["omarchy.example"]

    verify(Stash.restore(cfg, "omarchy.example", record))
    compare(cfg.disabledPlugins.length, 1)
    compare(cfg.disabledPlugins[0], "omarchy.example")
  }

  function test_normalizeKeepsOnlyKnownOwnershipFlags() {
    var state = Store.normalize({
      stashed: {
        "example.plugin": {
          inBar: true,
          keepAlive: {
            layoutEntryAdded: true,
            layoutSource: keepAliveSource(),
            disabledEntryRemoved: false,
            unknown: true
          }
        }
      }
    }, "leyanora.plugincontainers")

    verify(state.stashed["example.plugin"].keepAlive.layoutEntryAdded)
    compare(state.stashed["example.plugin"].keepAlive.layoutSource, keepAliveSource())
    verify(state.stashed["example.plugin"].keepAlive.disabledEntryRemoved === undefined)
    verify(state.stashed["example.plugin"].keepAlive.unknown === undefined)
  }
}
