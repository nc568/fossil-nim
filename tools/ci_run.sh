#!/bin/sh
# Run one command under CI and, if it fails, republish the reason as a GitHub
# Actions error annotation.
#
#   sh tools/ci_run.sh "description" command [args...]
#
# Why this exists: a job's console log is stored on blob storage that is not
# reachable from every place a run gets inspected, while annotations are served
# by the ordinary GitHub API. A failure that explains itself only in the log is
# a failure nobody can diagnose -- you are left with "Process completed with
# exit code 1". So the tail of the output is duplicated into an annotation.
#
# The full output is still printed to the console, so nothing is hidden from a
# human reading the job page.
#
# Optional:
#   CI_RUN_LOG=/path   also keep a copy of the output at that path, for later
#                      steps that want to grep it.
set -u

if [ "$#" -lt 2 ]; then
  echo "usage: sh tools/ci_run.sh \"description\" command [args...]" >&2
  exit 2
fi

desc="$1"
shift

tmp="${RUNNER_TEMP:-/tmp}"
log="$tmp/ci_run.$$.log"

echo "=== $desc"
echo "=== \$ $*"
"$@" > "$log" 2>&1
code=$?

cat "$log"

if [ -n "${CI_RUN_LOG:-}" ]; then
  cp "$log" "$CI_RUN_LOG"
fi

if [ "$code" -ne 0 ]; then
  # Workflow-command escaping: a literal % becomes %25, a newline becomes %0A,
  # and CR (which Windows runners produce) is dropped. Long lines are cut
  # because an annotation is a summary, not a transcript.
  msg=$(tail -n 30 "$log" \
        | tr -d '\r' \
        | cut -c1-400 \
        | sed -e 's/%/%25/g' \
        | awk 'NF {printf "%s%%0A", $0}')
  echo "::error::$desc -- exited $code%0A\$ $*%0A$msg"
fi

rm -f "$log"
exit "$code"
