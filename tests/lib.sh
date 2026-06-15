#!/usr/bin/env bash
# tests/lib.sh — minimal assertions for host-runnable bash unit tests.
# Usage: source this, call assert_eq, end with t_done.
_T_FAIL="${_T_FAIL:-0}"
assert_eq() { # assert_eq <actual> <expected> <message>
  if [ "$1" = "$2" ]; then
    printf '  ok   %s\n' "$3"
  else
    printf '  FAIL %s\n        got: [%s]\n     wanted: [%s]\n' "$3" "$1" "$2"; _T_FAIL=1
  fi
}
t_done() { if [ "$_T_FAIL" = 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi; }
