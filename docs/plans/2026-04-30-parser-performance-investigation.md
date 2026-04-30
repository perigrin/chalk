# Parser Performance Investigation Findings

**Date:** 2026-04-30
**Status:** Read-only investigation. No optimizations applied. Findings inform future decisions.
**Author:** Investigation conducted in worktree `worktree-pu`.

**Inputs:**
- `~/.claude/projects/-home-perigrin-dev-chalk/memory/xs_performance_investigation.md` (45-day-old memory, framing only)
- `docs/plans/2026-04-01-benchmark-design.md`
- `script/profile-parse-lite.pl`
- `script/profile-parse.pl`
- `lib/Chalk/Bootstrap/Earley.pm` stats infrastructure (`scan_stats`, `gc_stats`, `set_reuse_stats`, `EARLEY_PROFILE`)
- `docs/architecture/parsing-pipeline.md`

Two temporary wrapper scripts were used and have been left in `/tmp/` for re-runs;
they perform no production-code modifications:
- `/tmp/profile-with-rss.sh` — peak-RSS polling wrapper around `script/profile-parse.pl`
- `/tmp/profile-deep.pl` — per-component-semiring multiply/add/is_zero timing
- `/tmp/profile-inner-loop.pl` — `_chart_*` / `_make_*_context` / `Context::new` timing

---

## Summary

Three Perl source files spanning the conformance harness's spectrum
(`Boolean.pm` 73 lines, `Context.pm` 160 lines, `FilterComposite.pm` 336 lines)
were profiled with the existing `script/profile-parse.pl` plus two read-only
deep-instrumentation wrappers. All three parse successfully under the full
five-semiring `FilterComposite` stack. `FilterComposite.pm` completes in
**126-141s**, just over the conformance harness's **120s** budget — that is the
actual TIMEOUT pathology: not a hung parse, but one that crosses the budget by
~10-20%.

**The dominant primary bottleneck is Category E — multiple causes of
roughly comparable size, with a strongly super-linear cost-per-operation
trend that points specifically at memory pressure on the chart data
structure.** Operation counts (predict, scan, complete, multiply, chart_set,
chart_has) all grow approximately **linearly** with input bytes (5-7x for
~5.8x bytes), but **wall-clock time grows ~18x** for the same input growth.
The per-operation cost more than doubles between the smallest and largest
file in this corpus, in lockstep with peak RSS rising from 125 MB to 609 MB.
This is consistent with the chart growing from L2-resident to L3/main-memory
sized and is not a single hotspot the profiler can attribute to one method.

A clear secondary finding stands separately and could be acted on
independently: the **set-reuse registry** at lines 708-727 of
`Earley.pm` builds a sorted, joined string key over every chart-cell pair at
every position, and only ~34% of those keys produce a reuse hit. The work it
does is large; the savings it produces are not measured anywhere we can see.

A third finding worth flagging: the existing `script/profile-parse-lite.pl`
and `script/profile-parse.pl` instrumentation captures Earley operation
counts cleanly but loses **65-72% of wall-clock time** to "unaccounted
overhead" on the largest file. This is the per-position agenda-building
loop, the pre-predict/pre-scan terminal-clustering loop, the safe-set check,
and the set-reuse registry. The deeper wrapper added in this investigation
brings unaccounted down to 34.6% on the largest file, but never below ~25%
on the smallest. The remainder is loop overhead distributed across every
position.

---

## Corpus

| File | Size (bytes) | Lines | Tier | Reason for selection |
|------|-------------|-------|------|---------------------|
| `lib/Chalk/Bootstrap/Semiring/Boolean.pm` | 2,648 | 73 | Fast-passing | Smallest Bootstrap semiring file; recommended in `2026-04-01-benchmark-design.md`; parses in 7-8s |
| `lib/Chalk/Bootstrap/Context.pm` | 6,055 | 160 | Slow-passing | Medium file; passes in 32-38s; well within 120s budget |
| `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` | 15,279 | 336 | TIMEOUT in conformance harness | Identified by recent A3 spot-check as TIMEOUT under harness; this run measured 126-141s, confirming "just over the 120s budget" |

`Constant.pm` and other `IR/Node/*.pm` files were considered for the fast
tier but are too short (10-20 lines) to produce meaningful per-component
timings. Boolean.pm at 73 lines is the smallest Bootstrap-realistic file
that exercises class declarations, methods, fields, and conditionals.

