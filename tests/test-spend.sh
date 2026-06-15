#!/usr/bin/env bash
# tests/test-spend.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
. scripts/spend-check.sh   # sourcing must NOT run main

assert_eq "$(spend_decide 10 2 '' '')"        "spike"      "spike: today >= 2x avg and >= floor"
assert_eq "$(spend_decide 3 2 '' '')"         ""           "no spike: 3 < 2*2"
assert_eq "$(spend_decide 0.5 0.01 '' '')"    ""           "no spike: below \$1 floor"
assert_eq "$(spend_decide 1 0.1 '' '')"       "spike"      "spike: 1 >= 0.2 and >= 1.0 floor"
assert_eq "$(spend_decide 0.5 0.01 50 40)"    "budget100"  "budget100: mtd >= budget"
assert_eq "$(spend_decide 0.5 0.01 35 40)"    "budget80"   "budget80: mtd >= 80% < 100%"
assert_eq "$(spend_decide 0.5 0.01 10 40)"    ""           "no budget alert: mtd < 80%"
assert_eq "$(spend_decide 10 2 50 40)"        "spike budget100" "both spike and budget"
assert_eq "$(spend_decide 2.00 0 '' '')"  "spike"  "spike fires on first day with no history (by design)"
assert_eq "$(spend_decide 0.50 0 '' '')"  ""       "floor still protects on first day (avg7=0)"
t_done
