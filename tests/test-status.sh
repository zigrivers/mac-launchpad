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

# _join_ports: a MULTI-LINE listen map must survive stock macOS awk (a `-v` value
# with a newline aborts it — this test would have caught that regression).
_jp_listen="$(printf '1024\t50608\n2048\t3000')"
_jp_records="$(printf 'p1024\nn/Users/x/Developer/foo\np2048\nn/Users/x/Developer/bar\np9999\nn/elsewhere')"
assert_eq "$(printf '%s\n' "$_jp_records" | _join_ports "$_jp_listen")" \
          "$(printf '/Users/x/Developer/foo\t50608\n/Users/x/Developer/bar\t3000')" \
          "_join_ports maps listening pids to cwd+port (multi-line, stock-awk safe)"

# _lookup_port: exact cwd, cwd-under-repo, and no-match
_pm="$(printf '/dev/foo\t5173\n/dev/bar/sub\t3000')"
assert_eq "$(_lookup_port "$_pm" /dev/foo)" "5173" "_lookup_port exact cwd match"
assert_eq "$(_lookup_port "$_pm" /dev/bar)" "3000" "_lookup_port cwd-under-repo match"
assert_eq "$(_lookup_port "$_pm" /dev/baz)" ""     "_lookup_port no match -> empty"

t_done