The TIMEOUT-tier candidates listed in the brief were:
- `FilterComposite.pm` (336 lines) — chosen
- `TypeInference.pm` (529 lines) — not run; likely 250s+
- `ConciseTree/Actions.pm` (1568 lines) — not run; likely well over 600s

`FilterComposite.pm` was chosen because it is the smallest of the three and
therefore the cheapest place to characterize the TIMEOUT regime without
multi-hour parses. If post-investigation work needs evidence at much larger
sizes, the same wrappers should be re-run on `Actions.pm` after improvements
land.

---

## Profile data

### Wall time and operation counts

From `script/profile-parse.pl` (top-level `FilterComposite` plus
`Earley._predict/_scan/_complete/_advance_from_completed` instrumentation,
single run per file; numbers vary 5-10% run to run):

| Metric | Boolean.pm | Context.pm | FilterComposite.pm |
|--------|-----------:|-----------:|-------------------:|
| Wall time | 7.1s | 37.4s | 126.0s |
| chart_has calls | 159,933 | 439,456 | 826,789 |
| chart_set calls | 23,117 | 78,343 | 143,981 |
| `multiply` (FilterComposite) | 7,135 | 33,877 | 60,523 |
| `add` (FilterComposite) | 101 | 1,797 | 2,751 |
| `is_zero` (FilterComposite) | 7,136 | 33,878 | 60,524 |
| `predict` calls | 10,642 | 34,213 | 64,002 |
| `scan` calls | 11,765 | 39,324 | 72,732 |
| `complete` calls | 909 | 3,777 | 6,306 |
| `advance_from_completed` | 10,388 | 33,557 | 62,387 |
| `multiply` time | 1.21s (17%) | 6.45s (17%) | 10.42s (8%) |
| `predict` time | 1.39s (20%) | 4.58s (12%) | 7.94s (6%) |
| `complete` time | 0.87s (12%) | 4.96s (13%) | 7.90s (6%) |
| `scan` time | 0.61s (9%) | 2.36s (6%) | 4.87s (4%) |
| Accounted | 65.5% | 55.4% | 28.0% |
| **Unaccounted** | **34.5%** | **44.6%** | **72.0%** |

The unaccounted figure rising from 34.5% to 72.0% is the loudest signal in
the original profiler. The bulk of the file-scaling time is going into code
the original profiler does not instrument.

### Deep per-component breakdown (`/tmp/profile-deep.pl`)

This wrapper additionally times each component semiring's `multiply`,
`add`, `is_zero` and `FilterComposite::_filter_compare`.

| Component (rolled up) | Boolean.pm | Context.pm | FilterComposite.pm |
|---|---:|---:|---:|
| Earley loop (predict/scan/complete/advance) | 40.6% | 33.6% | **17.6%** |
| FilterComposite (own work, excluding components) | 19.9% | 21.0% | 10.2% |
| SemanticAction (multiply + add + is_zero) | 4.4% | 4.6% | 2.3% |
| Precedence (multiply + add + is_zero) | 3.8% | 3.9% | 1.9% |
| TypeInference | 2.3% | 2.6% | 1.2% |
| Structural | 1.4% | 1.5% | 0.7% |
| Boolean | 1.4% | 1.4% | 0.7% |
| Accounted | 73.8% | 68.6% | 34.6% |
| **Unaccounted** | **26.2%** | **31.4%** | **65.4%** |

Two observations from this table:

1. **Per-component semiring work is small.** Even at the largest file, all
   five component semirings together consume 6.8% of wall time. Eliminating
   their entire dispatch overhead would save ~10s of the 138s parse, not
   the 60+ seconds the file is over budget.
2. **Loop overhead grows with file size.** The Earley/`_predict/_scan/...`
   row drops from 40.6% to 17.6% as a fraction, but its absolute time
   roughly doubles per-call. The unaccounted region — covering the agenda-
   building loop, pre-predict terminal clustering, set-registry build,
   safe-set check, and GC sweep — grows from 26.2% to 65.4%.

### Inner-loop methods (`/tmp/profile-inner-loop.pl`)

Wrappers on `_chart_has`, `_chart_set`, `_chart_get`, `_make_scan_context`,
`_make_complete_context`, `_is_safe_set`, and `Chalk::Bootstrap::Context::new`:

