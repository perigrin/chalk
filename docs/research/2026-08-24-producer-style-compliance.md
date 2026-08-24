# Producer (perl5-son) style-compliance audit

**Date:** 2026-08-24
**Subject:** `/home/perigrin/dev/perl5-son` @ `pu` (10f9e2e), `lib/` (105 `.pm`,
11,561 lines) and `t/` (111 `.t`, 588 tests)
**Reference:** `/home/perigrin/dev/chalk/.claude/worktrees/pu` (168 `.pm`, 36,260 lines)
**Status:** READ-ONLY. Nothing fixed. No producer file modified.

## Oracle

Named explicitly, because most categories here have no external oracle.

| Category | Oracle | Type |
|---|---|---|
| 1 class style, 2 ABOUTME, 3 deref, 4 booleans, 5 signatures, 6 eval | chalk `CLAUDE.md` "Code Style" + global `CLAUDE.md` | **Plan oracle** — the written convention IS the spec |
| 7 `$a`/`$b` | reproduced miscompile (probe below) + the fixed regression at `SoN/IR/Stamp.pm:92-93` | **External** (differential probe) |
| 8 mirror | chalk `TypeLibrary.pm:12-14` states the two tables "must not drift" — a written contract | **Plan oracle** |
| suite green | `prove -Ilib -Iblib/lib -j1 t/` → 111 files, 588 tests, PASS | **Regression guard only** |

The producer has **no `CLAUDE.md` of its own** (`ls -a ~/dev/perl5-son` — absent).
It is held to chalk's conventions by the dispatching ruling, not by any file in
its own tree. That is itself finding 0.

**Calibration note, load-bearing:** on three of the seven categories the producer
is *cleaner than chalk per line*. Any remediation framed as "the producer is
behind" would be measuring the wrong thing. Normalized per KLOC:

| Metric | producer | chalk | verdict |
|---|---|---|---|
| `= @_;` (non-signature) | 29 (2.5/KLOC) | 152 (4.2/KLOC) | producer **cleaner** |
| prefix-deref code sites | 37 (3.2/KLOC) | 205 (5.7/KLOC) | producer **cleaner** |
| `eval {` | 31 (2.7/KLOC) | 2 (0.06/KLOC) | producer **worse** (but see F6) |
| `return 1/0;` | 18 | 6 | producer worse |
| ABOUTME 2-line | 105/105 | 168/168 | tie, both perfect |

## Summary table

| # | Category | Violations | Sites | Mechanical | Judgement |
|---|---|---|---|---|---|
| 0 | No `CLAUDE.md` in producer tree | 1 | — | 0 | 1 |
| 1 | Class style | **0 real** | 7 plain pkgs, all justified | 0 | 0 |
| 1b | Pragma idiom vs written rule | rule is **stale on both sides** | 92 prod / 163 chalk | 0 | 1 (fix the doc) |
| 2 | ABOUTME structural | **0** (105/105 two-line) | — | 0 | 0 |
| 2b | ABOUTME describes history | 4 wording + 17 ticket-ref | 21 | 17 | 4 |
| 2c | `use utf8` missing | 9 `.pm` + 79 `.t` | 88 | 88 | 0 |
| 3 | Prefix deref | 37 lib + 34 t code sites | 71 | 62 | 9 |
| 4 | Booleans 1/0 | 19 subs | 25 | 23 | 2 |
| 5 | Signatures | 27 subs | 27 | 26 | 1 |
| 6 | `eval {}` vs try/catch | 31 lib | 31 | 0 | 31 |
| 7 | `$a`/`$b` lexicals | 3 lib + 25 t | 28 | 26 | 2 |
| 8 | Mirror divergence | 5 distinct | — | 1 | 4 |

Totals: **~200 sites**, of which **~216 mechanical / ~45 judgement** by
category weighting. No live defect found — every hazard measured is **latent**.
The suite is green and I did not find a case where style debt is currently
producing wrong output.

---

## Finding 0: the producer has no `CLAUDE.md`

**Evidence:** `ls -a /home/perigrin/dev/perl5-son` — no `CLAUDE.md`. Chalk has
two layers of convention (`~/.claude/CLAUDE.md` global + project
`CLAUDE.md`); the producer inherits only the global one, which does not
contain the "Code Style" block (that is chalk-project-specific).

