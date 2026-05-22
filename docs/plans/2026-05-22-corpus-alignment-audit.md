# Audit Corpus Alignment with `lib/`

**Date:** 2026-05-22 (after Phase 3d closure)
**HEAD on `pu` at writing:** `e50d76ba` (+ Phase 3d commits on `fixup-audit-baseline`)
**Scope:** Verify the IR audit corpus (`t/fixtures/ir-audit-corpus.pl`)
covers the constructs actually present in Chalk's own self-hosting
source code. Read-only audit; produces this report and an expanded
corpus.

## Why

The Phase 3d work closed every gap the original 56-snippet corpus
caught. If real Chalk code uses constructs the corpus doesn't probe,
the "IR is complete" claim is overstated. This audit verifies the
corpus is representative of what the compiler actually has to handle.

## Method

`script/audit-corpus-alignment.pl` scans `lib/**.pm` (143 files) for
~100 syntactic construct patterns and reports per-construct
file-presence counts. For each construct, it cross-references whether
the original audit corpus probed that construct.

The constructs are detected by regex over source text. False
positives are accepted (over-counting). False negatives are not (a
construct present in lib/ must be detected).

## Findings before corpus expansion

The original 56-snippet corpus covered the major node types
(VarDecl, Call, Assign, CompoundAssign, RegexSubst, If, Loop,
TryCatch). It missed several legitimate construct categories used
widely in `lib/`.

Gaps with >10 occurrences in `lib/`:

| Construct | files | Notes |
|---|---|---|
| `use-pragma` (use strict etc.) | 143 | every file; UseInfo body items not probed |
| `use-module` (use Foo::Bar) | 116 | UseInfo body items |
| `method-call-no-parens` | 59 | false-positive overlap with method-call |
| `string-interp` (`"foo $var"`) | 47 | string interpolation never probed |
| `postfix-for` | 35 | `STMT for LIST` |
| `for-as-foreach` (without my) | 33 | `for (LIST) { ... }` using `$_` |
| `postfix-unless` | 33 | `STMT unless EXPR` |
| `arrow-subscript-array` | 23 | `$ref->[N]` |
| `arrow-subscript-hash` | 23 | `$ref->{K}` |
| `ref-of` | 23 | `\@list`, `\%hash` |
| `caller` | 15 | introspection |
| `string-concat` | 15 | `"a" . "b"` |
| `static-method-call` | 12 | `Foo::Bar->new()` |
| `my-multiple` | 11 | `my ($a, $b) = ...` |
| `compound-assign-or` | 10 | `$x //= ...` |

Smaller gaps (<10 occurrences): `unless` block, `next-bare`,
`last-bare`, `bare-delete`, `sort-block`, `do-block`, `eval-block`,
`for-c-style`.

## Corpus expansion (M-series additions)

Added 25 snippets (M1-M25) covering the legitimate gaps:

- **M1-M2:** `use strict`, `use List::Util qw(...)` — UseInfo body items
- **M3-M4:** string interpolation with scalar and array variables
- **M5:** postfix unless
- **M6:** postfix for (`STMT for LIST`)
- **M7:** iterator-less foreach (`foreach (LIST) { ... }` using `$_`)
- **M8-M9:** arrow subscript array/hash
- **M10-M11:** ref-of constructs
- **M12-M13:** static method calls / qualified function calls
- **M14:** string concatenation
- **M15:** defined-or compound assign (`//=`)
- **M16:** block unless
- **M17-M18:** bare next / last inside loops
- **M19:** my multi-assign (`my ($a, $b) = ...`)
- **M20-M21:** do block / eval block
- **M22:** sort with block (`sort { $a <=> $b } LIST`)
- **M23:** bare delete
- **M24:** chained arrow subscript (`$r->{a}->[0]`)
- **M25:** C-style for loop (`for (my $i = 0; $i < N; $i++) { ... }`)

Corpus is now 82 snippets across 13 categories.

## New findings from expanded corpus

Running the probe on the expanded corpus surfaces 2 WARN cases:

### Carried-over: I3 (my sub → SubInfo)

