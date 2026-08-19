#!/bin/bash

# Runs the pure-logic tests for Store.js and Stash.js. These cover the parts
# that are easy to get wrong and hard to see in the UI: the refcount that
# decides when a plugin leaves and rejoins the bar, and the snapshot/restore
# that has to give it back its original position and settings.
#
# The QML surface is not covered here; verify that against a running shell.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

command -v node >/dev/null 2>&1 || {
  echo "tests: node is required to run the logic tests" >&2
  exit 1
}

node "$ROOT/tests/logic.test.js"
