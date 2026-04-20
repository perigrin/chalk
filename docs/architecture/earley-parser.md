<!-- ABOUTME: Detailed architecture of Chalk's scanless Earley parser with Aycock optimizations. -->
<!-- ABOUTME: Covers chart structure, DFA prediction, Leo optimization, nullable handling, GC, and error recovery. -->

# Chalk Earley Parser: Architecture Reference

**Version**: current as of the `worktree-pu` branch  
**Primary source**: `lib/Chalk/Bootstrap/Earley.pm`, `lib/Chalk/Bootstrap/LR0DFA.pm`, `lib/Chalk/Bootstrap/CoreItemIndex.pm`, `lib/Chalk/Bootstrap/Desugar.pm`

---

## Table of Contents

1. [Overview](#overview)
2. [Source Materials and References](#source-materials-and-references)
3. [Grammar Representation](#grammar-representation)
4. [Core Item Index](#core-item-index)
5. [LR(0) DFA Precomputation](#lr0-dfa-precomputation)
6. [Chart Structure](#chart-structure)
7. [Parse Loop: Predict, Scan, Complete](#parse-loop-predict-scan-complete)
8. [Semiring Integration](#semiring-integration)
9. [Leo Optimization](#leo-optimization)
10. [Nullable Handling: Aycock-Horspool](#nullable-handling-aycock-horspool)
11. [Safe-Set Garbage Collection](#safe-set-garbage-collection)
12. [Epoch Garbage Collection](#epoch-garbage-collection)
13. [Scan Caching and Terminal Clustering](#scan-caching-and-terminal-clustering)
14. [Error Recovery](#error-recovery)
15. [Performance Analysis](#performance-analysis)

---

## Overview

The Chalk Earley parser (`Chalk::Bootstrap::Earley`) is a scanless, general context-free parser at the center of Chalk's compilation pipeline. It accepts arbitrary BNF grammars and parses input strings by maintaining an Earley chart: a data structure that records which grammar rules have been recognized up to each position in the input.

The parser is "scanless" in the Marpa sense (Kegler 2012): it does not require a separate lexer phase. Terminals are regex patterns matched directly against the input using `\G`-anchored matching, and the parse operates character-by-character, advancing through input positions as patterns match.

Its role in the pipeline is:

- **Compiler front-end**: Parse Perl source files into an Intermediate Representation (IR) for downstream lowering and code generation.
- **Grammar bootstrapping**: Parse the Chalk BNF meta-grammar to produce the recognizer for Chalk's own grammar description language.
- **Semiring-parameterized evaluation**: The parser does not hard-wire tree construction or type inference. Instead, it is parameterized by a *semiring* object that determines what value is built at each recognition step. The same parser drives boolean recognition (does the string match?), IR construction (what does it mean?), type inference, and precedence disambiguation, depending on which semiring is supplied.

The implementation incorporates four major optimizations from Aycock's 2001 dissertation:

1. **Core item index** — integer IDs for `(rule, alternative, dot)` triples replace string-keyed hash lookups.
2. **LR(0) DFA prediction clustering** — the epsilon-closure of a nonterminal is precomputed once; prediction at parse time becomes an O(1) table lookup.
3. **Leo optimization** — right-recursive chains of deterministic completions are compressed to O(1) per chain instead of O(n).
4. **Safe-set and epoch garbage collection** — chart positions are freed as parsing advances, bounding memory usage on long inputs.

---

## Source Materials and References

The implementation draws on the following primary sources:

**Earley, Jay. "An Efficient Context-Free Parsing Algorithm." *Communications of the ACM*, 13(2):94-102, 1970.**  
The foundational algorithm. The three operations — Predict, Scan, Complete — are described here. Earley's original algorithm has O(n³) worst-case time and O(n²) space for ambiguous grammars, O(n²) time for unambiguous grammars, and O(n) time for LR(k) grammars.

**Leo, Joop M.I.A. "A General Context-Free Parsing Algorithm Running in Linear Time on Every LR(k) Grammar Without Using Lookahead." *Theoretical Computer Science*, 82(1):165-176, 1991.**  
Leo's optimization compresses right-recursive chains of deterministic completions. Where Earley's original algorithm would create O(n) completion items for a right-recursive rule matched over n positions, Leo creates a single chain item representing the entire stack, bringing right-recursive parsing to O(n).

**Aycock, John Daniel. "Practical Earley Parsing." PhD dissertation, University of Victoria, 2001.**  
The primary optimization source for this implementation. Chapters of particular relevance:

- Chapter 4: Core item enumeration and LR(0) DFA construction.
- Chapter 6: Safe-set definition and chart garbage collection.
- Chapter 7: Aycock-Horspool nullable symbol handling (prediction past epsilon-nullable nonterminals).

**Kegler, Jeffrey. "Marpa: A Practical General Parser." 2012-2015.**  
Introduced scanless Earley parsing (terminal matching integrated into the Earley loop) and the "Ruby Slippers" virtual token recovery strategy.

**Local design documents**:
- `docs/chalk-ayock-optimizations.md` — Pseudo-code walkthrough of Aycock integration into Chalk's semiring architecture, with implementation status table.
- `docs/bootstrap-meta-grammar.md` — The 10-rule BNF meta-grammar the parser bootstraps from.
- `docs/ir-node-types.md` — Sea of Nodes IR taxonomy produced by the semantic semiring.

---

## Grammar Representation

### Rule and Symbol Objects

The grammar is represented as an array of `Chalk::Grammar::Rule` objects, where the first element is the start rule by convention.

```perl
class Chalk::Grammar::Rule {
    field $name        :param :reader; # LHS nonterminal name (string)
    field $expressions :param :reader; # arrayref of arrayrefs of Symbol
}
```

Each Rule holds `$expressions`: a list of alternatives, where each alternative is a flat list of `Chalk::Grammar::Symbol` objects. An alternative with zero symbols is an epsilon (empty) production.

```perl
class Chalk::Grammar::Symbol {
    field $type       :param :reader; # 'reference' (nonterminal) or 'terminal' (regex)
    field $value      :param :reader; # nonterminal name or regex pattern string
    field $quantifier :param :reader; # undef, '*', '+', or '?'
}
```

A Symbol is either:

- A **terminal**: a regex pattern string (without delimiters). Matched at parse time using `\G`-anchored matching. Example: `\w+`, `\s*`, `\)`.
- A **nonterminal reference**: the name of another rule to predict and complete. Example: `Expression`, `StatementList`.

Symbols may carry a quantifier. The quantifier determines whether a symbol is desugared before parsing or handled inline during parsing (see below).

### Desugaring of Quantifiers

Before the grammar reaches the parser, `Chalk::Bootstrap::Desugar::desugar_grammar()` transforms quantified symbols. The transformation is non-mutating: it produces a new grammar array.

**`+` (one-or-more)**: `X+` is replaced by a reference to `X_plus`. Two helper rules are emitted:

```
X_plus ::= X X_star
X_star ::= X X_star | (epsilon)
```

`X_plus` requires at least one `X`, then zero or more via the right-recursive `X_star`. Because `X_star` has an epsilon alternative, it is nullable and the DFA nullable-set computation will recognize it.

**`*` (zero-or-more)**: `X*` is replaced by a reference to `X_star`:

```
X_star ::= X X_star | (epsilon)
```

**`?` (zero-or-one)**: The `?` quantifier is **not desugared** into a helper rule. It is handled inline by the parser at two points:

1. During LR(0) DFA construction: when a `?`-quantified symbol is encountered in a closure item, the dot is advanced past it as if the symbol were nullable (Aycock-Horspool optimization).
2. During parsing: when an in-progress item's dot lands on a `?` symbol, the parser explicitly creates a skip path advancing past the symbol without matching it, calling `on_skip_optional` on the semiring to maintain positional alignment in semantic contexts.

This inline handling avoids generating a helper rule for every optional symbol, which would double the grammar size for grammars with many optional elements.

The helper rule naming scheme uses `_plus`, `_star`, and `_opt` suffixes, derived deterministically from the base symbol name. Helper rules are appended to the grammar array in sorted order to ensure deterministic DFA construction.

---

## Core Item Index

`Chalk::Bootstrap::CoreItemIndex` enumerates every possible `(rule_name, alt_idx, dot)` triple at grammar construction time and assigns each a small non-negative integer ID. This integer becomes the primary key for all chart operations.

### Why Integer IDs

The classical Earley algorithm represents items as structs or hashes keyed by string. During parsing, membership testing (has this item already been added to the chart?) requires constructing a key and performing a hash lookup. For a grammar with hundreds of rules and parse inputs of thousands of characters, this per-item overhead accumulates.

By pre-enumerating all triples at grammar construction time, the chart can use arrays indexed by integer ID instead of hashes keyed by strings. Membership testing becomes an array dereference.

### Structure

```
field %id_for_key;      # "rule_name:alt_idx:dot" => integer ID
field @id_to_info;      # integer ID => { rule_name, alt_idx, dot }
field @id_to_rule_name; # integer ID => rule name string (O(1) read)
field @id_to_alt_idx;   # integer ID => alt index integer (O(1) read)
field @id_to_dot;       # integer ID => dot position integer (O(1) read)
field @id_to_rule;      # integer ID => Rule object (O(1) read)
field @id_is_complete;  # integer ID => boolean (dot >= alt length)
field @id_symbol_after; # integer ID => Symbol immediately after dot, or undef
field %advance_map;     # core_id => core_id for dot+1 (memoized)
field @id_to_state;     # core_id => DFA state_id (populated by LR0DFA)
```

The parallel arrays (`@id_to_rule_name`, `@id_to_alt_idx`, etc.) are critical for the inner parse loop. Rather than calling methods per item, `_run_parse` extracts array references once per parse and dereferences directly:

```perl
my $ci_completions   = $core_index->completions();
my $ci_symbols_after = $core_index->symbols_after();
my $ci_rule_names    = $core_index->rule_names();
```

These bulk accessors return the underlying array references. Inside the hot agenda loop, `$ci_completions->[$core_id]` replaces `$core_index->is_complete($core_id)`, eliminating method dispatch overhead for the most frequently called operations.

### Registration and Advance

`build_from_grammar($grammar)` registers all triples by iterating over every rule, every alternative, and every dot position from 0 through the length of the alternative. It populates `@id_to_rule`, `@id_is_complete`, and `@id_symbol_after` in the same pass.

`advance($id)` returns the ID for the same `(rule_name, alt_idx, dot+1)` triple, memoizing the result in `%advance_map`. This is called on every Scan and Complete step to move the dot forward.

For a grammar with R rules, an average of A alternatives per rule, and an average RHS length of L symbols, the total number of core items is approximately R * A * (L + 1). The count scales linearly with the grammar; for Chalk's current Perl subset grammar (`docs/chalk-bootstrap.bnf`) the core-item set is small enough that the `@id_is_complete` and `@id_symbol_after` caches fit comfortably in L1 cache, which is the property the optimization depends on.

---

## LR(0) DFA Precomputation

`Chalk::Bootstrap::LR0DFA` constructs a full LR(0) DFA from the grammar before any parsing begins. The DFA is used at parse time to cluster prediction (adding all items for a nonterminal at once) and to pre-populate the scan cache (trying each unique terminal pattern once per position).

### Nullable Set Computation

The nullable set is the set of nonterminals that can derive the empty string. It is computed by fixed-point iteration before DFA construction.

**Seed**: any nonterminal with an empty alternative (epsilon production) is immediately nullable.

**Iteration**: for each non-nullable nonterminal, check whether any alternative consists entirely of nullable symbols. A symbol is nullable if it is:
- A `?`-quantified reference (inherently optional), or
- A nonterminal reference whose rule is already in the nullable set.

The iteration continues until no new nullables are found. Note that `*`-quantified symbols are desugared into helper rules with epsilon alternatives before this computation, so they appear as nullable nonterminals in the set.

```
# Seed
for each rule R:
    for each alt A of R:
        if A is empty: nullable[R] = true

# Fixed point
repeat:
    changed = false
    for each non-nullable rule R:
        for each alt A of R:
            if all symbols of A are nullable:
                nullable[R] = true
                changed = true
until not changed
```

### Epsilon-Closure for Prediction

`_compute_prediction_closure($nonterminal)` computes the set of core items reachable by transitively following nonterminal predictions from a given nonterminal. This is the epsilon-closure of the NFA where each item `[A -> alpha . B beta]` has an epsilon-edge to `[B -> . gamma]` for each alternative of B.

The result is stored in `%prediction_items{$nonterminal}` as an array of `[$core_id, $skip_symbols]` pairs, where `$skip_symbols` is an arrayref of nullable symbol names skipped to reach that dot position (for `on_skip_optional` callback sequencing).

The Aycock-Horspool optimization is applied here: when a nonterminal's alternative begins with a nullable symbol, the dot is also advanced past that symbol, producing an additional entry in the result. This pre-advances items through nullable prefixes so the parser does not need to handle nullable completions during prediction.

### Subset Construction: DFA States

`_build_dfa_states()` constructs the full LR(0) DFA by subset construction:

1. **Start state**: the closure of all dot=0 items for the start rule's alternatives.
2. **Goto computation**: for each state, a single pass over its core IDs groups advanced items by the symbol after the dot (using `Symbol->goto_key()` to prevent collisions between terminal patterns and nonterminal names). Each grouped set becomes the kernel of a new state.
3. **Deduplication**: states are registered by a sorted key of their core IDs. A state already seen is reused; a new state is added to the worklist.

Each state records:

```
{
    id             => $state_id,
    core_ids       => [sorted list of core IDs in this state],
    terminal_map   => { pattern_string => [core_ids expecting this terminal] },
    completion_map => { nonterminal    => [core_ids expecting this nonterminal] },
    goto_table     => { goto_key       => target_state_id },
}
```

The `terminal_map` is the primary structure used during terminal clustering at parse time: it maps each unique terminal pattern to the set of items (within the state) that are waiting for it.

After all states are built, `set_state_for($core_id, $state_id)` is called on the `CoreItemIndex` for each core ID in each state, using first-write-wins (lowest state_id) for determinism on items that appear in multiple states. This populates `@id_to_state` in the `CoreItemIndex`.

### Complexity

For a grammar with S DFA states, the construction time is O(S * I * log I) where I is the number of core items per state (sorting for deduplication keys). In practice S is bounded by 2^I (the number of distinct item sets), but for realistic grammars the DFA is much smaller because most item sets occur only once. The Chalk Perl grammar produces a DFA with a few hundred states.

---

## Chart Structure

The chart is the central data structure of the Earley algorithm. It records, for each input position, which grammar items have been recognized and with what semiring value.

### Indexing Scheme

```
@chart[$pos][$core_id][$rel_dist] = $value
```

- `$pos` (0 .. n): the input position up to which the item has been recognized.
- `$core_id`: integer ID of the `(rule_name, alt_idx, dot)` triple.
- `$rel_dist`: the distance from `$pos` back to the item's origin, computed as `$pos - $origin`. Storing relative distance rather than absolute origin allows the chart to avoid absolute-position hash keys and enables the GC mechanism (positions can be freed without invalidating stored values).

The value stored at `$chart[$pos][$core_id][$rel_dist]` is the semiring value associated with the item whose dot has advanced to `$core_id` with origin `$pos - $rel_dist` and end `$pos`.

### Rationale for Relative Distance

Classical Earley implementations key items by `(rule, dot, origin, end)`, typically using hash tables. Chalk uses a 3D array. The third dimension is relative distance rather than absolute origin for two reasons:

1. **GC compatibility**: when chart position `$p` is freed (nulled or replaced with `[]`), any item at a later position `$q` that spans `$p` still has its relative distance `$q - $p` intact. The GC decision is made at `$q`; once the window before `$q` is freed, relative distances into the freed window are simply never dereferenced again.
2. **Cache locality**: for items with short spans (which dominate in practice), the relative distance is small and the inner array is short.

### Chart Access Helpers

Three methods provide uniform access:

```perl
method _chart_has($chart, $pos, $core_id, $origin)
method _chart_get($chart, $pos, $core_id, $origin)
method _chart_set($chart, $pos, $core_id, $origin, $value)
```

All three convert `$origin` to `$rel_dist = $pos - $origin` internally. Callers work in absolute origin coordinates; the relative encoding is an internal implementation detail.

### Secondary Index: completed_at

```
%completed_at{$rule_name}{$origin}{$pos} = [[$core_id, $origin], ...]
```

This index records completed items grouped by rule name, origin position, and end position. It is used by `_advance_from_completed` to handle the case where a newly predicted item needs to immediately advance over an already-completed nonterminal (a situation that arises with nullable nonterminals appearing multiple times in a rule). Lookup is O(1) by key, avoiding a full chart scan.

Only non-zero completions are indexed; items rejected by `on_complete` (returning semiring zero) are not recorded.

---

## Parse Loop: Predict, Scan, Complete

The parse loop in `_run_parse` iterates over positions 0 through n (where n is the length of the input). At each position it builds an agenda of items to process and runs them through the Predict/Scan/Complete cycle until the agenda is empty.

### Initialization

```perl
my $start_rule = $grammar->[0];
for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
    my $core_id = $core_index->id_for($start_rule->name(), $alt_idx, 0);
    ($chart[0][$core_id] //= [])->[0] = $semiring->one();
}
```

Each alternative of the start rule is seeded at position 0 with origin 0, initialized to `$semiring->one()` (the semiring's multiplicative identity).

### Agenda Construction

At each position, all items with defined values in `$chart[$pos]` are collected into `@agenda` as `[$core_id, $origin]` pairs. The values themselves remain in the chart; the agenda carries only coordinates.

### Pre-prediction and Terminal Clustering

Before processing the agenda, a single pass over the active core IDs at the current position performs two tasks simultaneously:

1. **Prediction** (`_predict`): for any incomplete item expecting a nonterminal, predict that nonterminal by adding all items from its LR(0) epsilon-closure.
2. **Terminal clustering**: look up the DFA state for each active core ID (via `$ci_states_bulk->[$cid]`), then pre-populate the scan cache for each unique terminal pattern in that state's `terminal_map`.

Both tasks use deduplication (via `%seen_states` and `%seen_patterns`) so each state and each pattern are processed at most once per position. This is the terminal clustering optimization from Aycock: instead of calling the regex engine once per item per terminal, each distinct pattern is matched exactly once per position.

### Predict

```perl
method _predict($rule_name, $pos, $chart, $agenda, $predicted_at)
```

`_predict` is called when an incomplete item's next symbol is a nonterminal. It looks up `$lr0_dfa->prediction_items_for($rule_name)`, which returns the precomputed `[$core_id, $skip_symbols]` pairs for that nonterminal.

For each pair:
- If the item is not already in the chart at `(pos, core_id, origin=pos)`, it is added with value `$semiring->one()` (possibly combined via `multiply(value, one())` for each skipped nullable symbol — see Nullable Handling).
- The item is pushed to the agenda.

A `%predicted_at` hash prevents redundant prediction: if a nonterminal has already been predicted at the current position, subsequent calls for the same nonterminal at the same position return immediately.

### Scan

```perl
method _scan($core_id, $origin, $value, $symbol, $pos, $input, $chart, $n, $agenda, $predicted_at)
```

Scan is called for incomplete items whose next symbol is a terminal. It:

1. Checks the scan cache for a previously computed `(pos, pattern)` match result.
2. If not cached, calls `Chalk::Bootstrap::Terminal::match($input, $pos, $pattern)` which performs `\G`-anchored matching at `$pos`. The result (end position or undef on failure) is stored in the cache.
3. If the match succeeds, builds a scan-annotated `Chalk::Bootstrap::Context` via `_make_scan_context($rule_name, $alt_idx, $pos, $matched, $is_predicted)`. The Context carries the scan event's information in its `annotations` slots.
4. Calls `$semiring->multiply($value, $scan_ctx)` to produce the new semiring value. Semirings that reject the scan (e.g., TypeInference rejecting a keyword as an identifier) return their zero element from `multiply`; the result is filtered out via `is_zero` and not added to the chart.
5. Advances the core ID via `$core_index->advance($core_id)` and stores the new value at `$chart[$end_pos][$new_core_id][$end_pos - $origin]`.
6. If the match is zero-width (end_pos == pos), the advanced item is pushed to the current position's agenda for immediate processing.

When an existing value is present at the target chart cell, the semiring `add` operation merges the two values (disambiguation).

### Complete

```perl
method _complete($completed_core_id, $origin, $completed_value, $pos, $chart, $agenda)
```

Complete is called for items where `$ci_completions->[$core_id]` is true (dot has reached the end of the alternative). It advances all waiting items at `$origin` that are expecting the completed nonterminal.

A completion-annotated `Chalk::Bootstrap::Context` is built via `_make_complete_context($rule_name, $alt_idx, $pos, $origin)`. The parser calls `$semiring->multiply($completed_value, $complete_ctx)` to produce the final completion value. Semirings that reject the completion (e.g., SemanticAction applying an action that returns zero) produce the semiring's zero element; rejected completions are not indexed in `%completed_at` and do not propagate.

The actual completion search uses `%_waiting_core_ids{$rule_name}`, a precomputed map from nonterminal name to the list of core IDs that have their dot immediately before that nonterminal. This is built once at construction time from the `CoreItemIndex` and never mutated.

For each waiting core ID, the chart at `$origin` is scanned for live values (defined entries). Each live waiting value is combined with the completed value via `$semiring->multiply($waiting_value, $completed_value)`, and the advanced item is added to the chart at `$pos`.

The Leo optimization path is checked first (see Leo Optimization below).

### Acceptance

After the main loop, acceptance is checked by looking for a completed start rule item spanning the entire input:

```perl
for my $alt_idx (...) {
    my $end_dot = scalar($start_rule->expressions()->[$alt_idx]->@*);
    my $core_id = $core_index->id_for($start_rule->name(), $alt_idx, $end_dot);
    my $end_oh  = $chart[$n][$core_id];
    if (defined $end_oh && defined $end_oh->[$n]) {
        return $end_oh->[$n];   # origin 0, rel_dist = n - 0 = n
    }
}
```

A defined value at `$chart[$n][$core_id][$n]` (where `$n` is both the end position and the relative distance encoding origin=0) means the start rule completed from position 0 to position n.

---

## Semiring Integration

The parser is parameterized by a semiring object that extends pure recognition with arbitrary semantics. The semiring interface follows Goodman's (1999) formalism: four algebraic operations (`one`, `is_zero`, `multiply`, `add`) are sufficient to express all parse computations. Scan, completion, and optional-skip events are represented as specially-annotated `Chalk::Bootstrap::Context` values passed as the right operand to `multiply`; there are no separate callbacks.

This is a deliberate reduction from an earlier callback-based interface (`on_scan`, `on_complete`, `should_scan`, `on_skip_optional`, `on_epoch_commit`) that was eliminated in Milestones 17-18 (PRs #702, #715) as premature optimization — the `multiply` path produces the same semantic results, and the callbacks added complexity without earning it. See `docs/plans/2026-04-12-unified-context-design.md` and `docs/plans/2026-04-12-on-complete-elimination-design.md` for the rationale, and the Appendix: History of `context-comonad.md` for the narrative.

### Required Methods

**`one()`**
Returns the semiring's multiplicative identity. Used to initialize new items when they are first predicted or scanned. For the Boolean semiring, `one()` returns a true value. For the SemanticAction semiring, `one()` returns a fresh `Context` with no children.

**`is_zero($value)`**
Returns true if `$value` is the semiring's additive identity (the absorbing element). A zero value means the parse path is rejected. Items with zero values are not propagated. The parser checks `is_zero` after every `multiply` and `add` result.

**`multiply($left, $right)`**
The core combining operation. Called in three distinct situations, distinguished by the right operand:

- **Completion:** `$left` is a waiting item's value and `$right` is a completed item's value. Represents sequential composition: recognize `$left` then the completed sub-parse.
- **Scan event:** `$right` is a scan-annotated `Context` built by `_make_scan_context`. The semiring inspects the Context's `annotations` to read the matched text, rule name, alt index, position, and `is_predicted` set, and produces an updated value. Semirings that reject the scan (e.g., TypeInference rejecting a keyword as an identifier) return `zero()`.
- **Completion event:** `$right` is a completion-annotated `Context` built by `_make_complete_context`. The semiring reads the completing rule's identity and position span, applies any per-rule semantic action, and produces an updated value. Rejection returns `zero()`.
- **Skip-optional event:** `$right` is `one()` — no event-carrying Context is needed because skipping a `?`-quantified symbol is algebraically identity composition; semirings that want positional placeholders (e.g., SemanticAction) detect this through their `multiply` implementation and insert an undef child.

**`add($existing, $new)`**
Merges two values for the same chart cell when a second derivation reaches it. Represents choice (ambiguity): the two derivations are combined into one value. For the Boolean semiring, `add` is logical OR. For filtering semirings, `add` may use refaddr-based first-wins preference to select a survivor. For SemanticAction, it appends to an arrayref of alternatives.

### Surviving Callbacks

One callback survived the Milestone 17-18 elimination:

**`on_merge($winner, $loser)` (optional)**
Called by `FilterComposite` after `add` selects a survivor, as a workaround for an Earley stale-value merge bug where CFG-state updates on the loser could otherwise be dropped. Only `SemanticAction` implements it. See `docs/architecture/context-comonad.md` Appendix for the history.

### Value Lifecycle

```
predict:   item value = semiring->one()
           (for each nullable prefix: value = multiply(value, one()))

scan:      scan_ctx = _make_scan_context(rule, alt, pos, matched, is_predicted)
           new_value = semiring->multiply(prev_value, scan_ctx)
           if is_zero(new_value): skip
           else: store at chart[$end_pos][$new_core_id][$end_pos - $origin]

complete:  complete_ctx = _make_complete_context(rule, alt, pos, origin)
           completed_value = semiring->multiply(chart_value, complete_ctx)
           if is_zero(completed_value): skip
           else: store back into chart[$pos][$core_id][$pos - $origin]
                 for each waiting item:
                     new_value = semiring->multiply(waiting_value, completed_value)
                     if existing: merged = semiring->add(existing, new_value)
                     else: store new_value
```

---

## Leo Optimization

The Leo optimization compresses right-recursive chains of deterministic completions. Without it, a right-recursive rule like `A ::= X A` matched over n positions produces O(n) completion items — each `A` at position i spawns a completion that advances the `A` at position i-1, which spawns a completion that advances the `A` at position i-2, and so on. With Leo, the entire chain is represented as a single Leo item and resolved in O(1).

### Eligibility

A completion is eligible for Leo optimization when:

1. Exactly one waiting item was found in the chart for the completed nonterminal at the origin position (deterministic: no ambiguity).
2. Advancing that waiting item would immediately complete it (the waiting item is in the penultimate position: after advancing, the dot is at the end of the alternative).
3. The semiring supports Leo (`$_leo_enabled` is true).
4. No Leo item was already resolved for this completion (the Leo path and the standard path are mutually exclusive at each step).

### Leo Item Structure

```perl
$leo_items{$rule_name}{$origin} = {
    leo          => true,
    rule_name    => $rule_name,
    top_origin   => $top_origin,
    top_core_id  => $top_core_id,
    value        => $chain_value,
    wait_core_id => $leo_candidate_core_id,
    wait_origin  => $leo_candidate_w_origin,
};
```

- `rule_name` / `origin`: the key. When a completion of `$rule_name` arrives with this `origin`, the Leo item is consulted first.
- `top_core_id` / `top_origin`: the top of the chain — the waiting item at the far end. Rather than walking each link, the Leo item resolves directly to the top.
- `value`: the accumulated semiring value for the entire chain from the current origin to the top.
- `wait_core_id` / `wait_origin`: the immediate waiting item (the first link). Stored so `_complete` can skip it in the standard completion loop (to avoid double-advancing).

### Chain Extension (Disabled)

Earlier Leo implementations extended parent chains: when a Leo-eligible completion arrived and a parent Leo item existed, the chains were merged into a single multi-level item by multiplying the parent's chain value with the new completed value. Chalk disabled this behavior (see `Earley.pm:1396-1400`). The reason is semiring-value equivalence: baking intermediate completions into the stored value produced parse trees with extra intermediate nodes that did not match the non-Leo path's output. Each Leo item now covers exactly one chain level, so the Leo-optimized parse and the non-optimized parse produce the same tree for every semiring. The test `t/bootstrap/leo-graph-equivalence.t` enforces this invariant.

### Semiring Compatibility

Leo is structurally correct for every semiring Chalk uses (proven by `t/bootstrap/leo-graph-equivalence.t`). The constructor parameter `leo_enabled` exists solely as a test-time override so that the Leo and non-Leo paths can be compared; there is no runtime capability gate on the semiring. (The disabled chain-extension optimization, described above, is what preserves this equivalence.)

---

## Nullable Handling: Aycock-Horspool

Nullable symbols (nonterminals that can derive the empty string) require special treatment in Earley parsing. The classical algorithm handles nullables by including epsilon completions in the chart, which is correct but inefficient: a nullable nonterminal present in many rule prefixes causes O(n) prediction overhead at every position.

Aycock and Horspool (1999, formalized in Aycock 2001 Chapter 7) precompute the effect of nullable predictions into the LR(0) DFA. The result is that prediction at parse time handles nullable prefixes without any runtime epsilon completions.

### Precomputation

During `_compute_prediction_closure`, when a predicted alternative begins with a nullable symbol (either `?`-quantified or in the nullable set), the algorithm also adds a dot-advanced item (advancing past the nullable symbol). If multiple consecutive nullable symbols appear at the start of an alternative, items are generated for each intermediate dot position, each recording the cumulative list of skipped symbol names.

Example: for `A ::= B? C D`, where B is optional:
- `[A -> . B? C D]` is added (dot before B).
- `[A -> B? . C D]` is also added (dot past B, skipping it), with `skip_symbols = ['B']`.

### Runtime Handling for Mid-Rule Optionals

The DFA prediction closure handles optional symbols at the start of alternatives. Optional symbols that appear mid-rule (after the dot has already advanced to them during parsing) are handled differently:

When the agenda processes an item `[A -> alpha . B? beta]` where B is `?`-quantified, the parser explicitly creates a skip path:

```perl
if ($symbol->is_quantified() && $symbol->quantifier() eq '?') {
    my $skip_value = $semiring->multiply($value, $semiring->one());
    if (defined $skip_value && !$semiring->is_zero($skip_value)) {
        my $skip_core = $core_index->advance($core_id);
        # add/merge skip_value into chart[$pos][$skip_core][$pos - $origin]
    }
}
```

This advances the dot past B without matching anything. Skipping a `?`-quantified symbol is algebraically identity composition — `multiply(value, one())` — which is the whole reason the old `on_skip_optional` callback could be eliminated.

### Positional Child Alignment

Semirings that care about positional child indexing (e.g., SemanticAction, whose action methods access children by position) detect skip events through their `multiply` implementation. When SemanticAction's `multiply` sees an `one()` right operand during rule parsing, it inserts a synthetic undef child into the Context so that all children maintain their expected positional index. Without this, a rule `A ::= B? C` where B is skipped would produce a Context with C at child index 0 instead of child index 1, misaligning the semantic action's positional access.

Semirings that do not care about positional indexing (e.g., Boolean) naturally do nothing on `multiply(value, one())` by the multiplicative-identity law, so the machinery has no cost for them.

---

## Safe-Set Garbage Collection

Earley charts grow linearly with input length: an input of n characters potentially requires n+1 chart positions. For large inputs (Perl source files of several thousand lines), retaining all chart positions simultaneously would require substantial memory.

Aycock's Chapter 6 defines a condition — the safe set — under which chart positions can be freed during parsing without affecting correctness.

### Definition

A chart position `$pos` is a safe set if three properties all hold:

1. **Property 1**: At least one completed item (final item, dot at end) exists at this position.
2. **Property 2**: No incomplete item at `$pos` is expecting a symbol that also appears as the last symbol of any completed item at `$pos`. This checks the symbol after the dot of incomplete items against the set of last symbols of completed items.
3. **Property 3**: No completed item at `$pos` resulted from an epsilon (empty) alternative.

These three properties together ensure that the parse has made definite progress at `$pos` — there is no ambiguity about what was just recognized, so everything in the window before the previous safe set is no longer needed.

### Conservative Refinement

The implementation uses a slightly more conservative check for Property 2 than Aycock's original specification. Aycock's version checks the symbol *before* the dot of incomplete items (the last-consumed symbol). The implementation instead checks the symbol *after* the dot (the next-expected symbol).

This change is necessary because zero-width terminal patterns (such as the whitespace/comment pattern `(?:\s|#[^\n]*)*`) can match empty strings. A predicted item at dot=0 has no last-consumed symbol and would be skipped by Aycock's original check, but it may still indicate ambiguity when its expected-next symbol conflicts with the last symbol of a completed item. The more conservative check catches this case.

The trade-off is that some positions that would be safe under Aycock's original definition are not recognized as safe here. In practice, for LR-like grammars (which the Chalk Perl grammar mostly resembles), safe sets occur frequently enough at list-element boundaries that this does not significantly impact GC effectiveness.

### GC Mechanism

When a safe set is found at `$pos` and the previous safe set was at `$last_safe_pos`, the parser checks whether it is safe to free the window `($last_safe_pos, $pos)`. The check verifies that no incomplete item at `$pos` has its origin inside the candidate window (an item with such an origin would still need the chart data at its origin for future completions).

If the window is safe, each position `$p` in `($last_safe_pos, $pos)` has its chart slot replaced with `[]`, its scan cache entry deleted, and its `%completed_at` entries removed. The `_gc_stats{positions_freed}` counter is incremented for each freed position.

```perl
$_gc_stats{safe_sets_found}++;
for my $sp ($last_safe_pos + 1 .. $pos - 1) {
    if (defined $chart[$sp] && $chart[$sp]->@*) {
        $chart[$sp] = [];
        delete $_scan_cache{$sp};
        $_gc_stats{positions_freed}++;
    }
}
```

GC statistics are available after parsing via `$earley->gc_stats()`, which returns a hash with `positions_freed` and `safe_sets_found` keys.

---

## Epoch Garbage Collection

Safe-set GC handles locally unambiguous regions. For grammars with long-range structures (such as statements spanning many positions), safe sets may not occur frequently. Epoch GC provides a complementary mechanism tied to semantic boundaries.

### Mechanism

When `on_complete` is called for a rule that represents a top-level statement boundary (such as `StatementItem` in the Chalk Perl grammar), the semiring may call the `$on_epoch_commit` callback passed to it:

```perl
$on_epoch_commit->($origin, $end);
```

This registers a pending sweep covering positions `($origin, $end)`.

After the agenda for the current position is fully processed, pending sweeps are drained. For each sweep `($sweep_origin, $sweep_end)`:

1. **Phase 1** — Null completed items: for positions strictly inside `($sweep_origin, $sweep_end)`, completed items whose origin is strictly inside the epoch are set to undef. Incomplete items are left intact (they may still be needed by future completions, e.g., ElsifChain waiting for a recursive child).

2. **Phase 2** — Compact empty positions: any position where all values are now undef has its chart slot replaced with `[]` and its scan cache entry deleted.

The sweep skips the `$sweep_origin` position itself, because the origin position holds parent-rule items (such as Program or StatementList) that span beyond this epoch.

### Interaction with Safe-Set GC

The two GC mechanisms are complementary and independent:

- Safe-set GC fires at any position identified as locally unambiguous, regardless of semantic structure.
- Epoch GC fires at explicit semantic boundaries declared by the semiring via `on_epoch_commit`, allowing the grammar author to guide GC at points where they know long-spanning items are complete.

In practice, safe-set GC handles the interior of expressions and epoch GC handles statement and block boundaries.

---

## Scan Caching and Terminal Clustering

### Scan Cache

```perl
field %_scan_cache;  # {$pos}{$pattern_string} => $end_pos (or undef)
```

The scan cache memoizes regex match results per `(position, pattern)` pair within a single parse. When the same terminal pattern appears in multiple grammar rules (which is common — whitespace patterns, identifier patterns, and punctuation patterns are used throughout the grammar), the regex engine is invoked only once per position per unique pattern.

A measurement in the ABOUTME comments notes that 28% of scans are duplicates and 93% of attempted scans fail. The cache eliminates the 28% redundant regex invocations; the 93% failure rate underscores why memoizing failures (storing `undef` as a negative result) is as important as memoizing successes.

The cache is populated at two points:

1. **Terminal clustering pre-pass** (before the agenda loop): the DFA state for each active item is consulted. Its `terminal_map` lists all patterns that any item in that state is waiting for. Each unique pattern is matched once and the result stored.
2. **`_scan` fallback**: if a pattern was not covered by the pre-pass (because the item's DFA state was not pre-scanned), the regex is run on demand and the result cached.

### Terminal Clustering

The pre-pass uses `%seen_states` to avoid re-scanning the same DFA state twice at the same position:

```perl
my $state_id = $ci_states_bulk->[$cid];
next unless defined $state_id;
next if $seen_states{$state_id}++;

my $tmap = $lr0_dfa->state($state_id)->{terminal_map};
for my $pstr (keys $tmap->%*) {
    next if $seen_patterns{$pstr}++;
    next if exists $_scan_cache{$pos} && exists $_scan_cache{$pos}{$pstr};
    my $pattern = $regex_cache{$pstr} //= qr/$pstr/;
    $_scan_cache{$pos}{$pstr} = Chalk::Bootstrap::Terminal::match($input, $pos, $pattern);
    $_scan_stats{clustered_scans}++;
}
```

This means the number of regex invocations per position is bounded by the number of unique terminal patterns in the DFA states that are active at that position, rather than by the number of items.

### Compiled Regex Cache

```perl
field %regex_cache;  # pattern_string => qr// object
```

Terminal patterns are stored in grammar as strings (the raw regex without delimiters). The `%regex_cache` maps each string to its compiled `qr//` object, which persists for the lifetime of the Earley object (across multiple `parse` calls). This avoids recompiling the same regex pattern on every parse.

### Scan Statistics

After parsing, `$earley->scan_stats()` returns a hash with:
- `total_matches`: total number of scan attempts (including cache hits).
- `cache_hits`: number of scans that found a cached result.
- `clustered_scans`: number of scans performed during the terminal-clustering pre-pass.

---

## Error Recovery

When the agenda at position `$pos` is empty and `$pos` is past the furthest chart position reached by scanning, the parse has stalled. With error recovery enabled (`recover => true`), the parser attempts two tiers of recovery before giving up.

### Tier 1: Ruby Slippers

Ruby Slippers recovery (named after Marpa's "virtual token" concept) attempts to continue the parse by virtually inserting a closing delimiter that the parser is known to be waiting for.

The set of eligible virtual tokens is fixed: `)`, `]`, `}`, `;` and their escaped variants. The parser checks `$_diag_expected` (the set of terminal patterns that were expected at the last active position) for any delimiter pattern. For each such pattern, it scans the chart at the last active position for items that were waiting for it. Each such item is advanced as if the delimiter had been scanned — calling `on_scan` with an empty matched string and placing the advanced item at the current (stalled) position.

If any items are successfully inserted, the position's agenda is rebuilt from the newly inserted items and parsing continues. A recovery event is recorded in `@_errors`:

```perl
{ position => $pos, expected => {...}, recovery_type => 'ruby_slippers' }
```

### Tier 2: Panic Mode

If Ruby Slippers fails, the parser scans forward from the stalled position to find a synchronization point. `_find_sync_point($input, $start_pos)` implements a simple brace-depth-tracking scan:

- At depth 0, a `;` character is a sync point of type `semicolon`.
- A `}` that would take depth below 0 is a sync point of type `block_close`.
- At depth 0, one of the declaration keywords `method`, `field`, `class`, `sub`, `use` (followed by a non-word character) is a sync point of type `keyword`, provided it is not at the very start of the scan.

When a sync point is found at `$sync_pos`, the parser re-seeds the chart at `$sync_pos` with fresh start-rule items (initialized to `$semiring->one()`) and jumps directly to that position:

```perl
for my $alt_idx (...) {
    ($chart[$sync_pos][$seed_id] //= [])->[0] = $semiring->one();
}
$pos = $sync_pos;
next;
```

A recovery event is recorded with `sync_pos` and `sync_type`.

At most 20 recovery events are attempted in total (to prevent unbounded recovery loops). After 20 errors, the parser stops.

### EOF Recovery

A separate Ruby Slippers pass runs after the main loop when recovery is enabled and the start rule has not completed. It iterates up to 10 times, checking whether inserting virtual closing delimiters at position `$n` (end of input) allows the start rule to complete. After each insertion, completions are re-processed via a local agenda. If the start rule completes, the value is returned.

### Recovered Parse Result

With recovery enabled and errors recorded, the parser accepts a completion of the start rule from any origin (not just origin=0). This means a recovered parse returns a partial result covering the portion of the input that was successfully parsed.

The list of recovery events is available via `$earley->errors()`.

---

## Performance Analysis

### Time Complexity

The standard Earley algorithm has:
- O(n³) worst case for ambiguous grammars.
- O(n²) for unambiguous grammars.
- O(n) for LR(k) grammars (with Leo optimization on right-recursive rules).

The Chalk grammar for Perl is approximately LR-like with some ambiguous regions. In practice:

- The Leo optimization brings most list and statement sequences to O(n).
- The safe-set and epoch GC bound chart memory usage.
- The scan cache and terminal clustering reduce the constant factor on the O(n) scan work.

### Space Complexity

Without GC, chart space is O(n * I) where I is the number of distinct items per position (bounded by the number of core items times the number of origin positions, giving O(n² * C) in the worst case where C is the number of core items).

With safe-set GC, positions outside the live window are freed as parsing advances. For LR-like grammars with frequent safe sets, the live window is bounded by the length of the longest "statement" (the span between safe sets), which for typical Perl is O(1) relative to the input length. This brings effective space usage to O(n) in the common case.

### Profiling Hooks

When the environment variable `EARLEY_PROFILE` is set, the parser records statistics per position:
- Total items across all positions.
- Maximum items at any single position (and which position).
- Live position span at each sample.
- Resident set size (RSS) from `/proc/self/status`, sampled every 1000 positions.

This data is written to STDERR as `PROFILE pos=... items_here=... total=... max=... live_span=... rss=...kB` lines and is also available via `$earley->profile_data()` after parsing.

When `EARLEY_SAFE_DEBUG` is set, safe-set evaluation decisions are traced to STDERR with position, final item count, and which properties caused failure.

When `EARLEY_ORIGIN_DEBUG` is set, the true minimum live origin across all chart positions is computed and traced every 10 positions, showing how far behind the GC window is lagging relative to the parse frontier.

### Measurement Results

The ABOUTME comment in `Earley.pm` notes the scan cache observation: 28% of scans are duplicates and 93% of attempted scans fail. These numbers were measured on the Chalk grammar against Perl source files. The cache eliminates the 28% redundant regex invocations with O(1) lookup cost, and the clustered pre-scan eliminates the majority of the 93% failure attempts by predetermining which patterns can possibly match before the per-item scan loop runs.

The XS compilation of `_run_parse` (where the parser is compiled to native C via Chalk's XS backend) achieves approximately 2x speedup over pure Perl on moderate inputs and recognizes large Perl source files (~5000 lines) in roughly 1 second.

---

## Appendix: Optimization Status Summary

The following table reflects the implementation status of optimizations from Aycock's dissertation as of the current branch.

| Optimization | Status | Location |
|---|---|---|
| Core item index (integer IDs) | Complete | `CoreItemIndex.pm` |
| LR(0) DFA prediction clustering | Complete | `LR0DFA.pm`, `Earley.pm _predict` |
| Nullable set computation | Complete | `LR0DFA.pm _compute_nullable_set` |
| Aycock-Horspool dot advancement | Complete | `LR0DFA.pm _closure`, `_compute_prediction_closure` |
| Safe-set GC | Complete | `Earley.pm _is_safe_set` |
| Epoch GC | Complete | `Earley.pm on_epoch_commit` + `@pending_sweeps` |
| Leo optimization | Complete | `Earley.pm _complete` Leo path |
| Scan result cache | Complete | `Earley.pm %_scan_cache` |
| Terminal clustering | Complete | `Earley.pm` pre-scan pre-pass using DFA `terminal_map` |
| Compiled regex cache | Complete | `Earley.pm %regex_cache` |
| Lazy semiring initialization | Not implemented | Described in `docs/chalk-ayock-optimizations.md` |
| Bitmap set membership | Not implemented | Described in `docs/chalk-ayock-optimizations.md` |
| Earley set compression (dead states) | Not implemented | Described in `docs/chalk-ayock-optimizations.md` |

The unimplemented optimizations (lazy initialization, bitmap membership, dead-state compression) are speculative improvements. The scan cache partially mitigates the absence of lazy initialization by ensuring that the regex matching cost — which is the primary work avoided by lazy initialization — is paid at most once per `(position, pattern)` pair rather than once per item.
