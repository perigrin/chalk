#!/bin/bash
# ABOUTME: Runs every gate of the wire v2 plan (both suites, the census, the corpus gate, the
# ABOUTME: audit probes, the wire verifier's ratchet) on snapshots of this checkout and B::SoN's.
#
#   PERL5_SON_LIB=/path/to/perl5-son/lib tools/gates.sh [--out DIR] [--jobs N] [--only GATE,...]
#   tools/gates.sh --summary --out DIR
#   tools/gates.sh --list
#
# ONE IMPLEMENTATION. The gates span two repositories, and the script that
# runs them is B::SoN's tools/gates.sh (it owns the census and the verifier);
# this hands it this checkout as the chalk to test. Its header says what is
# run, how a run is resumed, and how to read the summary.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
SON=${PERL5_SON_LIB:-$HOME/dev/perl5-son/lib}
[ -x "$SON/../tools/gates.sh" ] || {
    echo "GAP: B::SoN's tools/gates.sh is not beside $SON (set PERL5_SON_LIB)" >&2
    exit 2
}
exec "$SON/../tools/gates.sh" --chalk "$HERE" "$@"