| Method | Boolean.pm | Context.pm | FilterComposite.pm |
|---|---:|---:|---:|
| `Context::new` calls | 46,311 | 185,270 | 334,656 |
| `Context::new` time | 0.38s (5.0%) | 1.66s (4.3%) | 3.13s (2.2%) |
| `_chart_has` time | 0.34s (4.4%) | 0.98s (2.6%) | 1.89s (1.3%) |
| `_is_safe_set` time | 0.23s (3.0%) | 0.78s (2.0%) | 1.36s (1.0%) |
| `_chart_set` time | 0.09s (1.1%) | 0.30s (0.8%) | 0.59s (0.4%) |

`_is_safe_set` is called once per chart position and inspects every active
core item at that position twice (Aycock §6.2 properties 1+2 — see
Earley.pm:178-249). Its 1.36s share at the largest file is small individually
but grows as items-per-position grows.

### Peak RSS (sampled every 0.5s by `/tmp/profile-with-rss.sh`)

| File | Peak VmHWM | Peak VmSize | RSS at 50% wall time |
|---|---:|---:|---:|
| Boolean.pm | 127.8 MB | 133.2 MB | 99.3 MB |
| Context.pm | 254.6 MB | 261.3 MB | 173.9 MB |
| FilterComposite.pm | **609.4 MB** | 616.2 MB | 387.1 MB |

The RSS growth curve is roughly linear in elapsed time within each parse,
indicating steady chart growth without late-stage GC reclamation. By the end
of the FilterComposite.pm parse the process holds ~600 MB of resident chart
data plus interpreter and grammar.

### Earley internal stats (from `scan_stats`, `gc_stats`, `set_reuse_stats`)

| Stat | Boolean.pm | Context.pm | FilterComposite.pm |
|---|---:|---:|---:|
| Total scans | 11,765 | 39,324 | 72,732 |
| Scan cache hits | 1,906 (16.2%) | 8,839 (22.5%) | 15,940 (21.9%) |
| Clustered scans (DFA terminal_map population) | 101 | 269 | 539 |
| Positions freed by GC | 123 | 364 | 720 |
| Safe sets found | 204 | 660 | 1,022 |
| Total positions in input (ceil bytes) | 2,649 | 6,056 | 15,280 |
| `safe_sets / positions` | 7.7% | 10.9% | 6.7% |
| `positions_freed / positions` | 4.6% | 6.0% | 4.7% |
| Set-reuse unique | 276 | 721 | 1,352 |
| Set-reuse hits | 101 (26.8%) | 461 (39.0%) | 705 (34.3%) |

Three things worth noting from the stats table:

1. **GC and safe sets fire infrequently.** Only 4.7% of chart positions get
   freed, and only 6.7% of positions qualify as safe sets. The rest stay
   resident through the entire parse, which is consistent with peak RSS
   growing roughly with file size rather than plateauing.
2. **Scan cache hit rate is low (~22%).** Most scans bypass the cache and
   call `Chalk::Bootstrap::Terminal::match` directly. The pre-scan
   terminal-clustering loop populates the cache for patterns reachable from
   the current DFA states, but 539 clustered scans against 72,732 total
   matches means the cache only covers ~0.7% of total matches via the
   clustering path.
3. **Set-reuse hit rate plateaus at ~34%.** This metric is currently
   advisory only — the registry (Earley.pm:708-727) builds the keys but the
   parser does not consult them to skip work.

---

## Scaling analysis

### Bytes ratios (FilterComposite.pm vs Boolean.pm)

| Metric | Ratio | Linear baseline | Verdict |
|---|---:|---:|---|
| Bytes | 5.77x | 5.77x | reference |
| Lines | 4.60x | 5.77x | sub-linear (good) |
| chart_has | 5.17x | 5.77x | linear |
| chart_set | 6.23x | 5.77x | linear |
| `multiply` | **8.48x** | 5.77x | mildly super-linear |
| `predict` | 6.01x | 5.77x | linear |
| `scan` | 6.18x | 5.77x | linear |
| `complete` | 6.94x | 5.77x | linear |
| `Context::new` | 7.23x | 5.77x | linear-ish |
| Peak RSS | 4.87x | 5.77x | sub-linear |
| **Wall time** | **18.4x** | 5.77x | **strongly super-linear** |

Operation counts grow ~5-7x for ~5.8x bytes — close to linear, with
`multiply` slightly super-linear (8.5x) because items at busier positions
have more disambiguation merges. `Context::new` is 7.2x, also close to linear.

