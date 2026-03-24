# Earley Core/Distance Factoring and Set Reuse

**Date**: 2026-03-24
**Status**: Design
**Problem**: Parse times are super-linear. Building chalk.so takes ~38 minutes,
dominated by pure-Perl Earley parsing (Phase 2 alone: 2307s). The compiled C
target gives no speedup because the bottleneck is chart width, per-item hashref
overhead, and FilterComposite tuple cloning — not opcode dispatch.

## Root Cause Analysis

Profiling reveals:

| File | Lines | parse_value time | lines/s |
|------|-------|-----------------|---------|
| Boolean.pm | 68 | 5.6s | 12.2 |
| FilterComposite.pm | 257 | 74.8s | 3.4 |
| Structural.pm | 374 | 74.7s | 5.0 |
| Earley.pm | 1097 | 1613s | 0.7 |

Lines/s drops as files grow — super-linear scaling. The generated C code
operates at the Perl SV API level (allocating SVs for every hash key lookup),
so compilation provides negligible improvement.

The YAEP parser (Makarov) parses 635K lines of C in 1.43s / 142MB vs Marpa's
22.23s / 30GB. YAEP's key optimizations: core/distance factoring, set reuse
via hashing, relative distances, and optionally transitive transitions.

## Design

### 1. Eliminate Item Hashrefs

**Current**: An Earley item is a 6-field hashref `{rule, alt_idx, core_id,
dot, origin, value}`. Three fields (rule, alt_idx, dot) are redundant with
core_id (derivable from CoreItemIndex). The chart stores
`$chart[$pos][$core_id]{$origin} = [$item_hashref, $alt_idx]`.

**New**: The chart stores values directly. Initially (step 3) using a hash
for the origin dimension: `$chart[$pos][$core_id]{$origin} = $value`. After
relative distances are introduced (step 6), the origin dimension converts to
a sparse array: `$chart[$pos][$core_id][$rel_dist] = $value`. Relative
distances are small integers (profiling shows 67.7% are 0-1, 82% are 0-7)
suitable for sparse array indexing. No item hashref. No wrapper array.

The agenda carries `[$core_id, $origin]` pairs; values are looked up from the
chart when needed.

Items are never allocated, cloned, or passed around. `_make_item` and
`_advance_item` disappear. CoreItemIndex provides `rule_name_for($core_id)`,
`alt_idx_for($core_id)`, `dot_for($core_id)` as O(1) array lookups.

### 2. Semiring API Change

Every semiring method that currently receives `$item` changes to receive
explicit parameters. The item fields accessed across all semirings:

| Field | Used by |
|-------|---------|
| `value` | All semirings |
| `rule->name()` | Precedence, TypeInference, Structural, SemanticAction |
| `origin` | SemanticAction (epoch commit only) |

New signatures:

```perl
method on_scan($value, $rule_name, $alt_idx, $pos, $matched_text)
method on_complete($value, $rule_name, $alt_idx, $pos, $origin, $on_epoch_commit)
method should_scan($value, $rule_name, $alt_idx, $pos, $matched_text, $is_predicted)
method on_skip_optional($value, $rule_name, $alt_idx, $pos, $symbol_name)
```

FilterComposite changes from cloning the item hashref per component:
```perl
my $component_item = { %$item, value => $item->{value}->[$i] };
$sr->on_scan($component_item, $alt_idx, $pos, $matched_text);
```
To passing the value slice directly:
```perl
$sr->on_scan($value->[$i], $rule_name, $alt_idx, $pos, $matched_text);
```

This eliminates 5 hash clones per semiring operation (on_scan, on_complete,
should_scan, on_skip_optional each clone 5 times in FilterComposite = 20
clones per chart entry per operation).

### 3. Leo Item Adaptation

Leo items currently store a rich hashref:
```perl
{ origin => ..., value => ..., rule => ...,
  wait_core_id => ..., wait_origin => ... }
```