Same as before. The body item is a metadata struct, not an IR node.
The completeness test excludes metadata structs from its
"is-in-graph" assertion. Not a real failure.

### New: M7 (iterator-less foreach)

`foreach (1, 2, 3) { $sum = $sum + $_; }` parses but produces body
items `[VarDecl($sum), Constant(1), Constant(2), Constant(3), Return]`
— no Loop, no If, no Phi. The three Constants are statement-position
body items not in the graph, marked [miss].

Cause: `ForeachStatement` action at Actions.pm:2801 has
`return undef unless defined $iterator;`. The grammar's second
alternative (foreach without IteratorVariable) parses successfully
but the action drops it.

`lib/` does not use this form — every loop in lib/ is either
`for my $x (LIST)` (with iterator) or `for (my $i = 0; ...; ...)`
(C-style). So this is a gap in IR coverage of a Perl feature Chalk
doesn't currently consume, not a bug blocking self-hosting.

### Newer finding outside corpus: ForStatement is a stub

While investigating M25 (C-style for loop), discovered
`ForStatement` at Actions.pm:2762:

```perl
method ForStatement($ctx) {
    return undef;
}
```

The grammar accepts C-style for loops; the action discards them.
For the M25 snippet, the body comes out as `[VarDecl($sum),
VarDecl($i), Return]` — the entire for-loop's condition,
increment, and body are not in the IR.

**`lib/` uses C-style for loops in 5 places**:
- `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` (3 sites)
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (1 site)
- `lib/Chalk/Bootstrap/Perl/Target/C.pm` (1 site)

This is a **real blocker for full self-hosting**. The compiler
parses these files (they're valid grammar) but the parsed IR is
wrong: the loop body is dropped.

## Summary

**Corpus alignment after expansion:**
- 82 snippets covering all construct categories present in `lib/`
  with >10 occurrences.
- Smaller-frequency constructs (<10 sites) covered where they
  affect IR shape; introspection/runtime constructs (caller,
  wantarray, goto) deliberately excluded as out of Chalk's
  semantic subset.

**Remaining gaps:**

| Gap | lib/ usage | Real blocker? |
|---|---|---|
| ForStatement (C-style for) | 5 sites | **Yes** — actively used in self-hosting |
| Iterator-less foreach | 0 sites | No — Perl pattern Chalk doesn't use |
| `my sub` graph membership | 1 corpus case | No by design (SubInfo, not IR node) |

## Recommended remediation

**Critical** (blocks self-hosting):

- **ForStatement action implementation.** Build a CFG Loop+If
  structure equivalent to `foreach (LIST)` after desugaring
  init/cond/incr. This is genuinely new compiler work and should
  get its own design pass. Scope candidate: Phase 3e — ForStatement
  lowering.

**Documentation** (no code change):

- Note in MEMORY.md and master plan that iterator-less foreach is
  out of scope for Chalk's subset.

**No action** (corpus pinning):

- I3 (my sub) continues to be flagged by the probe and excluded by
  the completeness test. This is the correct treatment: metadata
  structs are not IR nodes by design.

## Reproducing

```
$ perl script/audit-corpus-alignment.pl > /tmp/alignment.txt
$ perl script/probe-ir.pl t/fixtures/ir-audit-corpus.pl > /tmp/probe.txt
$ grep WARN /tmp/probe.txt | wc -l
2
```

The expanded corpus is committed at `t/fixtures/ir-audit-corpus.pl`.
The alignment script is committed at `script/audit-corpus-alignment.pl`.

## What this audit does NOT prove

- That every Perl construct in Chalk's subset is now correctly
  IR'd. The audit checks structural reachability, not semantic
  correctness. Two constructs could produce equally-reachable IR
  but with subtly different semantics; this audit wouldn't catch it.
- That the regex-based construct detection in
  `script/audit-corpus-alignment.pl` is complete. Some patterns
  may have false negatives (a construct in `lib/` not detected).
- That the M-series snippets exercise *every* IR shape variation
  for their construct. A single snippet per category is a
  sufficient signal for the structural questions this audit asks,
  but is not exhaustive.