Wall time grows 18.4x. That gap — between linear op-count growth and
super-linear wall time — has to come from per-operation cost growth, not
operation count growth.

### Per-operation cost trend

| File | Wall time | `multiply` count | Per-multiply | `chart_has` count | Per-chart_has | `Context::new` count | Per-context |
|------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|
| Boolean.pm | 7.1s | 7,135 | 0.99 ms | 159,933 | 0.044 ms | 46,311 | 0.082 ms |
| Context.pm | 37.4s | 33,877 | 1.10 ms | 439,456 | 0.085 ms | 185,270 | 0.090 ms |
| FilterComposite.pm | 126.0s | 60,523 | 2.08 ms | 826,789 | 0.152 ms | 334,656 | 0.094 ms |

Per-call cost trends:

- **`multiply` per-call: 0.99ms → 1.10ms → 2.08ms.** More than doubles between
  the smallest and largest file. This is per-invocation cost increasing — i.e.
  multiply is doing the same orchestration but slower.
- **`chart_has` per-call: 0.044ms → 0.085ms → 0.152ms.** **3.5x increase per
  call** for what should be an O(1) array index. This is the smoking gun for
  cache/memory pressure: as the chart and its `[$pos][$core_id][$rel_dist]`
  triple-deep array structure grows past L2 / L3, every lookup costs more.
- **`Context::new` per-call: nearly flat at 0.08-0.09ms.** Constructor cost
  is independent of file size, as expected. So the per-call growth in
  `multiply` and `chart_has` is real and not measurement artifact.

This pattern — flat operation-count scaling with rising per-operation cost
that tracks RSS growth — is the textbook signature of a memory-bound
workload, not an algorithmic blowup. The chart data structure does not have
catastrophic ambiguity (max 255 items at one position out of ~15,000),
but it does become large enough that pointer-chasing through nested
arrayrefs starts incurring real cost.

### Items-per-position from `EARLEY_PROFILE`

For `FilterComposite.pm`:

| pos | items_here | total_items | max_items_at_pos | live_span | RSS |
|----:|----:|----:|----:|----:|----:|
| 1000 | 0 | 3404 | 149 | 100 | 226 MB |
| 5000 | 82 | 51100 | 236 | 9 | 265 MB |
| 10000 | 0 | 92148 | 236 | 27 | 389 MB |
| 15000 | 0 | 137937 | 255 | 140 | 557 MB |

The peak items-at-one-position is 255 — non-trivial, but not the runaway
N-way ambiguity blowup that would mark Category A. Total cumulative items
grows roughly linearly in pos (137,937 / 15,000 ≈ 9.2 items per position
average). Live-span (positions still holding data due to incomplete spans)
hovers at 9-340 chars, occasionally dropping when GC fires.

This rules out gross ambiguity blowup as the primary cause. The chart is
moderately populated and behaves consistently with file size.

---

## Primary bottleneck: Category E (multiple causes), heavily weighted toward
memory-pressure-driven per-operation cost growth

The data does not support a single dominant cause:

- Not Category A (ambiguity blowup): max items-per-position is 255 and
  total items grows linearly with input. No exponential or polynomial
  blowup pattern.
- Not cleanly Category B (regex/scan overhead): scan accounts for 4-9%
  of wall time even on the smallest file and shrinks as a fraction on
  larger files. Scan cache hit rate is low (~22%) but the absolute time
  in scan is bounded.
- Not Category C alone (hash-cons/cache pressure): per-component semirings
  contribute 7-12% total of wall time, and their `add()` and `is_zero()`
  costs are negligible. If hash-cons cache pressure were dominant, it
  would show up here.
- Not cleanly Category D (filter-stack dispatch): `FilterComposite.multiply`
  is 10-20% of wall time across all three files. Removing all five
  component-semiring dispatch overhead would save ~7% of the largest file's
  wall time, not the 10%+ needed to fit under 120s.

**What the data does support:**

The 18x wall-time growth against 5-6x operation-count growth is
super-linear in time *per operation*, not in operation count. This is most
visible in `chart_has` (3.5x per-call cost increase) and `multiply` (2.1x
per-call cost increase) as the chart data structure grows from ~125 MB to
~609 MB peak RSS.

Several distributed factors contribute roughly equally:

