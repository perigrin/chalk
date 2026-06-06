#!/bin/bash
# ABOUTME: Runner script for the typed-IR-representation model Phase 3a spike.
# ABOUTME: Runs the hand-written add.ll via lli and compares output to the perl oracle.
#
# Usage: bash t/spike/llvm/run_add.sh
# Expected output:
#   ORACLE (perl):  3
#   LLVM (lli):     3
#   MATCH: yes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLI=/usr/lib/llvm-15/bin/lli
PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl

ORACLE=$("$PERL" -e 'my $r = 1 + 2; print $r;')
LLVM_OUT=$("$LLI" "$SCRIPT_DIR/add.ll")

echo "ORACLE (perl):  $ORACLE"
echo "LLVM (lli):     $LLVM_OUT"

if [ "$ORACLE" = "$LLVM_OUT" ]; then
    echo "MATCH: yes"
    exit 0
else
    echo "MATCH: NO -- oracle='$ORACLE' llvm='$LLVM_OUT'"
    exit 1
fi
