#!/usr/bin/env bash
# Runs the unit tests. With Xcode this is plain `swift test`; Command Line Tools need
# explicit swift-testing paths, and their _Testing_Foundation overlay ships without
# a module, so cross-import overlays are disabled.
set -euo pipefail

FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
if [[ "$(xcode-select -p)" == */CommandLineTools && -d "$FRAMEWORKS/Testing.framework" ]]; then
  # Command Line Tools 27 keep the @Test macro plugin outside the default plugin path.
  PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
  EXTRA=()
  [[ -d "$PLUGINS" ]] && EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
  exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    ${EXTRA[@]+"${EXTRA[@]}"} \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    "$@"
fi
exec swift test "$@"