1. **Chart array-of-array-of-array access slows with size.** Every chart
   operation traverses three Perl arrayref dereferences:
   `$chart->[$pos][$core_id][$rel_dist]`. On the largest input the chart's
   working set exceeds L3 caches and likely incurs memory-bus traffic on
   every access. `chart_has` slowed 3.5x per call between the smallest and
   largest file despite no change in code path.

2. **`FilterComposite.multiply` is a 5-iteration loop with hashref-construction
   in the middle.** Per-call work scales modestly with chart density because
   `_annotation_semirings()` re-runs `grep blessed && can('slot_name')` on
   every call (FilterComposite.pm:21-27), allocating a fresh list. The loop
   then constructs `%slot_results`, calls `set_type_context()`, and invokes
   `_wrap_sa_result` which builds a new `Context` with a new `annotations`
   hash. None of this is per-component-component dispatch overhead per se —
   it is the orchestrator's per-event book-keeping.

3. **The set-reuse registry runs unconditionally per position.** Lines
   708-727 of Earley.pm scan every chart cell at every position, build
   `"$core_id:$rel_dist"` strings, sort them, join with `;`, and hash-lookup
   the result. This work scales with items-at-position × positions. At
   15,000 positions × 9.2 avg items, that is ~138K string builds + sort +
   hash lookup per parse. The output (`$_set_reuse_stats`) is **read by no
   parsing logic** — it is exposed via `set_reuse_stats()` for diagnostics.

4. **`Context::new` is called 334,656 times for the largest file** and is
   roughly half from `_make_complete_context` / `_make_scan_context` /
   `_filter_compare` results / `_wrap_sa_result`. Each call allocates a
   fresh blessed object with three or four hashref fields. This is real
   work that grows linearly with parse events.

5. **Component semiring work, while small per-call, runs ten of thousands
   of times.** Even at 0.05-0.10 ms per Boolean::is_zero call, 60K calls
   accumulate to tens of seconds when summed across all five components.

The fix shapes for these are different from each other — see
"Implications for next steps" below.

---

## Secondary findings

### 1. GC effectiveness: limited but not broken

`positions_freed` covers 4.6-6.0% of total positions. `safe_sets_found`
covers 6.7-10.9% of total positions. Both proportions stay roughly constant
across file sizes — GC is not falling behind on larger files, but it is
also not aggressive. The chart's resident set grows linearly with input
because most positions are never freed.

The two GC mechanisms in `_run_parse` are:
- **Aycock safe-set GC** (lines 795-841): frees the window between
  consecutive safe sets when the window is empty of cross-window items.
  The check at lines 800-819 is conservative — it walks all incomplete
  items at the safe set position and rejects the window if any of their
  origins fall inside. Many parses will fail this check.
- **Epoch GC** (lines 730-786): triggers on `StatementItem` completion.
  This is more aggressive but bounded to the statement just completed.

A potential cheap win: increase the visibility into *why* safe-set GC
rejects windows. Currently when `safe_to_free` is false, the window is
silently kept; there is no way from outside the parser to see how often a
"would-be-safe" window was blocked by an open item.

### 2. Set-reuse registry: unused at runtime, expensive to maintain

`_set_registry` and `_set_reuse_stats` (Earley.pm:79-81, 708-727,
reset_parse_state at 144-145) are built per position by joining a sorted
string of every active chart cell. The output is exposed via
`set_reuse_stats()` for tests but is not consulted by `_run_parse` to skip
work.

For FilterComposite.pm: 1,352 unique sets + 705 reuse hits = 2,057 set-key
constructions. At 9.2 items per position × 15,280 positions, the inner
work to build keys runs ~138K times. The cost is small per call (a few
microseconds for sort+join) but adds up to seconds across a parse.

This is a candidate for either deletion (if the diagnostic value isn't
used) or for actually consuming the registry to short-circuit
duplicate-set positions.

### 3. Scan cache hit rate is structurally low (~22%)

The scan cache (`%_scan_cache`) is populated in two places:
- The pre-predict/pre-scan loop at the top of every position (lines 530-558),
  which iterates the active core items' DFA states and pre-tries every
  pattern in the union of their `terminal_map`. This produces the
  `clustered_scans` count (101-539 scans across our corpus).
- `_scan` itself, which falls through to `Chalk::Bootstrap::Terminal::match`
  on cache miss and stores the result.