Every violation below is therefore a violation of a rule **never written down
where the producer's authors would see it**. This is the root cause for the
category-2c/6 divergences: they are not carelessness, they are the absence of
a spec.

**Suggested remediation shape:** either a producer `CLAUDE.md` that references
chalk's Code Style block, or a shared style file both repos include.
**Side effects:** any producer `CLAUDE.md` that restates rules rather than
referencing them creates a second source of truth that will drift — the exact
failure mode finding 8 documents for the lattice.

---

## 1. Class style — the strongest category, effectively clean

```
$ grep -rln "^class " lib --include=*.pm | wc -l      → 98
$ find lib -name "*.pm" | wc -l                       → 105
$ grep -rn "our @ISA|use parent|use base|push @ISA" lib t   → (no output)
$ grep -rn "bless" lib --include=*.pm | grep -v blessed     → 2 hits, both
    OpMap.pm:244-245, which are opcode-NAME table entries (`bless => [...]`),
    not calls
$ grep -rn ":isa(" lib --include=*.pm | wc -l         → 89
```

**Verification of the earlier claim:** "0 `@ISA`, 92 files on feature class" —
`@ISA` count **confirmed 0**; the file count is **98, not 92**. The 92 figure
matches `grep -c "use experimental 'class'"`, which is a different measurement
(6 files use `use feature 'class'` instead). Full picture: 98 class files = 92
`use experimental 'class'` + 6 `use feature 'class'`.

### The 7 plain-package modules, each classified

| File | Lines | Stateful? | Verdict |
|---|---|---|---|
| `lib/SoN.pm` | 36 | no | `XSLoader::load` + `$VERSION`. **Correct as-is** — cannot be a class, it is the XS bootstrap. |
| `lib/SoN/ClassAux.pm:1-13` | 13 | no | XS shim, `require SoN`. **Correct as-is.** |
| `lib/SoN/FieldInfo.pm:1-13` | 13 | no | XS shim. **Correct as-is.** |
| `lib/SoN/OptSuppress.pm:1-13` | 13 | no | XS shim (`suppress_peep`/`restore_peep` swap `PL_rpeepp`). **Correct as-is.** |
| `lib/SoN/Serialize/JSON.pm` | 440 | **no** | Stateless function namespace; `Exporter`, `@EXPORT_OK = qw(to_json)` (:10). All state is parameters. **Correct as a namespace.** |
| `lib/SoN/IR/Serialize/JSON.pm` | 1334 | **no** | Same shape, `@EXPORT_OK = qw(to_json from_json)` (:10). File-scoped `my %CFG_OPS` (:17), `%STAMP_TO_REPR` (:24), `%_REPR_RANK` (:816) are **constant tables**, not mutable state. **Correct as a namespace.** |
| `lib/B/SoN.pm` | 1172 | no | `B` backend. The `-MO=SoN` protocol **requires** `B::SoN::compile` be a package sub. **Cannot be a class** without breaking the interface. |

**Verdict: zero class-style violations.** Every plain package is either an XS
loader, a stateless exporter, or an interface-constrained backend. There is no
stateful plain package anywhere in `lib/`.

**Mechanical / judgement:** neither. Nothing to convert.

### 1b. The `no warnings 'experimental::class'` rule is stale on BOTH sides

The written rule says `feature class` "with `no warnings 'experimental::class';`".
Measured:

```
$ grep -rhn "^use feature|^no warnings|^use experimental" lib --include=*.pm \
    | sed 's/^[0-9]*://' | sort | uniq -c | sort -rn
producer:  92 use experimental 'class';   13 no warnings 'experimental::class';   6 use feature 'class';
chalk:    163 use experimental 'class';   20 no warnings 'experimental::class';
```

85 producer files use `class` with no `no warnings` line — but this is **not a
defect**. `use experimental 'class'` enables the feature *and* disables the
warning in one statement; the separate `no warnings` is redundant where it
appears. Both repos have converged on `use experimental` (92/98 and 163/163).

Probe confirming `use v5.42.0` alone is insufficient (so the pragma is genuinely
load-bearing, just not in the documented spelling):

