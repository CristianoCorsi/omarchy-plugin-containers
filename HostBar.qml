import QtQuick
import qs.Commons

// The `bar` a hosted plugin sees: the real one, minus four things that would break hosting.
QtObject {
  id: hostBar

  property var bar: null
  property var shell: null

  // Set when the container hosts its widgets in its own bar slot rather than in a strip:
  // the cells are then in the bar's own window, and the real bar can serve them directly.
  property bool inline: false

  signal tooltipRequested(var target, string text)
  signal tooltipDismissed(var target)

  // The strip is horizontal whatever edge the real bar is docked to; inline it is the bar.
  readonly property bool vertical: inline && bar ? bar.vertical === true : false
  readonly property int barSize: inline && bar ? bar.barSize : Style.bar.sizeHorizontal
  // Forwarded: a hosted popup should still open away from the bar's edge.
  readonly property string position: bar ? bar.position : "top"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color background: bar ? bar.background : Color.bar.background
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool transparent: bar ? bar.transparent : false
  readonly property bool foregroundAnimationEnabled: bar ? bar.foregroundAnimationEnabled : true
  readonly property bool barHidden: bar ? bar.barHidden : false

  readonly property var barWidgetRegistry: bar ? bar.barWidgetRegistry : null
  readonly property var layoutConfig: bar ? bar.layoutConfig : null

  function run(command) { return hostBar.bar.run(command) }
  function shellQuote(value) { return hostBar.bar.shellQuote(value) }
  function targetBelongsToWindow(target, window) { return hostBar.bar.targetBelongsToWindow(target, window) }

  // broadcast() should reach the container's instances; the bar has none.
  property var peers: []
  function moduleWidgets(id) {
    var out = []
    for (var i = 0; i < peers.length; i++) {
      if (peers[i] && peers[i].moduleName === id) out.push(peers[i])
    }
    return out
  }

  // Hosted buttons register here so a click on a cell's padding can be routed to one.
  property var clickTargets: []

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    clickTargets = clickTargets.filter(function (item) { return item !== target })
  }

  // Local coordinator: a hosted popup must not evict the container hosting it.
  property var activePopout: null

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  // Or a hosted popup outlives the strip that anchored it.
  function closeHostedPopouts() {
    if (!activePopout) return
    var owner = activePopout
    activePopout = null
    if ("close" in owner) owner.close()
  }

  // No neighbouring slot inside a container; forwarding would jump focus out to the bar.
  function switchPanelFrom(owner, direction) { return false }

  // The bar only paints tooltips for its own windows, so the strip hosts its own. An inline
  // cell is in that window, so there the real one works and looks like every other widget's.
  function showTooltip(target, text) {
    if (hostBar.inline && hostBar.bar) {
      hostBar.bar.showTooltip(target, text)
      return
    }
    hostBar.tooltipRequested(target, String(text || ""))
  }

  function hideTooltip(target) {
    if (hostBar.inline && hostBar.bar) {
      hostBar.bar.hideTooltip(target)
      return
    }
    hostBar.tooltipDismissed(target)
  }
}