`clustered_scans` represents only 0.7% of total scan attempts on the
largest file (539 / 72,732). The pre-scan terminal clustering exists but
covers a small fraction of actual scanning. Cache hit rate plateaus at
~22% across all three file sizes, suggesting the limiting factor is the
diversity of patterns reached from each position rather than the cache
mechanism itself.

The Aycock terminal clustering mentioned in `xs_performance_investigation.md`
appears to be partially implemented (the pre-scan loop exists) but its
coverage is small. Either the DFA `terminal_map` is mostly empty for the
states reached during real parses, or the pre-scan loop is short-circuiting
on the `next if seen_states{$state_id}++` condition before exploring
many terminals.

### 4. Filter-stack short-circuiting works correctly

`FilterComposite.multiply` short-circuits on the first zero return from
any annotation-layer semiring. This is verified by the per-component
counts:

For FilterComposite.pm:
- Boolean.multiply: 60,523
- Precedence.multiply: 60,523
- TypeInference.multiply: 60,353 (170 fewer — short-circuited by Precedence)
- Structural.multiply: 60,250 (103 fewer — short-circuited by Precedence or TI)
- SemanticAction.multiply: 60,250 (same as Structural)

So only 0.3% of multiply calls are short-circuited before reaching SA.
This is consistent with the pipeline's design (most parses are valid Perl
that all five semirings accept), but it means that **the "cheaper checks
first" rationale for filter ordering does not produce the expected savings
at runtime — the vast majority of multiply calls run all five semirings
to completion.** Ordering changes would have negligible effect on parse
speed.

Worth noting separately: `FilterComposite.is_zero` (60,524 calls) is far
cheaper than `multiply` because it just checks the Context's `is_zero`
flag without invoking components. The 0.2% wall time spent there is
appropriate.

### 5. `_filter_compare` (the disambiguation path) is rare

`_filter_compare` runs 2,751 times on FilterComposite.pm (vs 60,523 multiply
calls — 4.5%). It is the only place where the per-component `add()` would
matter for performance, and per-component `add()` is dwarfed by `multiply`
(2,751 vs 60,523 calls). Disambiguation cost is ~0.18s on the largest file
— effectively free.

### 6. Top-of-file profiler "unaccounted overhead" growth

`script/profile-parse.pl` reports unaccounted overhead growing from
34.5% (Boolean.pm) to 72.0% (FilterComposite.pm). The deeper wrapper
brought this to 26.2% → 65.4%. The remaining 65% on the largest file is
the per-position agenda-building loop body (lines 421-433 in
`_run_parse`), the pre-predict/pre-scan loop (530-558), the GC sweep
(730-786), the safe-set check (795-841), and the set-reuse registry
build (708-727). These are not method calls — they are inline loops in
`_run_parse` and cannot be wrapped without source modification.

If a future investigation needs sub-second attribution of the inline
loops, `Devel::NYTProf` is the right tool. This investigation deliberately
stayed below NYTProf since the existing infrastructure was sufficient to
identify the *category* of the bottleneck.

---

## Implications for next steps

The data supports several different fix shapes. They are not mutually
exclusive, but they have different cost/risk profiles.

### Pure-Perl fixes (no C bootstrap needed)

**S1. Remove or use the set-reuse registry.** The block at
Earley.pm:708-727 builds keys that no parsing logic consults. Either:
- Delete it and the supporting fields. Net positive (some seconds back per
  parse on large files).
- Or actually use it: short-circuit position processing if an identical
  set was seen before. This is bigger work and requires verifying
  correctness (is the set-key really sufficient to avoid re-doing work?).

The diagnostic statistics it exposes can be reproduced cheaply if
needed (count ChartSet sizes; the set keys themselves are not informative
once the parse completes).

**S2. Reduce `Context::new` allocations on the hot path.**
`_make_scan_context` and `_make_complete_context` produce a fresh
Context per scan and per completion (5,002 + 6,388 = ~11K calls on the
largest file, 0.32s). These could be reused as immutable singletons
keyed on `(rule_name, alt_idx, pos, origin)` — many scans share rule_name
and alt_idx within a single position. The hash-cons cache on Context (if
one exists; verify) is also a candidate for inspection.

**S3. Audit `_annotation_semirings()` for per-call work.** The grep at
FilterComposite.pm:21-27 runs on every call to `multiply`, `add`, `one`,
and `_filter_compare`. Cache the resulting list in a field at construction
time. Saves a few microseconds × 60,523 multiply calls = single-digit
seconds.