In the new representation, Leo items become a separate side-table (not in the
chart) storing:
```perl
$leo_items{$rule_name}{$origin} = {
    core_id      => $top_core_id,
    origin       => $top_origin,
    value        => $chain_value,
    wait_core_id => $waiting_core_id,
    wait_origin  => $waiting_origin,
}
```

The Leo optimization is critical for right-recursive rules (ExpressionList,
StatementSequence). The core_id replaces the rule+dot+alt_idx fields. The
origin and wait_origin remain absolute positions (Leo chains span arbitrary
distances, so relative distances don't help here). When a Leo completion
fires, it looks up `rule_name_for(core_id)` from CoreItemIndex instead of
accessing `$item->{rule}->name()`.

### 4. Position-Independent Hash-Consing

SemanticAction's `_scan_ctx` currently keys on `"scan:$pos:t:$text"`,
making contexts position-dependent. TypeInference's `_extend_ctx_with_focus`
includes `$position` in its cache key.

Position is bookkeeping, not semantics — the IR does not carry source
positions. The hash-consing keys change to:

- `_scan_ctx`: `"scan:t:$text"` (drop `$pos`)
- `_extend_ctx_with_focus`: `"ext:$rule_name:$focus_key:$children_key"` (drop `$position`)

**Correctness argument**: Two scans of the same text at different positions
produce identical leaf contexts. When combined via `_mul_ctx` with different
surrounding contexts (different refaddrs), the multiply produces different
trees regardless. The tree structure preserves source ordering; individual
leaf identity does not need to.

### 5. Core Set Representation

A **core set** is the set of core_id integers active at a chart position,
independent of origins or values. Represented as a sorted integer array with
a precomputed hash for O(1) dedup lookup.

```
CoreSet:
  id         — unique integer (assigned on first encounter)
  core_ids   — sorted arrayref of active core_id integers
  hash       — content hash for dedup lookup in registry
```

Core sets are discovered lazily during parsing and registered in a hash table.
Many chart positions will share the same core set (same active rules, different
origins/values). This is analogous to YAEP's set_core.

### 6. Relative Distances

Origins change from absolute input positions to relative distances from the
current position. An item with origin=990 at position=1000 becomes
distance=10.

Benefit: two chart positions with the same core set and the same relative
distances are structurally identical, even at different absolute positions.
This enables set reuse for repetitive source patterns (statement after
statement, expression after expression).

Set identity is `(core_set_id, distance_vector_hash)`. A distance vector is
the sorted list of `(core_id, relative_distance)` pairs. This is hashed and
used as the key in the set registry.

### 7. DFA States and Terminal Clustering

CoreSets serve as DFA states. Each core set gets precomputed:

**Terminal map**: which terminal patterns are expected by items in this core
set. At each position, try each terminal once (not once per item). The scan
cache already does per-(position, pattern) memoization; this extends it to
per-(core_set, pattern).

**Goto table**: for each (core_set, symbol) pair, which core_set results
from advancing all items past that symbol. Precomputed on first encounter,
reused for subsequent positions with the same core set.

**Completion map**: for each (core_set, nonterminal) pair, which items in
this core set are waiting for that nonterminal's completion. Replaces the
per-item scan of the agenda during completion.

Note: the completion map tells you which items in a core set *wait* for a
nonterminal. But the waiting items are at the *origin* position, not the
current position. Same-position completions (where the completed item and
waiting item are both at the current position) are fully precomputable from
the core set. Cross-position completions require looking up the origin
position's core set to find waiting items — the completion map at the origin
pre-indexes which core_ids wait for the given nonterminal, avoiding a full
agenda scan.

These are properties of the core set (grammar-structural), not of specific
positions or values. Computed once per core set, shared across all positions
that use that core set.

### 8. Set Reuse

When a new chart position has a known `(core_set_id, distance_vector_hash)`,
its structural parsing decisions are reusable:

- **Predictions**: determined by core set alone. Cache per `core_set_id`.
- **Scan decisions**: determined by core set's terminal map. Try each pattern
  once per core set, not once per item.
- **Same-set completions**: determined by core set alone (which items complete
  and which items wait, independent of distances). Precomputable.
- **Cross-set completions**: depend on the origin position's core set and
  values. These still require per-position work but benefit from the goto
  and completion maps.

For repetitive source code (common in real Perl files — sequences of
statements, method definitions, field declarations), the same core
set + distance vector recurs frequently, making reuse effective.

### 9. GC Considerations

**Grammar-lifetime structures** (persist across file parses, cleared only when
grammar changes):
- Core set registry
- DFA state tables (goto, terminal map, completion map)

**Parse-lifetime structures** (cleared by `reset_cache()` between files):
- Chart and distance vectors
- Set registry entries
- Hash-consing caches (SemanticAction `$_ctx_cache`, TypeInference `$_ctx_cache`)

The existing `reset_cache()` method on each semiring handles inter-file
cleanup. A new `reset_parse_state()` on Earley clears the chart, set
registry, and distance vectors while preserving core set and DFA tables.

Intra-file, the epoch GC callback can evict set registry entries for swept
positions. Core set and DFA tables grow monotonically but are bounded by the
grammar — the number of distinct core sets is finite (and typically small
relative to input size).

## Tech Debt

**Target/XS.pm hardcoded FilterComposite dispatch**: Target/XS.pm has
hand-written emitters for each semiring method name (`_emit_composite_on_scan`,
`_emit_composite_on_complete`, etc.) that unroll the FilterComposite component
loop into direct C calls. This bypasses the IR — Target/C.pm does not need
equivalent special-casing because it emits whatever the IR contains. The
XS.pm dispatch was a performance optimization compensating for the item
cloning overhead. After this refactor eliminates cloning, the hand-unrolled
dispatch may no longer be necessary. Flag for cleanup: make XS.pm work from
IR like C.pm does.

## Files Changed

| File | Change |
|------|--------|
| `lib/Chalk/Bootstrap/Earley.pm` | Rewrite `_run_parse`, eliminate `_make_item`/`_advance_item`, new chart representation, Leo item adaptation |
| `lib/Chalk/Bootstrap/CoreItemIndex.pm` | Add `rule_name_for`, `alt_idx_for`, `dot_for`, `rule_for` accessors |
| `lib/Chalk/Bootstrap/LR0DFA.pm` | Extend with DFA states, goto table, terminal map, completion map |
| `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` | New API signatures, eliminate item cloning |
| `lib/Chalk/Bootstrap/Semiring/Boolean.pm` | New API signatures |
| `lib/Chalk/Bootstrap/Semiring/Precedence.pm` | New API signatures |
| `lib/Chalk/Bootstrap/Semiring/TypeInference.pm` | New API signatures, position-independent hash-consing |
| `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` | New API signatures, position-independent hash-consing |
| `lib/Chalk/Bootstrap/Semiring/Structural.pm` | New API signatures |
| `t/bootstrap/*.t` | Update tests for new API |

## Expected Impact

- **Per-position cost**: drops dramatically — no hashref allocation, no
  FilterComposite cloning, array indexing instead of hash lookup for origins.
- **Set reuse**: positions with identical core sets share prediction/scan/
  completion maps. For repetitive code, large portions of the chart are
  structurally reused.
- **Memory**: items go from 6-field hashrefs to values stored directly in
  chart arrays. Core sets and DFA tables add fixed overhead bounded by grammar
  size.
- **C codegen benefit**: the new chart representation translates to efficient
  C (integer arrays, direct indexing) vs the current hashref-heavy code that
  generates SV allocation at every step.
- **Correctness**: the new representation matches the theoretical Earley item
  model (core_id + origin pair with attached value), eliminating redundant
  fields and the design defect of passing rich item objects through the
  semiring interface.

## Sequencing

### Task 1: CoreItemIndex Accessors

**Requirement:** Design §1 — CoreItemIndex provides `rule_name_for`, `alt_idx_for`,
`dot_for`, `rule_for` as O(1) array lookups.

#### RED
- Write tests that call `rule_name_for($core_id)`, `alt_idx_for($core_id)`,
  `dot_for($core_id)`, `rule_for($core_id)` for known core items.
- Assert they return the correct rule name string, alt index integer, dot
  position integer, and Rule object respectively.
- Expected failure: methods don't exist yet.
- If they pass unexpectedly: CoreItemIndex already has these (check).

#### GREEN
- Add four arrays to CoreItemIndex populated during `build()`: `@id_to_rule_name`,
  `@id_to_alt_idx`, `@id_to_dot`, `@id_to_rule`. Each indexed by core_id.
- Four accessor methods that return `$array[$id]`.

#### REFACTOR
- Check whether existing `item_for($id)` can be simplified or removed since
  its callers may now prefer the specific accessors.
- Verify the id_for/advance methods still work — advance returns the next
  core_id, which should be consistent with the new arrays.

---

### Task 2: Semiring API Change

**Requirement:** Design §2 — all semiring methods receive explicit `$value`,
`$rule_name`, `$origin` parameters instead of `$item` hashref.

#### RED
- For each semiring (Boolean, Precedence, TypeInference, Structural,
  SemanticAction, FilterComposite), write a test calling `on_scan`,
  `on_complete`, `should_scan`, `on_skip_optional` with the new signatures:
  `($value, $rule_name, $alt_idx, $pos, ...)`.
- Assert results match the current behavior for known inputs.
- Expected failure: methods still expect `$item` hashref as first parameter.
- If they pass unexpectedly: signatures were already changed (unlikely).

#### GREEN
- Change method signatures in all 6 semirings.
- In each method body, replace `$item->{value}` with `$value`,
  `$item->{rule}->name()` with `$rule_name`, `$item->{origin}` with `$origin`.
- In FilterComposite, replace `{ %$item, value => $item->{value}->[$i] }`
  with `$value->[$i]` passed directly to component semirings.
- Update Earley.pm call sites to pass explicit parameters (using
  `$core_index->rule_name_for($core_id)` from Task 1).

#### REFACTOR
- Remove any dead code paths that constructed fake item hashrefs for testing.
- Check whether FilterComposite's on_complete TI→SA threading (index 2→4)
  still works with the new signatures — it should, since it only passes
  the TI result, not the item.
- Look for any remaining `$item->{...}` patterns in semiring code.

---

### Task 3: Chart Representation + Leo Adaptation

**Requirement:** Design §1, §3 — chart stores values directly keyed by
`$chart[$pos][$core_id]{$origin} = $value` (hash for origin dimension at
this stage; converts to array in Task 6). Leo items move to a side-table
with core_id instead of rule/dot/alt_idx.

#### RED
- Write a parsing test that parses a known input (e.g., Boolean.pm) and
  checks that parse_value returns the same IR as the current implementation.
  Use an existing integration test as baseline.
- Write a test for Leo optimization: parse a deeply right-recursive input
  (long ExpressionList or StatementSequence) and verify it completes without
  stack overflow or O(n²) blowup.
- Expected failure: Earley.pm still uses item hashrefs.
- If they pass unexpectedly: the refactor was already done (check git).

#### GREEN
- Rewrite `_run_parse` to use `$chart[$pos][$core_id]{$origin} = $value`.
- Remove `_make_item` and `_advance_item`.
- The agenda carries `[$core_id, $origin]` pairs.
- Values are looked up from chart; `rule_name`, `alt_idx`, `dot` are looked
  up from CoreItemIndex.
- Rewrite Leo item storage: `$leo_items{$rule_name}{$origin}` stores
  `{core_id, origin, value, wait_core_id, wait_origin}`.
- Rewrite completion paths (normal, Leo, advance-from-completed) to work
  with the new representation.

#### REFACTOR
- Remove any remaining hashref construction patterns.
- Check that epoch GC still works (it accesses `$entry->[0]->{value}` which
  is now just `$value` directly in the chart).
- Verify diagnostic code (_emit_parse_diagnostic) works with new chart shape.
- Profile Boolean.pm parse_value before and after to measure the hashref
  elimination win.

---

### Task 4: Position-Independent Hash-Consing

**Requirement:** Design §4 — drop `$pos` from SemanticAction and
TypeInference hash-consing keys.

#### RED
- Write a test that parses input containing the same token at two different
  positions (e.g., `$x + $x`) and verifies the parse produces correct IR
  with both occurrences distinct in the output.
- Write a test that the scan Context cache returns the same object for
  identical text regardless of position: `_scan_ctx("foo", 10)` and
  `_scan_ctx("foo", 50)` return the same refaddr.
- Expected failure: `_scan_ctx` includes position in key, so same text at
  different positions returns different objects.
- If the first test (correct IR) fails: the position was load-bearing and
  our correctness argument was wrong — stop and investigate.

#### GREEN
- In SemanticAction, change `_scan_ctx` key from `"scan:$pos:t:$text"` to
  `"scan:t:$text"`.
- In TypeInference, change `_extend_ctx_with_focus` key from
  `"ext:$rule_name:$position:$focus_key:$children_key"` to
  `"ext:$rule_name:$focus_key:$children_key"`.
- Remove `$pos` parameter from `_scan_ctx` signature.

#### REFACTOR
- Check whether the Context class's `$position` field is still used anywhere.
  If not, consider removing it (but check if Actions.pm or other consumers
  read it for error messages).
- Measure cache hit rate before and after — the position-independent keys
  should produce significantly more hits.

---

### Task 5: Core Set Discovery, DFA State Tables, and GC Lifetime

**Requirement:** Design §5, §7, §9 — lazily discover core sets, build goto/
terminal/completion maps per core set. Grammar-lifetime structures persist
across file parses; parse-lifetime structures cleared by reset.

#### RED
- Write a test that parses two small files sequentially (with reset_cache
  between them) and verifies both produce correct IR.
- Write a test that the core set registry is populated after parsing: the
  number of distinct core sets is > 0 and < total chart positions.
- Write a test that DFA state tables exist for each core set: terminal_map,
  goto_table, completion_map are non-empty for at least some core sets.
- Write a test that after reset_parse_state(), the chart is empty but core
  set and DFA tables survive.
- Expected failure: core sets, DFA tables, and reset_parse_state don't exist.

#### GREEN
- Add CoreSet class or data structure to Earley.pm (id, core_ids, hash).
- At each chart position, after processing the agenda, compute the core set
  (sorted list of active core_ids), hash it, look up or register in registry.
- On first encounter of a core set, build its DFA tables:
  - Terminal map: for each core_id, if dot is before a terminal, record
    (terminal_pattern → [core_ids waiting for it]).
  - Goto table: for each (core_set, symbol), compute the set of core_ids
    that result from advancing past that symbol.
  - Completion map: for each (core_set, nonterminal), record which core_ids
    have that nonterminal after the dot.
- Add `reset_parse_state()` method that clears chart, set registry, scan
  cache, but preserves core set registry and DFA tables.
- Update reset_cache() to call reset_parse_state().

#### REFACTOR
- Check whether LR0DFA's existing prediction_items_for can be expressed in
  terms of core set goto tables, or if it should remain separate.
- Profile core set discovery overhead — hashing sorted integer arrays should
  be cheap but verify.
- Look for opportunities to share terminal map data between core sets that
  differ by only a few core_ids.

---

### Task 6: Relative Distances and Set Registry

**Requirement:** Design §6, §1 (array indexing) — convert origins to relative
distances, chart origin dimension becomes array, register sets for reuse.
Note: Leo items remain with absolute origins (Design §3).

#### RED
- Write a test that parses input and verifies distance vectors at chart
  positions contain relative (small) integers, not absolute positions.
- Write a test that two structurally identical parse positions (e.g., the
  start of two consecutive `my $x = ...;` statements) produce the same
  `(core_set_id, distance_vector_hash)`.
- Write a test that the chart origin dimension is now an array (not a hash):
  `ref($chart[$pos][$core_id]) eq 'ARRAY'`.
- Expected failure: chart still uses absolute origins in hashes.

#### GREEN
- Change chart representation from `$chart[$pos][$core_id]{$origin}` to
  `$chart[$pos][$core_id][$rel_dist]` where `$rel_dist = $pos - $origin`.
- Update all chart reads/writes in _run_parse to compute relative distance.
- Build distance vector per position: sorted `(core_id, rel_dist)` pairs.
- Hash distance vectors and register `(core_set_id, dist_hash)` in set
  registry.
- Leo items: keep absolute origins, no conversion.

#### REFACTOR
- Verify that the sparse arrays aren't wasting excessive memory — check the
  max relative distance seen during a real parse.
- Check whether `completed_at` index needs to change (it uses absolute
  positions for origin and completion position).
- Remove any remaining absolute-origin patterns in the chart path.

---

### Task 7: Terminal Clustering

**Requirement:** Design §7 — use core set's terminal map to try each
terminal pattern once per position instead of once per item.

#### RED
- Write a test that counts regex match attempts during a parse. With
  terminal clustering, the count should be proportional to
  (positions × distinct terminals per core set), not (positions × items).
- Compare match count before and after for a known input.
- Expected failure: scanning still iterates per-item.

#### GREEN
- In the scan phase of _run_parse, replace per-item terminal iteration with:
  look up current core set's terminal map, try each terminal pattern once,
  then for each matching terminal, iterate only the items waiting for it.
- Integrate with existing scan cache (which already memoizes per position +
  pattern) — the terminal map determines which patterns to try.

#### REFACTOR
- Check whether the scan cache is still needed — terminal clustering may
  subsume its function if each pattern is tried at most once per position.
- Profile scan phase time before and after.

---

### Task 8: Set Reuse

**Requirement:** Design §8 — cache and reuse predictions, scan decisions,
and same-set completions for known (core_set, distance_vector) pairs.

#### RED
- Write a test that parses input with repeated structure (e.g., 10 identical
  `my $x = 1;` statements). Instrument prediction to count how many times
  predictions are computed vs reused. Assert reuse count > 0.
- Write a test that parsing time scales sub-linearly with repetition count
  (e.g., 20 statements should take less than 2x the time of 10).
- Expected failure: every position computes predictions from scratch.

#### GREEN
- On core set discovery (from Task 5), cache prediction results per
  `core_set_id`.
- On set registry hit (same core_set + distances), reuse cached predictions
  instead of recomputing.
- Cache same-set completion results per core_set_id.
- For scan decisions, cache which terminals matched per (core_set_id, pos
  relative pattern) — or reuse terminal clustering results.

#### REFACTOR
- Measure cache hit rates on real files (Boolean.pm, Earley.pm).
- Check whether cross-set completions can benefit from any caching (they
  depend on origin position state, but the completion map lookup is already
  an improvement over agenda scanning).
- Profile end-to-end parse_value times and compare to baseline.

---

### Task 9: Rebuild chalk.so and Benchmark

**Requirement:** Validate the full refactor.

#### RED
- Run the existing chalk.so build pipeline (`script/build-chalk-so-generated`).
- Assert all 11 classes parse successfully and compile to C.
- Assert the built chalk.so passes all existing integration tests.
- Record Phase 2 parse times per file and compare to baseline (38 minutes).

#### GREEN
- Fix any issues found — parse failures, compilation errors, test regressions.

#### REFACTOR
- If performance targets are met, update the profiling scripts to work with
  the new chart representation.
- Update MEMORY.md with the new architecture description.
- Close or update related GitHub issues (#587 Leo, #633 safe-set, etc.).
