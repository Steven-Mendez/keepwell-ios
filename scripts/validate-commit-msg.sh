#!/bin/bash
# Validates that a message follows Conventional Commits (https://www.conventionalcommits.org).
# Usage:
#   scripts/validate-commit-msg.sh <message-file>             (commit-msg hook)
#   echo "feat: something" | scripts/validate-commit-msg.sh - (CI, PR title)
set -euo pipefail

TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
MAX_HEADER=100

source="${1:--}"
if [ "$source" = "-" ]; then
  message="$(cat)"
else
  message="$(cat "$source")"
fi

# First line that is neither a comment nor blank.
header="$(printf '%s\n' "$message" | grep -v '^#' | sed '/^[[:space:]]*$/d' | head -n 1 || true)"

# Git-generated messages that are allowed as-is.
if [[ "$header" =~ ^(Merge\ |Revert\ \"|fixup!\ |squash!\ |amend!\ ) ]]; then
  exit 0
fi

pattern="^($TYPES)(\([a-z0-9][a-z0-9._/-]*\))?!?: [^[:space:]].*$"

fail() {
  cat >&2 <<MSG
✖ Invalid commit message: "$header"
  $1

  Format:   <type>(<optional scope>)!: <description>
  Types:    ${TYPES//|/, }
  Examples: feat(onboarding): add currency step
            fix: prevent double save
            chore(deps)!: drop iOS 25 support
MSG
  exit 1
}

[ -n "$header" ] || fail "The message is empty."
[[ "$header" =~ $pattern ]] || fail "It does not follow Conventional Commits."
[ "${#header}" -le "$MAX_HEADER" ] || fail "The header exceeds $MAX_HEADER characters (${#header})."
[[ "$header" != *. ]] || fail "The description must not end with a period."
exit 0
