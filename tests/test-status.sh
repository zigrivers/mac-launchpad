#!/usr/bin/env bash
# tests/test-status.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
. scripts/status.sh   # sourcing must NOT run main

# status_classify <dirty> <ahead> <has_remote> -> "ok|phrase" / "warn|phrase"
assert_eq "$(status_classify 0 0 1)" "ok|backed up"                 "clean+remote = backed up"
assert_eq "$(status_classify 3 0 1)" "warn|3 unsaved"               "dirty = unsaved"
assert_eq "$(status_classify 0 2 1)" "warn|2 unpushed"              "ahead = unpushed"
assert_eq "$(status_classify 3 2 1)" "warn|3 unsaved, 2 unpushed"   "dirty+ahead"
assert_eq "$(status_classify 0 0 0)" "warn|no remote yet"           "no remote"
assert_eq "$(status_classify 5 1 0)" "warn|no remote yet"           "no remote dominates"

# _age <seconds> -> now / Nm / Nh / Nd
assert_eq "$(_age 30)"     "now" "age < 1m"
assert_eq "$(_age 120)"    "2m"  "age minutes"
assert_eq "$(_age 7200)"   "2h"  "age hours"
assert_eq "$(_age 259200)" "3d"  "age days"

t_done
