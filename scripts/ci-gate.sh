#!/bin/bash
# Decides whether the macOS test job must run, and writes `run_tests=true|false` to $GITHUB_OUTPUT.
#
# develop, staging and main are fast-forwarded, so a promotion pushes the SAME commit again. The
# develop run is the one that really tests it; staging/main wait for it here (on a cheap Linux
# runner) instead of repeating ~20 macOS minutes:
#   - develop run succeeded  -> skip the macOS job (the check stays green, the summary says why)
#   - develop run failed     -> fail this run too, without spending macOS time on the same commit
#   - no develop run / cancelled / timed out -> run the full suite (never skip without evidence)
# PRs, manual dispatches and develop itself always run everything.
#
# Env: GH_TOKEN, REPO, SHA, EVENT, REF, WORKFLOW_FILE, GATE_MAX_WAIT (seconds, default 2100).
set -euo pipefail

out() { echo "run_tests=$1" >>"${GITHUB_OUTPUT:-/dev/stdout}"; }
summary() { echo "$1" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"; echo "$1"; }

if [ "$EVENT" != push ] || [ "$REF" = refs/heads/develop ]; then
  out true
  exit 0
fi

deadline=$((SECONDS + ${GATE_MAX_WAIT:-2100}))
no_run_grace=$((SECONDS + 180)) # the develop run may register a little after this one

while :; do
  # Latest develop push run for this exact commit: "status conclusion" (conclusion empty while running).
  run="$(gh api "repos/$REPO/actions/workflows/$WORKFLOW_FILE/runs?head_sha=$SHA&branch=develop&event=push" \
    --jq '[.workflow_runs[]] | sort_by(.created_at) | last | if . == null then "none" else "\(.status) \(.conclusion // "")" end')"
  case "$run" in
    "completed success")
      summary "Commit $SHA already passed CI on develop: macOS build and tests skipped."
      out false
      exit 0
      ;;
    "completed failure" | "completed timed_out")
      summary "CI failed on develop for $SHA. Fix it there (or re-run it); this run is not repeating the same tests."
      exit 1
      ;;
    "completed "*) # cancelled, skipped, neutral: no proof the commit is good
      summary "The develop run for $SHA ended as '${run#completed }': running the full suite here."
      out true
      exit 0
      ;;
    none)
      if [ "$SECONDS" -ge "$no_run_grace" ]; then
        summary "No develop run found for $SHA: running the full suite here."
        out true
        exit 0
      fi
      ;;
  esac
  if [ "$SECONDS" -ge "$deadline" ]; then
    summary "Timed out waiting for the develop run of $SHA: running the full suite here."
    out true
    exit 0
  fi
  echo "develop run: $run; waiting..."
  sleep 30
done
