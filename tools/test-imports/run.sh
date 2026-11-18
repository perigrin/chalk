#!/bin/bash
# ABOUTME: Rebuild the test x module table: run every .t under perl with INCdump,
# ABOUTME: then analyze.pl writes the full TSV, the per-test summary and a report.
#   tools/test-imports/run.sh OUTDIR    (cwd = chalk root; the full TSV is not committed)
set -u
OUT=${1:?usage: run.sh OUTDIR}
mkdir -p "$OUT/runs"
T=$(cd "$(dirname "$0")" && pwd)
export HOME=${SUITE_HOME:-/home/runner} PERL5_SON_LIB=${PERL5_SON_LIB:-/home/user/repo/lib} LLI=${LLI:-/usr/bin/lli} T OUT

one() {
    f=$1; id=$(echo "$f" | tr '/.' '__'); R=$OUT/runs
    rm -f "$R/$id.inc"
    ulimit -v 4000000
    s=$(date +%s.%N)
    INCDUMP_OUT=$R/$id.inc timeout 2400 perl -Ilib -It/lib -I"$T" -MINCdump "$f" \
        > "$R/$id.out" 2> "$R/$id.err" < /dev/null
    ec=$?; e=$(date +%s.%N)
    printf '%s\t%s\t%.1f\t%s\t%s\t%s\n' "$f" "$ec" "$(echo "$e - $s" | bc)" \
        "$(grep -c '^ok ' "$R/$id.out")" "$(grep -c '^not ok ' "$R/$id.out")" \
        "$(grep -m1 -E '^1\.\.[0-9]+' "$R/$id.out" | head -c 200)" > "$R/$id.meta"
}
export -f one

# mode2-extractor.t needs ~/dev/perl5; the suite excludes it too.
find t -name '*.t' ! -name mode2-extractor.t | sort | xargs -P 4 -I{} bash -c 'one {}'
git checkout -q HEAD -- paad/worklist.json 2>/dev/null; rm -f .out.pl
perl "$T/analyze.pl" "$OUT/runs" . "$OUT/test-imports.tsv" "$OUT/test-imports-summary.tsv" "$OUT/report.txt"
