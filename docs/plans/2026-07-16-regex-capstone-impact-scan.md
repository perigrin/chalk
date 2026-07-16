# ABOUTME: Measured regex-feature impact scan over lib/ to scope the atom-list
# ABOUTME: vs regex-as-subgraph rewrite decision against the Phase-5 capstone.

# Regex feature impact scan (2026-07-16)

## Why this exists

The current regex backend (`_compile_regex_pattern` + `_emit_regex_matcher` in
`lib/Chalk/Target/LLVM/Context.pm`) compiles a literal pattern into a **flat,
ordered atom list** and walks it position-threaded to emit inline LLVM. That
representation has a structural ceiling: it has **no branch structure**, so
alternation (`a|b`) cannot be expressed, and a group is only two zero-width
marker atoms, so quantified groups (`(...)+`) cannot be expressed either.

The agreed end-state (perigrin, this session) is to treat a regex as a proper
sub-language: parse it into its **own IR graph** and lower it almost like a
sub/method subgraph, reusing Chalk's Sea-of-Nodes control+data IR. That is a
project unto itself (regex grammar + parser + IR + lowering).

Two decisions were separated:

1. **Stop investing in the atom-list compiler** — no incremental feature work
   (`/i` flags, `\b`, etc.) on a representation we intend to replace. Agreed.
2. **Start the graph rewrite now** — deferred. Reasons independent of (1): it
   would open a SECOND large architectural front while the MOP/Target::C
   migration is still parked mid-migration (one big front at a time), and we
   had no data to scope it.

This scan supplies the data for (2): **how much does regex actually block the
Phase-5 capstone, and which features carry the block.**

## Method

`scratchpad/regex_scan.pl` (throwaway analyzer) walks all 165 `lib/**/*.pm`,
extracts `/`-delimited regex operators (`=~`, `!~`, `s///`, `qr//`) with their
pattern text and flags, and classifies each pattern by the first backend
feature it needs that the current atom-list compiler does NOT support.

**Scan limits (honest):** source-level, not optree-level. It misses non-`/`
delimiters (`m{...}`, `s{}{}`), interpolated/runtime patterns, and its
`mid-anchor` heuristic mis-fires on `\Q$var\E` interpolations (the `$` inside
quotemeta is not an anchor). The `mid-anchor` bucket is therefore NOISE and is
excluded from the conclusion; every other bucket keys on a construct
(`|`, `)+`, `\b`, a flag letter) that appears verbatim in the pattern text —
which is exactly what the optree `precomp` string also carries — so those
buckets are reliable directionally.

## Results

- **165 lib/ files total; only 24 contain any regex at all** (the other 141
  are regex-free — regex is not a broad blocker).
- **357 `/`-delimited regex sites** scanned: 186 `=~`, 143 `s///`, 15 `qr//`,
  13 `!~`.
- **202 (57%) lower on the CURRENT compiler today**; 155 (43%) hit ≥1
  unsupported feature.

### The blocking load is concentrated in ~3 self-hosting files

Regex sites by file (top of 24):

| sites | file | tier |
|------:|------|------|
| 152 | `Bootstrap/Perl/Target/EmitHelpers.pm` | self-hosting codegen |
| 109 | `Bootstrap/Perl/Actions.pm` | self-hosting parser actions |
|  97 | `Bootstrap/Perl/Target/C.pm` | self-hosting codegen |
|  49 | `Target/LLVM/Context.pm` | the regex backend itself |
|  38 | `Bootstrap/Perl/Target/Perl.pm` | self-hosting codegen |
| ...  | (19 more files, ≤18 sites each) | mixed |

The three biggest (`EmitHelpers`, `Actions`, `Target/C` = ~358 sites) are the
**`Bootstrap::Perl` self-hosting frontend** — the codegen/parser tier that is
the LAST thing to self-host, not the core runtime path. The genuinely-hard
features live almost entirely there.

### Blocked patterns by first blocker (what a rewrite must cover, by impact)

| feature | patterns | files | notes |
|---------|---------:|------:|-------|
| `s///g` (flags) | 69 | 8 | global substitution — loop match+splice |
| alternation `\|` | 28 (47 any-use) | 5 | THE representation-bender; no branch struct today |
| `/r` (flags) | 13 | 5 | non-destructive s/// — cheap, orthogonal |
| quantified group `(...)+` | 13 (18 any-use) | 6 | needs group-as-subgraph |
| assertion escapes `\b \A \z \G` | 10 (25 any-use) | 6 | word boundary etc. |
| non-greedy `*?` | 1 (4 any-use) | 3 | rare |
| `mid-anchor` | (excluded — scan noise) | | `\Q$var\E` false positives |

## Interpretation

1. **Regex is NOT a broad capstone blocker.** 141/165 files are regex-free;
   57% of regex sites already lower. Regex is one gap class, not a wall.
2. **The block concentrates in the self-hosting frontend**, which is
   capstone-*late* (the codegen tier self-hosts last). The core runtime path
   is far less regex-dependent.
3. **The two features that carry the load are `s///g` and alternation.**
   `s///g` is a loop-the-existing-matcher problem (does NOT need the graph
   rewrite — it can ride the current matcher). Alternation is the one that
   genuinely needs branch structure the atom list cannot express.
4. **The hard, rewrite-only features (alternation, quantified groups,
   non-greedy) total ~42 blocked patterns across ~6 files** — real, but a small
   and concentrated target, not a pervasive one.

## Decision

- **Regex work goes COLD, not incremental-on-the-dead-end and not
  rewrite-now.** No `/i`/`\b`/flag features on the atom-list compiler (throwaway
  against the intended rewrite). The subsystem stays where it is: R1–R7 GREEN,
  everything else a loud GAP.
- **The regex-as-subgraph rewrite is filed as a PARKED project** (zhi issue,
  this doc as its scoping data), blocked behind: (a) the MOP/Target::C
  migration resolving so there is only one big architectural front at a time,
  and (b) the self-hosting frontend tier actually becoming the capstone
  frontier (it is not yet).
- **`019eb073` (G6 fast-follows) is re-tagged**: its remaining items are
  SUPERSEDED by the rewrite, not TODO on the current compiler — so the DAG does
  not keep offering "/i flags" as a ready leaf and pull `-auto` back into the
  dead end.
- **`-auto` routes to the non-regex capstone frontier** (loop/field/element/
  control-flow shapes), where throughput actually is.

## Scoping the eventual rewrite (for when it un-parks)

The measured feature set the rewrite must cover, in priority order by blocked
impact: alternation → quantified groups → `s///g` (may ride the current matcher
instead) → assertion escapes (`\b \A \z \G`) → flags (`/i /m /s /x /r`) →
non-greedy. `\G` anchored continuation (in `Actions.pm`'s own `/\G.../gc` scan
loop) needs match-position state threading and is the parser's self-scan — a
distinct sub-requirement. Backrefs: ~0 real uses, lowest priority.