```
$ cat /tmp/cls_probe.pl
use v5.42.0; use warnings;
class Probe::T { field $x :param = 1; method x { $x } }
$ perl /tmp/cls_probe.pl
Bareword found where operator expected (Do you need to predeclare "class"?) ... syntax error
```

**Finding: the CLAUDE.md rule describes an idiom neither repo uses.** This is a
doc-vs-code drift where the code is right and the doc is wrong.
**JUDGEMENT** — someone must decide to amend `CLAUDE.md`, and decide whether the
6 `use feature 'class'` + 13 redundant `no warnings` files get normalized.

---

## 2. ABOUTME compliance

### 2a. Structural — perfect

```
$ for f in $(find lib -name "*.pm"); do n=$(grep -c "^# ABOUTME:" $f); ...
zero-ABOUTME .pm:  (none)
one-line .pm:      (none)
three-plus .pm:    (none)
zero-ABOUTME .t:   0
one-line .t:       (none)
```

**105/105 `.pm` and 111/111 `.t` have exactly two `# ABOUTME:` lines.** Chalk
matches (168/168). This category is clean on both sides.

### 2b. History-describing ABOUTME — 21 sites

The rule is "what the file DOES, evergreen, no history." Four headers describe
what the code *used to do*:

- `t/from-optree-dor-exit.t:2` — `# ABOUTME: Was: the return was dropped and E//return became DefinedOr(E,E) -- a silent miscompile.`
- `t/from-optree-loop-gaps.t:2` — `...every case here previously MISCOMPILED silently.`
- `t/from-optree-multiconcat.t:2` — `...Const-append (nargs==0) was 4b-4b.`
- `t/from-optree-newops.t:1` — `# ABOUTME: Tests for new typed node generation...` ("new" violates the evergreen-naming rule directly)

Seventeen more embed a zhi ticket ID, which is a pointer to history rather than
a description of behaviour:

```
$ grep -rn "^# ABOUTME:.*zhi" lib t | wc -l   → 17
```
e.g. `t/from-optree-splice-gap.t:2`, `t/from-optree-range-gap.t:2`,
`t/from-optree-subst-gaps.t:1`, `t/from-optree-loop-stamp-fixpoint.t:2`.

**MECHANICAL (17):** stripping a trailing `zhi 019xxxxx` from an ABOUTME is a
regex. **JUDGEMENT (4):** the "Was:" headers must be *rewritten* to state present
behaviour, and rewriting them destroys a real breadcrumb — someone should decide
whether that breadcrumb moves to a body comment rather than being deleted.

False positives I checked and dismissed: `FieldAccess.pm:2` and `PadAccess.pm:2`
say "Used to represent…", which is present-tense usage, not history.

### 2c. `use utf8` missing — 88 files, the largest mechanical bucket

```
producer lib/:  9 of 105 missing
producer t/:   79 of 111 missing
chalk lib/:     0 of 168 missing
chalk t/:       0 of 462 missing
```

The 9 `.pm`: `SoN/ClassAux.pm`, `SoN/Compare.pm`, `SoN/FieldInfo.pm`,
`SoN/FromOptree/OpMap.pm`, `SoN/FromOptree/StackSim.pm`, `SoN/IR/Stamp.pm`,
`SoN/OptSuppress.pm`, `SoN.pm`, `SoN/Render/Text.pm`.

All 105 `.pm` have `use 5.42.0` / `use v5.42.0` — that half is clean.

This is the **starkest producer-vs-chalk divergence in the whole audit**: chalk
is at 630/630, the producer at 128/216. Note the producer is ASCII-only by
constraint (per project memory), so the *risk* is low — but the convention gap
is total.

**MECHANICAL (88).** Pure insertion after the `use 5.42.0` line. The only care
needed: a file that genuinely contains non-ASCII would change meaning, and
none do (the producer is ASCII-only), so this is safe.

---

## 3. Dereferencing

```
postfix (->@* ->%* ->$*):   lib 154   t 246
prefix @$x / %$x:           lib  43   t  25   (code sites, comments excluded)
prefix @{ } / %{ }:         lib   6   t   9
```

Postfix already dominant: **400 postfix vs 71 prefix (85%)**. Chalk is at 205
prefix code sites over 36 KLOC (5.7/KLOC) vs the producer's 37/11.5 KLOC
(3.2/KLOC) — **the producer is the cleaner of the two here.**