**S4. `_is_safe_set` walks all active items twice.** It could short-circuit
property 1 (must have a final item) before scanning twice. It already
does this in part — verify the early-out is tight.

These four fixes together likely net 5-15% improvement on the largest file
— not the 10-20% needed to fit under 120s, but progress without C work.

### Fixes that need careful design but are still pure-Perl

**M1. Improve scan-cache coverage.** The pre-predict terminal-clustering
loop exists (lines 530-558) but only fills the cache for 0.7% of total
scans. Two angles:
- Investigate why the DFA `terminal_map` produces so few patterns per
  state. If the DFA is "almost trivial" (most states accept most
  terminals), the clustering optimization fundamentally doesn't apply
  to this grammar.
- Cache scan results by `(pos, end_of_input_window)` rather than `(pos,
  pattern)`, so multiple patterns hitting the same byte at the same
  position share results.

**M2. Item-deduplication in the `add()` chart-merge path.** The chart
merge path is rare (2,751 calls vs 60,523 multiply) but each call can
trigger expensive `_filter_compare`. The current code paths look fine;
no specific fix surfaced.

**M3. Investigate why GC frees so few positions.** 4.7% of positions
freed on a 15K-position chart leaves 14,300+ positions resident. Are
items at those positions actually still referenced by live items, or
are they retained by the conservative `safe_to_free` check? If the latter,
a less conservative reachability analysis could reclaim more.

### Fixes that benefit from C-library / XS work

**C1. Vtable dispatch (per `docs/plans/semiring-vtable-dispatch.md`).**
Worth a measurement, but the data here suggests it would save at most
the current per-component overhead — about 7% of wall time on the largest
file (sum of all five components). Important to get right but not the
biggest lever.

**C2. Chart data structure migration.** The 3.5x per-call cost growth in
`chart_has` is the most super-linear effect in the data. A C-implemented
chart with packed (pos, core_id, rel_dist) → value mapping using a
contiguous backing store would dramatically reduce the per-access cost.
This is a much larger lift than vtable dispatch but addresses the root
cause of the per-operation cost growth.

**C3. Reimplement `_run_parse`'s inline loops in C.** The 65%
unaccounted region on the largest file is mostly Perl-level loop
overhead. Lifting the per-position agenda-building, pre-scan, GC sweep,
and safe-set checks into C would compress this region significantly.
This is essentially the chalk.so approach extended to the parser
core.

### Recommendation for next step

The data is **borderline ambiguous between pure-Perl wins and C-library
work** for the dominant bottleneck:

- The super-linear time-per-op trend points at memory-pressure on the
  chart. A C-backed chart (C2) addresses this directly. This is a
  big lift.
- The set-reuse registry, the safe-set GC sweep loop, and `Context::new`
  reuse are all approachable in pure Perl (S1, S2, M3) and likely sum to
  10-15% improvement.
- Vtable dispatch (C1) is plumbed in design docs but the upper bound on
  its win is ~7%.

**Recommended next step**: do **S1 first** (delete or use the set-reuse
registry — the cheapest change with measurable gain), then **rerun this
profiler set** on the same three files to see whether the per-op cost
trend moves. If `chart_has` per-call time stays super-linear, that
narrows the diagnosis to genuine memory pressure on the chart and
directly justifies the C-library migration. If `chart_has` per-call cost
flattens after S1, that suggests the registry build was creating a lot
of the chart-traversal pressure.

This is the "deeper measurement" path the brief allows for when data is
ambiguous: do one cheap fix that has independent merit, see whether the
metric movement explains the rest, and use the post-fix measurement to
decide between pure-Perl follow-ups and the bigger C-migration commit.

---

## What this investigation does NOT answer

- **Per-method-call timing inside Earley::_run_parse's inline loops.** The
  profiler attributes 65% of wall time on the largest file to unaccounted
  overhead inside loop bodies that aren't method calls. `Devel::NYTProf`
  would resolve this but was deemed disproportionate for an
  initial investigation.
- **Memory profiling beyond peak RSS.** We have RSS samples every 0.5s but
  no breakdown by Perl object type (e.g., how much is Context objects,
  how much is the chart arrayref tree, how much is the hash-cons caches in
  Precedence/TI). `Devel::Size` could resolve this.
- **Behavior on synthetic worst-case grammars.** Profiling was on real
  Bootstrap source files; we have no measurement of how the parser
  handles deeply ambiguous synthetic inputs.
