#!/bin/bash
# Xcode build phase: runs SwiftLint at the version pinned by mise.
# In Debug, errors are downgraded to warnings so local iteration is never blocked.
set -uo pipefail

export PATH="$HOME/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "${SRCROOT:-$(dirname "$0")/..}" || exit 0

if command -v mise >/dev/null 2>&1; then
  SWIFTLINT=(mise exec -- swiftlint)
elif command -v swiftlint >/dev/null 2>&1; then
  SWIFTLINT=(swiftlint)
else
  echo "warning: SwiftLint is not installed. Run 'make bootstrap'."
  exit 0
fi

if [ "${CONFIGURATION:-Debug}" = "Debug" ]; then
  "${SWIFTLINT[@]}" lint --quiet | sed 's/: error: /: warning: /'
  exit 0
fi

"${SWIFTLINT[@]}" lint --quiet