Worst files (lib, code sites only, comments excluded):

| File | `@$`/`%$` | `@{`/`%{` |
|---|---|---|
| `lib/SoN/FromOptree.pm` | 15 | 1 |
| `lib/SoN/IR/Serialize/JSON.pm` | 12 | 1 |
| `lib/B/SoN.pm` | 7 | 4 |
| `lib/SoN/Serialize/JSON.pm` | 2 | 0 |
| `lib/SoN/IR/Stamp.pm` | 1 | 0 |

Six of the 43 raw `lib` hits are **inside comments quoting Perl source**
(`FromOptree.pm:159,725,1454,1496,1499,1502` — e.g. `# left by a symbolic
`@$str` deref`). Those are documentation of the language being compiled and
must not be touched. Net code sites: **37**.

### MECHANICAL (62 of 71)

The dominant shape is `keys %$h` / `values %$h` / `for my $x (@$a)`:

- `lib/SoN/IR/Serialize/JSON.pm:761,832,930,1153,1179,1204,1226,1244,1276,1278,1305` — all `sort keys %$graphs` / `values %$graphs` → `$graphs->%*`
- `lib/SoN/FromOptree.pm:539,3392,3853,3865,3881,4445,4488,4691` — `keys %$arm_scope` etc.
- `lib/B/SoN.pm:241,354,417,840` — `sort keys %$stash`
- `lib/B/SoN.pm:41,950`, `lib/SoN/Serialize/JSON.pm:58`, `lib/SoN/FromOptree.pm:985,1000,1014,1033,2567` — `@$exits`, `@$fields`, `@$preds`

### JUDGEMENT (9)

- **3 symbolic stash refs — DO NOT CONVERT.** `lib/B/SoN.pm:197` `my $stash =
  \%{"${cname}::"}`, `:422` `\%{"${pkg_name}::${sub_pkg_short}::"}`, `:916`
  `\%{"${parent}::"}`. These deref a *string* symbolically; there is no arrow
  form. Converting is impossible, not merely risky.
- **1 already correct:** `lib/SoN/FromOptree.pm:986`
  `$exits->[0]->@{qw(control value)}` is already a postfix hash slice; my `@{`
  grep matched the `@{qw(...)}` text. Not a violation.
- **1 boolean-context deref:** `lib/SoN/Serialize/JSON.pm:435` `if defined
  $classes && %$classes` and `lib/SoN/IR/Serialize/JSON.pm:680` `if (ref
  $data->{classes} eq 'HASH' && %{ $data->{classes} })`. `%$h` in boolean
  context → `$h->%*` changes to list context; needs `keys %$h` or explicit
  scalar. **Needs thought.**
- **4 `@{ EXPR // [] }` in tests:** `t/args-source-node.t:23`,
  `t/entry-def-node.t:23`, `t/underscore-is-not-args.t:23,53,60,76,87`. Shape is
  `@{ ($wire->{methods}{$graph} // {})->{nodes} // [] }` — the `//` fallback sits
  *between* the expression and the deref, so postfix requires restructuring into
  a temporary. Mechanical-ish but not sed-able.
- **1 deliberate oddity:** `t/from-optree-translate-root.t:25` contains
  `(\@{\$g->returns} ? "yes" : "no")` inside a generated-source string.

---

## 4. Booleans

```
$ grep -rn "return\s+(1|0)\s*;" lib --include=*.pm     → 18
$ grep -rn "\?\s*1\s*:\s*0|\?\s*0\s*:\s*1" lib          → 7
$ grep -rc "\b(true|false)\b" lib | sum                 → 123 uses
```

`true`/`false` is already the house style (123 uses); these 25 are the residue.
Attributed to enclosing sub by script:

| Sub | Site | Predicate? |
|---|---|---|
| `_is_postfix_while` | `FromOptree.pm:2937` (3) | **yes** |
| `_is_comparison` | `FromOptree.pm:3159` (1) | **yes** |
| `_cond_stores_memory` | `FromOptree.pm:3253` (1) | **yes** |
| `_cond_reads_memory` | `FromOptree.pm:3285` (1) | **yes** |
| `_body_has_modifier_andor` | `FromOptree.pm:3968` (2) | **yes** |
| `_arm_has_element_store` | `FromOptree.pm:4031` (1) | **yes** |
| `_arm_has_field_store` | `FromOptree.pm:4054` (1) | **yes** |
| `_arm_has_void_call_from` | `FromOptree.pm:4104` (1) | **yes** |
| `_arm_has_direct_call_from` | `FromOptree.pm:4177` (1) | **yes** |
| `_arm_has_die_from` | `FromOptree.pm:4202` (1) | **yes** |
| `_body_stores_memory` | `FromOptree.pm:4233` (1) | **yes** |
| `_cond_drains_array` | `FromOptree.pm:4257` (1) | **yes** |
| `_op_uses_args` | `B/SoN.pm:711` (2) | **yes** |
| `_emit_package` | `B/SoN.pm:58` (1) | **yes** |
| `is_statement_node` | `NodeFactory.pm:441` (1) | **yes** |
| `_find_join_addr` | `FromOptree.pm:3947` (1) | no — returns an address |
| `_translate_from` | `FromOptree.pm:215` (2) | no — `is_program => ... ? 1 : 0` is a **wire field** |
| `remove_node` | `NodeFactory.pm:425` (1) | **yes** (`return defined $node ? 1 : 0`) |
| `_make_package_filter` | `B/SoN.pm:39` (2) | mixed — `$has_include = %$include ? 1 : 0` is internal |

Note the internal inconsistency worth flagging: `FromOptree.pm:3159`
`_is_comparison` mixes both idioms — `return 1 if ...` at :3163 while the same
file uses `return false` at `FromOptree.pm:3063`. Same file, same concept, two
spellings.

**MECHANICAL (23):** the 15 clearly-named predicates plus `remove_node`,
`is_statement_node`, `_emit_package`. `1`→`true`, `0`→`false`, `? 1 : 0` → the
bare condition or `? true : false`.

**JUDGEMENT (2):**
- `FromOptree.pm:254,885` `is_program => (defined $program_root ? 1 : 0)` — this
  value is **serialized into the wire JSON**. `true`/`false` are `JSON::PP`-
  visible as booleans and may change the emitted JSON from `1` to `true`,
  which the consumer parses. **Do not convert without checking the wire
  contract.** This one could silently break chalk.
- `B/SoN.pm:42` `$has_include = %$include ? 1 : 0` — hash-in-boolean-context,
  intersects finding 3's judgement bucket.

---

## 5. Signatures — 27 subs, 26 in one file

```
$ grep -rn "^\s*(sub|method)\s+\w+" lib --include=*.pm | wc -l          → 348
$ grep -rn "^\s*(sub|method)\s+\w+\s*\(" lib --include=*.pm | wc -l     → 320
$ grep -rn "=\s*@_\s*;" lib --include=*.pm | wc -l                      → 29
```

**320/348 = 92% already on signatures.** Zero `my $x = shift` sites. The debt is
concentrated:

| File | non-signature subs |
|---|---|
| `lib/B/SoN.pm` | **26** |
| `lib/SoN/FromOptree.pm` | 1 |

All 26 in `B/SoN.pm`: lines 39, 58, 66, 127, 180, 234, 286, 320, 341, 443, 456,
478, 543, 606, 618, 704, 711, 789, 815, 935, 1006, 1022, 1046, 1082, 1127, 1145.

For calibration, chalk has **152** `= @_;` sites against the producer's 29 —
chalk is the worse offender in absolute and normalized terms. `B/SoN.pm` is
simply the producer's one unmigrated file.

**MECHANICAL (26):** `sub f { my ($x,$y) = @_;` → `sub f ($x, $y) {`. Two
cautions that make this "mechanical with a checklist" rather than blind sed:
`compile` (:66) is called by perl's `-MO=` protocol with a variadic arg list, and
several take optional trailing args needing `= undef` defaults.

**JUDGEMENT (1):** `lib/SoN/FromOptree.pm:4728` `sub _scope_key_order {` — this
one **must not** get a signature. It is a `sort` comparator; it reads the `$a`
and `$b` globals and takes no arguments. See finding 7.

---

## 6. `eval {}` — 31 sites, and I do NOT recommend converting them