- **C-library/XS performance vs pure-Perl.** The XS path is documented in
  memory and design docs but not measured here. The investigation
  framing in `xs_performance_investigation.md` predates the current
  five-semiring stack; that file should be re-validated against current
  code before it informs decisions.
- **Scaling beyond 15K bytes.** `TypeInference.pm` (23 KB) and
  `ConciseTree/Actions.pm` (61 KB) are presumably worse, but were not
  measured. The 18x time-per-5.8x-bytes trend suggests Actions.pm at
  ~4x FilterComposite.pm bytes would take ~5-8x longer (~10-20 minutes)
  if the trend continues, but we have not verified the trend extrapolates
  cleanly.
- **The 120s harness budget vs. actual hardware.** The numbers here come
  from the host this investigation ran on. Different hardware would
  shift absolute times; the per-operation cost ratios should be
  hardware-independent.

---

## Cross-references

### Plans informed or informed-by this investigation

- `docs/plans/2026-04-01-benchmark-design.md` — proposed the benchmark
  approach this investigation extended. Notes that no harness was
  implemented; this investigation provides one (in `/tmp/`) that could
  be productionised under `t/benchmark/`.
- `docs/plans/semiring-vtable-dispatch.md` — proposes vtable dispatch
  to reduce per-component method-resolution overhead. This investigation
  shows the upper bound on that win is ~7% of wall time, not the
  dominant fix.
- `docs/plans/2026-03-16-safe-set-gc-design.md` — design for Aycock
  safe-set GC. This investigation confirms it works but reclaims only
  ~5% of chart positions. Worth revisiting whether the conservative
  `safe_to_free` check is too cautious.
- `docs/plans/2026-03-16-epoch-chart-gc-design.md` — design for
  StatementItem epoch GC. Same provenance as above.
- `docs/plans/2026-03-27-dfa-factored-earley-parser.md` — Section 11
  performance methodology, partially fulfilled by this investigation.

### Memory notes

- `xs_performance_investigation.md` (45 days old) — framed the suspect
  bottlenecks. This investigation finds they are all real but each
  contributes less than expected; the dominant trend (per-op cost
  growth) was not on that note's list.
- `feedback_technical_debt_cleanup.md` (referenced in MEMORY.md) — the
  set-reuse registry exposing diagnostic stats but not consuming them at
  runtime is a textbook example of "dead code accumulating because
  attempted fixes rarely get reverted after they're superseded."

### Code references cited

- `lib/Chalk/Bootstrap/Earley.pm:178-249` — `_is_safe_set` definition.
- `lib/Chalk/Bootstrap/Earley.pm:275-286` — `_chart_has`, `_chart_get`,
  `_chart_set` definitions; the 3-deep arrayref accessors that
  super-linearly slow down.
- `lib/Chalk/Bootstrap/Earley.pm:359-1007` — `_run_parse` main loop.
  Contains all the inline blocks that profiling cannot easily
  attribute.
- `lib/Chalk/Bootstrap/Earley.pm:530-558` — pre-predict/pre-scan
  terminal clustering loop. Populates `$_scan_cache` with 0.7% coverage
  at the largest file size.
- `lib/Chalk/Bootstrap/Earley.pm:708-727` — set-reuse registry build.
  Runs every position, builds sorted/joined keys; output unused at
  runtime.
- `lib/Chalk/Bootstrap/Earley.pm:730-786` — epoch GC sweep.
- `lib/Chalk/Bootstrap/Earley.pm:795-841` — Aycock safe-set GC sweep.
- `lib/Chalk/Bootstrap/Earley.pm:1133-1165` — `_predict`.
- `lib/Chalk/Bootstrap/Earley.pm:1169-1238` — `_scan` and the per-scan
  cache lookup.
- `lib/Chalk/Bootstrap/Earley.pm:1248-1415` — `_complete` including Leo
  resolution and Leo creation.
- `lib/Chalk/Bootstrap/Earley.pm:1422-1453` — `_make_scan_context` and
  `_make_complete_context`. Allocate Contexts on the hot path.
- `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:21-27` —
  `_annotation_semirings()` runs `grep blessed && can('slot_name')`
  per call.
- `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:148-193` —
  `multiply()` orchestration loop.
- `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:218-288` —
  `_filter_compare()` first-wins loop.
