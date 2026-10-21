#!/usr/bin/env bash
# Runs the unit tests. With Xcode this is plain `swift test`; Command Line Tools need
# explicit swift-testing paths, and their _Testing_Foundation overlay ships without
# a module, so cross-import overlays are disabled.
set -euo pipefail

FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
if [[ "$(xcode-select -p)" == */CommandLineTools && -d "$FRAMEWORKS/Testing.framework" ]]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    "$@"
fi
exec swift test "$@"