```
$ grep -rn "\beval\s*\{" lib --include=*.pm | wc -l   → 31
$ grep -rn "\beval\s+[\"'$]" lib --include=*.pm        → (no output — zero string eval)
$ grep -rn "\$@" lib --include=*.pm                    → 1 site
$ grep -rn "try\s*\{" lib --include=*.pm               → 4 sites, all B/SoN.pm
```

Distribution: `B/SoN.pm` 26, `FromOptree.pm` 4, `StackSim.pm` 1.

**Zero string eval in `lib/`.** The `eval '...'` occurrences are confined to
`t/` where they compile the Perl source under test — a different construct and
correct usage.

### The key distinction

The producer **already uses try/catch where errors are handled**:
`B/SoN.pm:142, 262, 303, 382`, e.g. at :142-156:

```perl
try {
    $graphs{'main::__PROGRAM__'} = SoN::FromOptree->translate_root();
}
catch ($e) {
    if ($e =~ /^GAP:/) { warn "B::SoN: skipped main::__PROGRAM__: $e" }
    else { warn "B::SoN: INTERNAL ERROR translating ... : $e" }
}
```

All 31 `eval {}` sites are **expression guards over the `B::` API**, not error
handling. The shape is uniformly "call a `B` accessor that dies on the wrong
node type, take undef otherwise":

- `B/SoN.pm:250` `my $start = eval { $cv->START };`
- `B/SoN.pm:445` `my $file = eval { $cv->FILE };`
- `B/SoN.pm:609-614` `eval { $cv->PADLIST } or return undef;` …
- `FromOptree.pm:1251` `$self_class = eval { $cv->GV->STASH->NAME };`
- `StackSim.pm:128` `my $id = eval { $node->id };`

Exactly **one** inspects `$@`: `B/SoN.pm:579`
`( $mandatory, $optional, $slurpy ) = ( 0, 0, '' ) if $@;` — and even that is a
default-on-failure, not error handling.

**JUDGEMENT (all 31).** The global rule says "try/catch, not eval blocks", but
that rule targets *error handling*, and none of these are. Rewriting
`my $x = eval { $o->M };` as a 5-line try/catch would make the code
substantially worse for zero correctness gain. My reading is that the honest
answer is a **documented exemption for expression guards**, not 31 conversions —
but that is perigrin's call, not mine, and I am flagging it as the one category
where I think literal compliance would be a net negative.

If any conversion is wanted, `B/SoN.pm:579` is the only site with real
error-handling semantics (`$@` inspection) and is the defensible one to change.

---

## 7. `$a` / `$b` — 28 sites, all latent, one file-level hazard

### The probe (reproducing the known bug class)

The `SoN/IR/Stamp.pm:92-93` comment records a real historical bug. I reproduced
the mechanism to establish which shapes are dangerous:

```perl
# /tmp/ab_probe2.pl
sub outer {
    my ($a, $b) = (99, 98);
    my @r = sort { $a <=> $b } (3,1,2);   # comparator sees the LEXICALS
    return join ",", @r;
}
package P { my ($a, $b); sub cmp2 { $a <=> $b } sub go { join ",", sort cmp2 (3,1,2) } }
```
```
"my $a" used in sort comparison at line 6.
inline-block-with-enclosing-lexical: 2,1,3      <-- WRONG, should be 1,2,3
named-sub-enclosing-lexical:         3,1,2      <-- WRONG, unsorted
```

Both return **silently wrong order**. The named-sub case emits **no warning at
all**. That is the shape to hunt.

Counter-probe establishing the boundary — a lexical in the *caller* is harmless:
```
sub hazard { my ($a,$b) = (99,98); return join ",", sort bykey (3,1,2) }
hazard: 1,2,3      <-- correct; the hazard is the COMPARATOR's scope, not the caller's
```

### `lib/` — 3 real sites

1. **`lib/SoN/FromOptree.pm:4728-4736` `_scope_key_order`** — the comparator.
   Reads `$a`/`$b` globals. **This is correct and must stay**; it is called at
   `:539, 3031, 3242, 3392, 4489, 4691`.

