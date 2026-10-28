#!/bin/sh
# Dogfood test, run on a Mac with the module enabled: the binary is on PATH from nix,
# its adhoc linker signature survived the build, it actually executes, and the
# pinned arrangement refers to displays that are really here.
#
# The signature check is the reason this file exists. displayplacer ships as a
# prebuilt, adhoc linker-signed Mach-O; nix's fixup phase strips by default,
# and a stripped adhoc-signed arm64 binary builds green and then dies with
# "killed: 9". nix/package.nix sets dontFixup for exactly that
# reason if it were dropped.
#
# READ-ONLY BY CONSTRUCTION. This never runs `displayplacer-apply`: the
# applier reasserts the pinned layout, so a test that ran it would snap the
# screens back and undo whatever the operator had just arranged by hand.
# Section D reads the applier instead of executing it.
set -e

command -v displayplacer >/dev/null || { echo "SKIP: displayplacer not in current generation"; exit 0; }

fails=0
ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1"; fails=$((fails+1)); }

echo "A. provenance"
p=$(command -v displayplacer)
case "$p" in
  /nix/store/*|"$HOME"/.nix-profile/*) ok "displayplacer from nix";;
  *) bad "displayplacer resolves outside nix: $p";;
esac

echo "B. signature survived fixup"
# flags must still read adhoc,linker-signed. If fixup stripped the binary this
# prints "code object is not signed at all" and the exec check below fails.
if codesign -dv "$p" 2>&1 | grep -q 'linker-signed'; then
  ok "adhoc linker signature intact"
else
  bad "signature gone — dontFixup dropped from nix/package.nix?"
fi

echo "C. runs"
# `list` is read-only: it prints the current arrangement and changes nothing.
if out=$(displayplacer list 2>&1); then
  ok "displayplacer list exits 0"
else
  bad "displayplacer list failed: $(echo "$out" | head -1)"
fi

# The last line of `list` is a ready-to-run command that would restore the
# current layout. Its presence means the private-framework calls resolved —
# a binary that loaded but could not read the display list would not get here.
if echo "$out" | grep -q '^displayplacer "id:'; then
  ok "read the live display arrangement"
else
  bad "no arrangement line in output — private frameworks unavailable?"
fi

echo "D. pinned arrangement"
if ! apply=$(command -v displayplacer-apply 2>/dev/null); then
  bad "displayplacer-apply not on PATH"
else
  ok "displayplacer-apply from ${apply}"

  # The generated applier carries its guard list as a literal `for id in …`
  # line. Reading it back is how this test learns what is pinned without
  # duplicating the ids here, where they would rot the moment the module
  # changed.
  ids=$(sed -n 's/^for id in \(.*\); do$/\1/p' "$apply")
  if [ -z "$ids" ]; then
    bad "could not read the pinned ids out of displayplacer-apply"
  else
    for id in $ids; do
      if echo "$out" | grep -q "$id"; then
        ok "pinned display $id is connected"
      else
        # Not a failure. This is the undocked case, and the applier's guard
        # is built to no-op through it — the point is to say so out loud
        # rather than leave a silent skip during activation.
        echo "  – pinned display $id not connected (applier will no-op)"
      fi
    done
  fi
fi

echo
[ "$fails" -eq 0 ] && echo "PASS" || { echo "FAIL ($fails)"; exit 1; }
