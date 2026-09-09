.pragma library

// The bar root is the only object holding the widget catalogue, the write API and the
// hosted bar. A container slot and the manager widget are loaded by the bar as ordinary
// modules, so they are handed capability facades instead and cannot reach it by traversal.
// Library scope is per engine and outlives a bar rebuild, which is what makes it the
// handle they look the root up through.

var _host = null

function publish(host) { _host = host }

function withdraw(host) { if (_host === host) _host = null }

function host() { return _host }