2. **`lib/SoN/FromOptree.pm:3858` — the one that matters**
   ```perl
   my ($a, $b) = $m->inputs->@*;
   $m->set_stamp(SoN::IR::Stamp::join($a->stamp, $b->stamp))
   ```
   A `my ($a,$b)` lexical **in the same file as a named `$a`/`$b` comparator**.
   Assessed for live hazard:
   - Enclosing sub: `_walk_loop_body` (`:3650`), which spans **3650–3946**
     (next sub `_find_join_addr` at `:3947`).
   - `_scope_key_order` at `:4728` is a **sibling**, not nested inside — so the
     lexical does not shadow the comparator's globals.
   - `grep sort` over lines 3650–3946: **zero sort calls** in that range.
   - `perl -Ilib -Iblib/lib -Mwarnings -c lib/SoN/FromOptree.pm` → `syntax OK`,
     no "used in sort comparison" warning.

   **LATENT, not live.** But it is one refactor away from live: adding any
   `sort _scope_key_order` inside `_walk_loop_body`, or moving either sub, turns
   it into the silent-miscompile shape above. Given `_scope_key_order` is called
   6 times elsewhere in this exact file, that refactor is plausible.

3. **`lib/SoN/Compare.pm:25,29`** — `my $a = $nodes_a[$i];` / `my $b =
   $nodes_b[$i];` inside `method diff`, used through `:74`. `grep -n sort
   lib/SoN/Compare.pm` → **no output**. Latent. Meaningful because `Compare.pm`
   is a *graph-diffing* module — sorting node lists is exactly the feature
   someone would add to it next.

Correctly-handled reference case: `lib/SoN/IR/Stamp.pm:94` `sub meet ($left,
$right)` with the comment at `:92-93` explaining why, and a real comparator at
`:108` `sort { _depth($b) <=> _depth($a) || $a cmp $b }` using the globals
properly. Same pattern at `IR/Serialize/JSON.pm:1010,1086` and
`IR/Graph.pm:249`.

### `t/` — 25 real lexical sites

Measured with a script that strips quoted strings first, because a naive grep
mostly matches Perl-source-under-test inside `translate('sub { my $a = ... }')`:

`t/ir-data-nodes.t` (8: :22,23,30,43,51,60,72,89), `t/ir-nodefactory.t` (6:
:14,15,22,23,29,30), `t/stacksim.t` (3: :29,30,82), `t/ir-node.t` (2: :26,27),
`t/base-classes.t:94`, `t/entry-def-node.t:58`,
`t/from-optree-computed-stamps.t:50,59`, `t/from-optree-newops.t:25`,
`t/from-optree-padaccess-identity.t:52`.

`grep -c sort` on all 9 files: **0, 0, 0, 0, 0, 0, 0, 0, 0**. All latent.

**MECHANICAL (26):** the 25 test lexicals and `Compare.pm` rename to
`$left`/`$right` or `$node_a`/`$node_b` — same rename `Stamp.pm` already made.
**JUDGEMENT (2):** `_scope_key_order` must be **left alone** (renaming its
globals breaks the sort), and `FromOptree.pm:3858` should be renamed *because*
it shares a file with that comparator — a reviewer needs to understand which of
the two is which before touching either.

---

## 8. The mirror obligation

chalk `lib/Chalk/Grammar/Perl/TypeLibrary.pm:12-14` states the contract:

> This is the CANONICAL lattice. […] B::SoN's `SoN::IR::Stamp` mirrors this
> table; the two must not drift.

Measured. The mirror is in remarkably good shape structurally:

```
producer lib/SoN/IR/Node/:  88 classes
chalk    lib/Chalk/IR/Node/: 88 classes
names only in producer: (none)
names only in chalk:    (none)
shared: 88
```

`Node.pm` field lists are **identical** (`id, inputs, consumers, stamp,
compat_class, control_in, schedule_data, representation`), and `Graph.pm` method
lists are identical (`_seed, merge, unmerge, next_cfg_id, members, start,
returns, nodes`). Lattice `%PARENTS`/`%PARENT` tables agree on all 27 members.

Five real divergences:

### 8a. Lattice API naming — JUDGEMENT

| Concept | producer (`SoN::IR::Stamp`) | chalk (`TypeLibrary`) |
|---|---|---|
| subtype test | `is_subtype_of` (:79), **method on an object** | `is_subtype` (:221), **sub on two strings** |
| LUB | `join` (:121) | `join_types` (:276) |
| GLB | `meet` (:94) | `meet_types` (:307) |
| operand type | `SoN::IR::Stamp` object | bare string |

