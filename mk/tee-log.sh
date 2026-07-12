#!/bin/sh
# make SHELL wrapper — tees all recipe stdout+stderr to a log file
#
# make calls:  tee-log.sh -c 'recipe line'
# LOG_FILE is set in environment by mk/00-vars.mk when LOG=1.
# If LOG_FILE is unset, runs normally (no logging).

logfile="${LOG_FILE:-}"

if [ -z "$logfile" ]; then
  # Not in LOG mode, execute directly
  exec /bin/sh "$@"
fi

# Drop '-c' (argv[1]), the remaining args are the recipe text
shift

# Run the recipe through the shell, tee stdout+stderr
{
  /bin/sh -c "$*"
} 2>&1 | tee -a "$logfile"

# Preserve exit status
exit ${PIPESTATUS:-0}
