#!/bin/sh
# Xcode Cloud clones the repo without Wain.xcodeproj, which XcodeGen makes and git
# never holds, so make it here: the build looks for the project right after this runs.
set -eu
cd "$(dirname "$0")/.."
HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
xcodegen generate
# Xcode Cloud never resolves packages itself; it builds from the project's Package.resolved.
xcodebuild -resolvePackageDependencies -project Wain.xcodeproj -scheme Wain