Someone moving between repos writes `$stamp->is_subtype($other)` and gets a
method-not-found, or writes `join_types($a,$b)` and gets Perl's builtin `join`.
The producer's `sub join` shadowing `CORE::join` inside the class block is the
sharper edge of the two.

### 8b. Reflexivity + membership — ALREADY FILED, cross-reference only

`is_subtype(T,T)` is `true` in chalk (`TypeLibrary.pm:222`) and `false` in the
producer (`Stamp.pm:81` `return false if $type eq $other_type`). Fully
documented with a 729-pair exhaustive diff in
`docs/plans/2026-08-24-lattice-reflexivity-and-membership.md` (status: FILED,
COORDINATOR-VERIFIED, latent). **Not re-reported here.**

### 8c. Encoding of the parent table — MECHANICAL, low value

producer `Stamp.pm:12-38` `Scalar => [qw(List)]` (arrayref, multi-parent
capable, DAG); chalk `TypeLibrary.pm:18-55` `Scalar => 'List'` (scalar, tree).
No producer entry has more than one parent, so the arrayref capability is
unused. Same semantics, two spellings — a maintainer editing both tables in one
sitting must switch syntax mid-edit.

### 8d. Producer ABOUTMEs say "Chalk" — 75 files — MECHANICAL

```
$ grep -rln "^# ABOUTME:.*Chalk" ~/dev/perl5-son/lib | wc -l   → 75
```
e.g. `lib/SoN/IR/Node/Not.pm:1` `# ABOUTME: Logical negation operation node in
the Chalk IR.`, `lib/SoN/IR/NodeFactory.pm:1` `# ABOUTME: Factory for Chalk IR
nodes…`.

Detected as a side effect of namespace-normalized diffing: the producer's header
survived `s/SoN/X/g` and still read "Chalk". Arguably *correct* — memory records
"single IR is a CONTRACT in the CODE COMMENTS" — but 75 files in `SoN::` naming
their contents "the Chalk IR" will read as a copy-paste error to anyone who has
not read that decision. Deliberate-or-accident is **not resolvable from the code
alone**: UNVERIFIABLE without perigrin's intent.

### 8e. chalk has two node-classification methods the producer lacks — JUDGEMENT

```
identity_kind:  chalk 63 node classes,  producer 0
staleness_kind: chalk 77 node classes,  producer 0
```

Typical diff (`IR/Node/Not.pm`, namespace-normalized):
```
> method staleness_kind() { 'transparent' }
> sub identity_kind { 'hash_consed' }
```

This accounts for 84 of the 88 node classes differing (only `Aggregate.pm`,
`BinOp.pm`, `Regex.pm`, `UnaryOp.pm` are byte-identical after normalization).
Related in-flight work: `docs/plans/2026-08-22-identity-kind-and-argssource-shape.md`
and `docs/plans/2026-08-23-dispatch-kind-conflates-two-axes.md`.

**Not a style violation** — it is a genuine capability gap, and whether the
producer *should* mirror these is a design question those two plans own. Flagged
here because it is the largest measured divergence in a pair of trees that are
otherwise 88-for-88 identical, and because chalk's contract comment says the two
"must not drift."

---

## Cross-references

- `docs/plans/2026-08-24-lattice-reflexivity-and-membership.md` — owns 8b; this
  audit adds 8a (naming) and 8c (encoding) to the same seam.
- `docs/plans/2026-08-22-identity-kind-and-argssource-shape.md`,
  `docs/plans/2026-08-23-dispatch-kind-conflates-two-axes.md` — own 8e.
- `docs/plans/2026-08-24-two-ir-architecture-alignment.md`,
  `docs/research/2026-08-22-lattice-unification-audit.md` — the mirror obligation.
- chalk `CLAUDE.md` "Code Style" — the plan oracle for 1-7; **needs amendment**
  per 1b (`no warnings 'experimental::class'` is not the idiom either repo uses).

## Deferrals, named

- **Where finding 0 goes:** unowned. No plan document currently covers producer
  convention documentation. Needs a decision or a new issue; I am not filing one.
- **Finding 6 exemption:** unowned. Requires perigrin to rule on whether
  expression-guard `eval` is exempt from the try/catch rule. Until ruled, the
  producer is in nominal violation on 31 sites nobody should touch.
