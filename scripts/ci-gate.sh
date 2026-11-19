#!/bin/bash
# Decides whether the macOS test job must run, and writes `run_tests=true|false` to $GITHUB_OUTPUT.
#
# The same code is pushed several times on its way to main (pull request -> develop -> release ->
# main), and every merge creates a new commit, so commit SHAs never repeat. The git TREE does: a
# merge that brings nothing new has exactly the tree that was already tested. The macOS job records each
# tree it passes as an artifact named `tested-tree-<tree>`; this script (on a cheap Linux runner)
# looks for that marker instead of repeating ~30 macOS minutes:
#   - marker found                          -> skip the macOS job (the check stays green)
#   - an older push run is testing the tree -> wait for it: marker appears -> skip, it fails -> fail
#   - no evidence                           -> run the full suite (never skip without proof)
# Pushes to develop and manual dispatches always run everything: develop is the post-merge signal
# and the only branch whose caches every other branch can read.
#
# Env: GH_TOKEN, REPO, EVENT, REF, WORKFLOW_FILE, RUN_ID, GATE_MAX_WAIT (seconds, default 2100),
#      TREE (optional, defaults to the tree of the checked out commit).
set -euo pipefail

out() { echo "run_tests=$1" >>"${GITHUB_OUTPUT:-/dev/stdout}"; }
summary() { echo "$1" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"; echo "$1"; }

if [ "$EVENT" = workflow_dispatch ] || { [ "$EVENT" = push ] && [ "$REF" = refs/heads/develop ]; }; then
  out true
  exit 0
fi

# On a pull request the checked out commit is the merge commit, i.e. the tree the tests would see.
tree="${TREE:-$(git rev-parse 'HEAD^{tree}')}"
run_id="${RUN_ID:-0}"
echo "tree: $tree"

# Run that uploaded the marker for this tree, if any. Markers uploaded from a fork are ignored: a
# fork's pull request runs the fork's workflow file and could claim a tree it never tested.
marker_run() {
  gh api "repos/$REPO/actions/artifacts?name=tested-tree-$tree&per_page=100" --jq '
    [.artifacts[]
      | select(.expired | not)
      | select(.workflow_run.head_repository_id == .workflow_run.repository_id)]
    | first | .workflow_run.id // empty'
}

# Latest OLDER push run with this tree: "id status conclusion", or "none". Only older runs count so
# that two runs of the same tree never wait for each other.
other_run() {
  gh api "repos/$REPO/actions/workflows/$WORKFLOW_FILE/runs?event=push&per_page=50" --jq "
    [.workflow_runs[] | select(.id < $run_id and .head_commit.tree_id == \"$tree\")]
    | sort_by(.id) | last
    | if . == null then \"none\" else \"\(.id) \(.status) \(.conclusion // \"\")\" end"
}

deadline=$((SECONDS + ${GATE_MAX_WAIT:-2100}))

while :; do
  tested_by="$(marker_run)"
  if [ -n "$tested_by" ]; then
    summary "Tree $tree already passed the tests in run $tested_by: macOS build and tests skipped."
    out false
    exit 0
  fi

  run="$(other_run)"
  case "$run" in
    none)
      summary "No tested marker for tree $tree: running the full suite here."
      out true
      exit 0
      ;;
    *" completed failure" | *" completed timed_out")
      summary "Run ${run%% *} failed for this same tree ($tree). Fix it there (or re-run it); this run is not repeating the same tests."
      exit 1
      ;;
    *" completed "*) # success without a marker (it skipped too), cancelled, skipped: no proof
      summary "Run ${run%% *} ended as '${run##* }' without a tested marker for tree $tree: running the full suite here."
      out true
      exit 0
      ;;
  esac

  if [ "$SECONDS" -ge "$deadline" ]; then
    summary "Timed out waiting for run ${run%% *} to test tree $tree: running the full suite here."
    out true
    exit 0
  fi
  echo "run ${run%% *} is testing this tree (${run#* }); waiting..."
  sleep 30
done
