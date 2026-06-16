#!/usr/bin/env bash
# tests/test-signin.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
. scripts/signin.sh   # sourcing must NOT run main

# signin_line <ok 0|1> <service> <action> <unlocks>
assert_eq "$(signin_line 1 GitHub 'run gh auth login' 'private backups')" \
          "  ✓ GitHub — ready" "ok line"
assert_eq "$(signin_line 0 GitHub 'run gh auth login' 'private backups')" \
          "  • GitHub — run gh auth login   (unlocks: private backups)" "todo line"

# detection wrapper with a mock `gh` on PATH
MB="$(mktemp -d)"
printf '#!/bin/sh\nexit 0\n' > "$MB/gh"; chmod +x "$MB/gh"
assert_eq "$(PATH="$MB:$PATH" _yn _gh_ok)" "1" "_gh_ok true when gh auth status exits 0"
printf '#!/bin/sh\nexit 1\n' > "$MB/gh"
assert_eq "$(PATH="$MB:$PATH" _yn _gh_ok)" "0" "_gh_ok false when gh auth status exits 1"

t_done
