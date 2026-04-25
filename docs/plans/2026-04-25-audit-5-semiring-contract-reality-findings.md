# Audit 5 — Semiring Contract Reality Findings

**Date:** 2026-04-25
**Companion to:** Phase A.2 audits 1-3, Phase A.2 synthesis,
`docs/plans/2026-04-25-bug-4-rca-and-remediation.md`,
`docs/plans/2026-04-24-semiring-contract-drift.md`,
`~/.claude/projects/-home-perigrin-dev-chalk/memory/semiring_ordering.md`.
**Status:** Read-only investigation. No code changes. Probe-driven verification of the
five RCA-debrief findings about the semiring layer's actual contract.

## Summary

| Finding | Verdict | Severity |
|---|---|---|
| 1. TypeInference is position-dependent | **Confirmed** — but the position-dependence is binary (TI as `_sa()` vs not), not ordinal | Architectural — invalidates "filtering semirings commute" as written |
| 2. SA-last is correctness, not optimization | **Confirmed correctness** — SA-not-last produces parses that pass at recognition level but build NO IR | Documentation drift — the memory file calls it "performance"; it is structural correctness |
| 3. TI output crosses the parser boundary | **Confirmed** — Actions.pm reads TI's `method_return_type` to populate `MethodInfo->return_type`; structural similarity to SA's IR | Architectural — TI is not "just a filter," it is a typed-data producer for compiler stages |
| 4. Inter-filter read/write dependencies | **Refuted (mostly)** — only TI reads its own slot; Boolean/Precedence/Structural read only their own slot + parser metadata. SA reads TI via `current_type_context()`. The brief's hypothesis about Structural reading TI's `is_*_typed` tags does NOT match current code | Brief framing mistake — there is no inter-filter read/write graph |
| 5. Side effects in semiring operations | **Confirmed multi-level** — MOP mutation (`declare_class`, `declare_field`, etc.), NodeFactory hash-cons + `cfg_counter` increment, class-level `$_method_returns`, `on_merge` mutates winner Context's `annotations->{cfg}` in place, `set_mop`/`set_type_context` set class-level state | Latent correctness — multi-firing is known (dedupe in `declare_import`) but only `declare_import` has dedupe; `declare_field`/`method`/`sub` do not |

**Counts:** 3 confirmed, 1 confirmed-as-correctness-rule (#2), 1 refuted-as-stated (#4 brief
hypothesis wrong about Structural). Three additional findings discovered during
investigation (see "Additional findings" below).

## Methodology

Probe-driven isolation per Phase A.2 pattern. Probes lived in `/tmp/audit5-*.pl`,
deleted at end of session. The probe pipeline reuses TestPipeline.pm to generate
the Perl grammar via the BNF target (the same path tests like
`perl-recognize-phase1.t` use), then constructs FilterComposite parsers with
custom semiring orderings.

For Finding 1: vary the order of the four filter semirings, with Boolean first
and SA last fixed. Also vary whether TI is in `_sa()` slot vs filter slot.
For Finding 2: place SA in non-last position and check IR construction.
For Finding 3: text search for `annotations->{type}` and `current_type_context`
references outside `lib/Chalk/Bootstrap/Semiring/`.
For Finding 4: text search for all `annotations()->` references in each semiring
and synthesize the read/write graph; then probe filter swaps that should change
behavior if cross-slot dependencies existed.
For Finding 5: monkey-patch instrumentation in /tmp probes for `Chalk::MOP::Class`
declare_*, `Chalk::Bootstrap::IR::NodeFactory.make`, and inspection of
class-level `my $_X` state in semiring classes.

The Perl grammar IR was built once via `perl_pipeline()` and reused across probes
to keep the comparison apples-to-apples.

## Finding 1: TypeInference position-dependence

**Claim:** TI behaves differently in SA position vs filter position; the
"filtering semirings commute" architectural claim is violated by at least TI.

**Probe results:**

The corpus (10 inputs spanning all the brief's example classes) was tested
across 6 permutations of `[B, P, T, S, A]` keeping B first and A last. Result:
**zero pass/fail divergences across all six permutations.** The four filter
semirings commute pairwise when SA is `_sa()`.

The position-dependence becomes visible when comparing configurations where TI
is `_sa()` vs configurations where TI is in `_annotation_semirings()`:

| Stack | `my @x = map { defined $_ } @arr;` | `my @y = map { $_ } (1, 2, 3);` | `my %h = map { $_ => 1 } @arr;` |
|---|---|---|---|
| `[B,T]`     | PASS | PASS | PASS |
| `[B,T,A]`   | **FAIL** | **FAIL** | **FAIL** |
| `[B,P,T]`   | PASS | PASS | PASS |
| `[B,P,T,A]` | **FAIL** | **FAIL** | **FAIL** |
| `[B,P,T,S]` | PASS | PASS | PASS |
| `[B,P,T,S,A]` | **FAIL** | **FAIL** | **FAIL** |

The pattern is: when TI is the last semiring (`_sa()`), it does not reject. When
something is added after TI (anything that puts TI in `_annotation_semirings()`),
TI rejects. This is the same mechanism the Bug 4 RCA already documented at a
finer-grained level.

**Code path of position-dependence (file:line):**

`lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:20-27`:

```perl
method _sa() { return $semirings->[-1] }
method _annotation_semirings() {
    return grep {
        blessed($_) && $_->can('slot_name') && defined $_->slot_name()
    } $semirings->@[0 .. $#{ $semirings } - 1];
}
```

The structural assumption is that the last semiring is "the SA" and all others
that have a `slot_name` are "annotation semirings." When TI is at position
`[-1]`:

1. `_sa()` returns TI.
2. `_annotation_semirings()` excludes TI (it's at index `$#-1` excluded from the slice).
3. In `multiply()` (line 155-166), only annotation semirings have their results
   stored as `slot_results` and merged into the winner Context's `annotations`
   via `_wrap_sa_result` (line 186, 109-111).
4. TI's tag-hash output from scan/complete events is therefore not stored in
   `annotations->{type}` on shared Context nodes.
5. In `_complete_type` (`TypeInference.pm:340-365`), when TI's CallExpression
   walker calls `_get_call_symbol`/`_get_item_types`, every node it walks has
   `annotations->{type} = undef`, so the walker returns `undef`, and the
   signature-validation block at line 343 (`if ($call_sym)`) is a no-op.

When TI is in filter position (`[B,T,A]` or any stack where TI is not `[-1]`),
its tag-hash output IS stored in `annotations->{type}` for every node, and the
walker finds the values it needs to perform signature validation — which then
rejects per Bug 4's RCA.

This is the same mechanism described in the Bug 4 RCA's "Why the audit thought
this was an interaction" section, generalized: TI's effective behavior depends
on whether it is the last semiring or not. The dependency is binary (last vs
not-last), not ordinal (position 1 vs 2 vs 3 vs 4 — those don't matter).

**Scope:**

Only TI shows position-dependence (last vs not-last). Structural also has
something at the boundary of last-vs-not-last — when Structural is `_sa()`,
its returns are integers, and `_wrap_sa_result` produces a Context with no
children, so TI walkers find nothing (this matches the RCA observation about
`[B,P,T,S]`'s degenerate tree). But for Structural, "TI walkers find nothing"
is the *intended* behavior; for TI itself, "TI walkers find nothing" is an
*accidental* behavior that masks Bug 4.

The claim in `~/.claude/projects/-home-perigrin-dev-chalk/memory/semiring_ordering.md`
that "the four filtering semirings commute" is true at the pass/fail level for
**filter ↔ filter swaps** with SA last. It is false for **TI ↔ SA position
swap**. The memory file does not distinguish these cases and is misleading as
written.

**Severity:** Architectural-level correctness, not bug-level correctness.

- Today: TI being in last position never happens in production (`TestPipeline.pm`
  always puts SA last). Bug 4 manifests because TI is in filter position; TI
  rejects via signature validation that it could only execute because of the
  position.
- Future: any work that changes the canonical semiring order (e.g., adding a
  6th semiring, or moving SA earlier in the stack — explored under Finding 2)
  has to reckon with TI's binary position-dependence. The class assumption of
  `_sa()` returning `[-1]` is structurally enforced; the contract that
  "filtering semirings commute" is documentation-only.

**Suggested remediation shape (commentary):**

1. **Documentation:** update the memory file and `parsing-pipeline.md`'s
   "Ordering Rationale" section to state explicitly: filter semirings commute
   pairwise *with each other*; the "filtering vs SA" boundary is structurally
   significant and not a commutativity boundary. Bug 4's "TI+SA interaction"
   framing in the audit was correct as observation; the underlying mechanism
   is "TI's behavior depends on whether it is in `_annotation_semirings()`."
2. **Architecture:** the position-dependence is a side-effect of TI not having
   a uniform output-storage model. Decision 5's flow-typing completion would
   make TI's output flow through typed nodes rather than `annotations->{type}`
   slots, which would dissolve this position-dependence entirely.
3. **Short term:** Bug 4's walker fix (Shape 1, Option 1 in the RCA) is
   compatible with TI's continued position-dependence; it just changes what
   the walker finds when TI is in filter position. The fix does not address
   the underlying contract issue.

## Finding 2: SA-last as correctness or optimization

**Claim:** SA-last is encoded structurally in `FilterComposite._sa()` as
`$semirings->[-1]`; the rationale is documented as "performance" in the memory
file, but the code suggests structural enforcement. Is SA-last a correctness
rule or an optimization?

**Probe results:**

Test inputs were run through configurations with SA in non-last position, e.g.
`[B,P,T,A,S]` (S as `_sa()`, A as a filter). Outcomes:

| Input | `[B,P,T,S,A]` (canonical) | `[B,P,T,A,S]` (SA in pos 3) |
|---|---|---|
| `my $x = 1;` | PASS, focus = ConciseTree | PASS, focus = (empty) |
| `my $x = 1 + 2 * 3;` | PASS, focus = ConciseTree | PASS, focus = (empty) |
| `class Foo { ... }` | PASS, focus = ConciseTree | PASS, focus = (empty) |

**SA-not-last produces parses that pass at the recognition level but build NO
IR.**

This is because:

1. SA's `slot_name()` returns `undef` (`SemanticAction.pm:351-353`).
2. `_annotation_semirings()` skips semirings with `undef` slot_name (line 25-26).
   So when SA is in a filter slot, it is *excluded from `_annotation_semirings()`*
   — its multiply is never called as a filter.
3. SA still becomes `_sa()` only when it is `[-1]`. With S at `[-1]`, S is `_sa()`.
4. `_wrap_sa_result` (line 101-114) builds the winner Context from
   `$sa_result` (whatever `_sa()` returned). When `_sa()` is Structural, that
   result is an integer; the wrapped Context has `focus = integer` and no children.
5. SA's action methods never run. No IR is built. The parse "succeeds" only
   because Boolean and the other filters say so.

**Verdict:** SA-last is **structural correctness**, not performance. The memory
file's claim "the four filtering semirings commute, so their relative order is
a performance choice" is correct. The continuation "running [SA] last avoids
building IR nodes for branches the filtering semirings will kill" frames
SA-last as performance, but the more fundamental fact is that SA can only run
as `_sa()` because that is how `FilterComposite` decides where the focus comes
from. SA-not-last produces silent total IR loss.

The structural enforcement (`$semirings->[-1]`) is the actual mechanism. It is
correct. The documentation framing as "performance" is misleading.

**What SA running in non-last position actually does:**

If SA is placed in a filter slot, it does nothing observable — its multiply
is never invoked because `_annotation_semirings()` excludes it. Whatever
semiring is at `[-1]` is treated as "the SA" by the rest of FilterComposite.
The parse runs to completion using that semiring's output as the focus.

This means SA-not-last is silently degraded behavior: no error, no warning,
just no IR construction. A reordering bug here would be invisible in test
output until someone tries to use `extract()->some_method()` on the result.

**Suggested remediation shape (commentary):**

1. **Documentation:** update the memory file and `parsing-pipeline.md` to
   state explicitly that SA-last is structural correctness, not performance.
   The performance argument exists too, but it's secondary.
2. **Defensive coding:** `FilterComposite::new()` could assert that the last
   semiring's `slot_name()` returns `undef` (matching SA's contract). This
   would catch the silent-degradation bug at construction. (NOT proposed
   work; just shape.)
3. **Long-term:** the special status of "SA" inside FilterComposite is a code
   smell — there is implicit dispatch on which semiring is `_sa()` (line
   170-179, 181-184, 323-325). This could be made explicit by passing SA as a
   separate field to FilterComposite, rather than as `[-1]` of the array.

## Finding 3: TI output crosses the parser boundary

**Claim:** TI's output is not just a parser-internal annotation; it is consumed
by Actions.pm and other compiler-stage code, structurally similar to SA's IR.

**Code evidence:**

`lib/Chalk/Bootstrap/Perl/Actions.pm:1411`:

```perl
my $ti_ctx = Chalk::Bootstrap::Semiring::SemanticAction::current_type_context();
die "MethodDefinition: TI context unavailable for '$method_name_str'"
    unless defined $ti_ctx;
my $ti_focus = $ti_ctx->extract();
...
if (defined $ti_focus->{method_return_type}) {
    $return_type = $ti_focus->{method_return_type};
} else {
    $return_type = 'Void';
}
```

The MethodDefinition action method reads TI's `current_type_context` output
and uses TI's `method_return_type` slot to populate `MethodInfo->return_type`.
This is a **producer-consumer relationship that crosses the parser boundary**:
TI produces typed data, Actions.pm consumes it as authoritative for the IR's
return-type field.

`lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm:62, 318-329`:

```perl
my %_method_returns;  # method_name => return_type
...
$_method_returns{$method_name} = $body_type;
return {
    valid => true,
    ($method_name ? (method_name => $method_name) : ()),
    ($body_type ? (method_return_type => $body_type) : ()),
};
```

The `%_method_returns` hash is populated by the `MethodDefinition` action method.
The hash is class-level (`my %`), shared across all instances of TypeInferenceActions.
The audit-2 finding that "the registry is dead code from the consumer's
perspective" is technically correct (no `lookup_method_return` callers), but
the *focus-hash version* of the same data IS consumed by `Perl::Actions::MethodDefinition`.
The data path is: TI computes `method_return_type` → stores in TI focus hash →
FilterComposite threads as `$ti_ctx_wrapper` (FC line 172-178) → SA's
`set_type_context($ti_ctx_wrapper)` → action method reads via `current_type_context()`.

**Verdict:** Confirmed. TI is not "just a filter" architecturally. It produces
typed data that downstream compiler stages consume to build the IR. The
similarity to SA is:

- **SA** produces IR (Sea-of-Nodes graphs in cfg state, ConciseTree in focus).
- **TI** produces typed annotations (return types, item types, op text, call
  symbols) that some IR fields are populated from.

Both produce data the compiler stages consume. The difference is that SA's
output is the focus of the result Context (the explicit primary product of
the parse), while TI's output is buried in `annotations->{type}` and consumed
via a class-level `current_type_context` channel.

**Architectural implications:**

1. **TI is a hidden second producer.** The parsing pipeline doc describes a
   "5-layer semiring stack" where 4 layers are filters and 1 is the IR
   builder. The actual code has 4 producer layers (Boolean, Precedence,
   Structural, SA) and 1 producer-disguised-as-filter (TI). The memory file
   `semiring_ordering.md` calls TI a "filter," which doesn't match current
   reality.
2. **Decision 5 (flow-typing completion) is consistent with this finding.** If
   TI becomes a flow-typing engine, its output stops being an annotation slot
   and becomes a typed-node SSA graph. This is the natural conclusion of TI
   already being a producer.
3. **The "TypeInference contract migration" in Decision 4 should be re-scoped.**
   Decision 4 wraps TI's carriers in Contexts to honor `(Context, Context) →
   Context`. But TI's output is consumed externally via `current_type_context()`,
   not via the slot. Wrapping the slot value in a Context doesn't change the
   external consumer's API. The contract migration is cosmetic for TI's
   internal slot but doesn't address the boundary-crossing producer/consumer
   relationship.
4. **Bug 4's walker fix interacts with this.** The walker (`_get_item_types` etc.)
   reads `annotations->{type}` from intermediate nodes — internal to TI. The
   external consumer (`Perl::Actions::MethodDefinition`) reads the *final
   focus hash* of TI's output. These are two different consumers; Bug 4's fix
   touches the internal-walker consumer, not the external one.

## Finding 4: Inter-filter read/write dependencies

**Claim:** Filters depend on each other's annotation slots; "commutativity" is
conditional. The brief specifically mentioned Structural reading TI's `is_*_typed`
tags.

**Read/write graph (per semiring):**

| Semiring       | Writes slot | Reads slots                                                       |
|----------------|-------------|-------------------------------------------------------------------|
| Boolean        | `boolean`   | (only via Context.is_zero)                                        |
| Precedence     | `precedence`| `precedence` (own), `scan`, `complete`, `rule_name`, `alt_idx`   |
| TypeInference  | `type`      | `type` (own, via tree-walk on left), `scan`, `complete`, `rule_name`, `alt_idx`, `predicted` |
| Structural     | `structural`| `structural` (own), `scan`, `complete`, `rule_name`, `alt_idx`   |
| SemanticAction | `cfg`       | `cfg` (own), `complete`, `rule_name`. Externally, action methods read TI's data via `current_type_context()` |

**Evidence:**

For Structural (`Structural.pm`), all annotation reads are listed:

```
59:        # Context object: read from annotations->{structural}
61:            return $val->annotations()->{structural} // $fallback;
70:        # Scan event: right Context has annotations->{scan} = true.
73:                && $right->annotations()->{scan}) {
78:        # Complete event: right Context has annotations->{complete} = true.
81:                && $right->annotations()->{complete}) {
83:            my $rule_name = $right->annotations()->{rule_name};
84:            my $alt_idx   = $right->annotations()->{alt_idx};
```

**Structural reads only its own `structural` slot plus parser metadata. It does
NOT read `annotations->{type}` or any TI slot.** A `grep` for `is_.*_typed` or
`->{type}` in Structural.pm returns no results. **The brief's hypothesis was
incorrect.**

For Precedence: the same pattern. Reads only `precedence` plus `scan`, `complete`,
`rule_name`, `alt_idx`. No cross-slot reads.

For TI: reads its own `annotations->{type}` slot from the left Context (used
in keyword rejection at scan time, line 268). Reads tree-walked `annotations->{type}`
across descendants for `_get_call_symbol` etc. (lines 100-140). No cross-slot reads.

For SA: reads its own `annotations->{cfg}` plus `complete`, `rule_name`. Does
NOT read other semirings' annotation slots directly. The cross-semiring read
happens via `current_type_context()` — a separate channel routed through
FilterComposite (set at FC line 178, consumed in `Perl::Actions::MethodDefinition`).

**Probe results from filter-permutation matrix:**

Across all six permutations of `{P, T, S}` (with B first and A last), the
parse outcomes for the test corpus were identical. This is consistent with the
read/write graph above: there is no cross-slot dependency to break by reordering.

The only cross-semiring data flow is **TI → SA via `current_type_context`**.
This is an SA-time read of TI-time data; reordering filters around TI does not
break it because TI's output is set when TI's multiply runs, regardless of
position.

**Verdict:** Refuted as stated in the brief. The brief's hypothesis ("Structural
reads TI's `is_*_typed` tags") does not match current code. There is no
cross-slot read/write graph among the four filter semirings. The only
cross-semiring data flow is the TI → SA channel via `current_type_context()`,
and SA's read happens at action time, not at filter-comparison time.

**Severity:** Brief framing was a guess that didn't match reality. The
"filtering semirings commute" claim is correct *for filter ↔ filter swaps*.
What is not correct is the broader claim that order is purely performance —
the position-dependence shown in Finding 1 (TI as `_sa()` vs not) and the
SA-last requirement shown in Finding 2 are both real ordering constraints.

**Suggested remediation shape (commentary):**

1. **Update the memory file:** replace the broad "filtering semirings commute"
   with a more precise statement: "the four filter semirings commute pairwise
   when SA is `_sa()`. SA must be `_sa()` for IR to be built. TI's behavior
   depends on whether TI is `_sa()` or in `_annotation_semirings()`."
2. **No remediation needed in code:** there is no real read/write dependency
   graph to fix.
3. **Future work:** when adding a sixth semiring, the position-dependence
   constraints (Finding 1, Finding 2) need to be respected. The new semiring's
   position is otherwise free relative to the four existing filters.

## Finding 5: Side effects in semiring operations

**Claim:** Some semirings mutate state beyond their returned value (MOP,
NodeFactory, etc.). If SA mutates the MOP during multiply/add, then SA running
on a derivation that gets pruned leaks state into the long-lived MOP.

**Probe results per semiring:**

### Boolean

`zero/one/multiply/add` — no mutation of external state. Lazy singletons
(`$ZERO_CTX`, `$ONE_CTX`) initialized once. Pure.

### Precedence

`zero/one/multiply/add` — mutates `%_cache` (hash-cons cache). Clearable via
`reset_cache()`. The cache is keyed by intrinsic value (valid, level, assoc,
is_operator), so cache hits return the same canonical object. **Effectively
pure** — cache growth doesn't affect correctness.

### TypeInference

`zero/one/multiply/add` — mutates `%_ctx_cache` (hash-cons cache) and the
pre-cached scan Contexts (`$_scan_regex`, etc.). Clearable via `reset_cache()`.

But also: **`%_method_returns` is a class-level hash that is mutated by
TypeInferenceActions::MethodDefinition** (line 323). This is reset only via
`reset_method_registry()`, which is called from `TypeInference::reset_cache()`
(line 170). If a MethodDefinition action fires during a losing derivation,
the registry retains the result. **Latent leak across derivations** — but the
brief noted that nothing reads the registry externally, so this leak is
benign at runtime.

### Structural

`zero/one/multiply/add` — pure. Operates on integers; no caches. **Pure.**

### SemanticAction

This is where the side effects accumulate.

1. **MOP mutation via action methods** (`Chalk::Bootstrap::Perl::Actions`):
   - `ClassBlock` (line 1318-1364) calls `$mop->declare_class`,
     `$mop_class->declare_field`, `declare_method`, `declare_sub`,
     `declare_import`, `declare_adjust`.
   - `Program` (line 972-987) calls `$main->declare_import`, `$main->declare_sub`.
   - `UseDeclaration` previously called `declare_import` directly; commit
     `2b2de487` moved it inside `ClassBlock`/`Program` body iteration.
   - **Multi-firing observed.** Probe `/tmp/audit5-finding5d.pl` confirmed:
     `use strict; use warnings;` triggers `declare_import` THREE times for
     two imports. The dedupe in `declare_import` (`MOP/Class.pm:60-63`)
     rescues this. **`declare_field`, `declare_method`, `declare_sub`,
     `declare_adjust`, and `declare_class` do NOT have dedupe.** These can
     fire multiple times if Earley produces multiple derivations reaching
     ClassBlock's action.
   - Probed corpus did not reveal multi-firing on declare_field/method/sub.
     Likely because the corpus's class shapes are unambiguous at the
     ClassBlock level. Multi-firing on declare_import happens at the
     Program-level use-decl iteration where Earley sees Program ambiguity.

2. **NodeFactory state mutation:**
   - `make()` advances `$cfg_counter` for CFG ops (If, Proj, Region, Phi, Loop).
     Each call produces a new node with a unique id. **Counter is global.**
     If a CFG node is created during a losing derivation, the counter has
     advanced and the node is orphaned (it's not in `$node_cache`).
     **Latent: 10 NodeFactory.make calls observed for a simple class
     `class Foo { field $x; method m() { return $x + 1; } }`** — 9
     Constants, 1 Start. Constants are hash-consed; Start is not.
   - Constants are added to `$node_cache`. Even on losing derivations, the
     cache retains them. Subsequent matches return the cached object.
     **Effectively pure** — cache hits return identical refaddrs.
   - The `$node_cache` and `$cfg_counter` survive across the entire parse;
     they do NOT get reset between Earley-chart derivations. They are reset
     only via `reset_for_testing`.

3. **Class-level state in SemanticAction:**
   - `$_pending_cfg_update` (line 22): set by action methods via `update_cfg`,
     consumed in `_complete_sa` (line 271-275). Cleared at the end of
     `_complete_sa`. **Could leak across SA invocations if an action method
     calls `update_cfg` and an exception is thrown before `_complete_sa`
     clears it.** Not observed in probes; latent.
   - `$_current_instance` (line 26): set in `_complete_sa` (line 253),
     cleared at end (line 286). Same exception-safety concern.
   - `$_type_context` (line 31): set by `set_type_context` (line 158),
     cleared in `_complete_sa` (line 287). Same exception-safety concern.
   - `$_mop` (line 38): set by `set_mop` (line 151). **Class-level mutation
     via class method** — affects all SemanticAction instances.
   - `$_one_singleton` (line 34): cached singleton. **Invalidated when
     `set_mop` is called** (line 151). This is correct caching, but the
     singleton is shared across all semiring constructions in a process.
     If two FilterComposite instances are constructed in the same process
     with different MOPs, the second `set_mop` call invalidates the first
     instance's singleton.

4. **`on_merge` mutates the winner Context's annotations in place:**
   - `SemanticAction.pm:324, 345`: `$correct->annotations()->{cfg} = ...`
   - The winner Context is potentially hash-consed (shared across many
     derivations). Mutating its annotations affects every other derivation
     that references the same Context.
   - This is a **violation of immutability** as documented in
     `parsing-pipeline.md` ("hash-consed immutable trees").
   - Comment in `SemanticAction.pm:312-314`: "The `on_merge` hook addresses
     a specific Earley engine issue. When `add()` in FilterComposite selects
     the older of two competing chart items, any CFG state updates that
     occurred between the time the older item was created and the current
     position are lost." — so this is a known stale-value workaround, but
     the workaround itself violates immutability.

### FilterComposite

- `$_tie_log` instance field, mutated when `CHALK_COUNT_FILTER_TIES` env var is
  set. Clearable via `flush_tie_log()`. **Instrumentation only — no production
  effect.**
- Calls each semiring's `multiply`/`add`/`on_merge` — propagates side effects
  from those.

**Verdict per semiring:**

| Semiring | Pure? | Caches? | External mutations? | Severity |
|---|---|---|---|---|
| Boolean        | yes | no  | none | none |
| Precedence     | yes-with-cache | yes (`%_cache`) | none | none (cache benign) |
| TypeInference  | mostly | yes (`%_ctx_cache`, scan singletons) | `%_method_returns` (class-level) | low (registry has no external consumer) |
| Structural     | yes | no  | none | none |
| SemanticAction | NO  | yes (`%_ctx_cache`) | MOP, NodeFactory, multiple class-level fields, on_merge mutates winner | **HIGH** |

**Severity rollup:**

- **MOP multi-firing:** known and partially handled (`declare_import` has
  dedupe). `declare_field`, `declare_method`, `declare_sub`, `declare_adjust`,
  `declare_class` lack dedupe. The probed corpus did not trigger duplicates,
  but the latent risk exists for any input where Program/ClassBlock has
  multiple derivations (e.g., ambiguity that survives until SA add()).
- **NodeFactory cfg_counter:** advances on losing derivations. Each CFG node
  created is orphan if the derivation loses. Memory leak (small) but no
  correctness issue — orphan nodes are not referenced by the IR.
- **Constant hash-cons:** cache hits across derivations. Effectively pure;
  same Constant value always returns same object.
- **`on_merge` mutates shared Context:** real immutability violation. Comment
  acknowledges it is a workaround for a specific Earley issue.
- **TypeInference's `%_method_returns`:** class-level hash mutation; benign
  because the registry isn't externally consumed (per Audit 2's finding).
- **SemanticAction class-level state (`$_mop`, `$_pending_cfg_update`, etc.):**
  set via class methods, shared across instances. Exception safety would be
  improved with `local`-scoped lexicals, but no exception-related leak observed
  in probes.

**Suggested remediation shape (commentary):**

1. **Add dedupe to `declare_field`, `declare_method`, `declare_sub`,
   `declare_adjust`, `declare_class`.** Pattern from `declare_import` is
   already established. (NOT proposed work; just shape.)
2. **Document the multi-firing reality** in `parsing-pipeline.md` §9. The
   current doc treats SA as building IR; it doesn't acknowledge that SA
   actions are called multiple times per rule completion when Earley produces
   multiple derivations.
3. **Reset NodeFactory cfg_counter between parses** — currently only resets
   via `reset_for_testing`. A `reset_cache` method could be added.
4. **Re-evaluate `on_merge`'s Context mutation.** The fix could be: instead
   of mutating the winner's `annotations->{cfg}`, return a new Context with
   the merged cfg state. This requires changing `add()` to return a new
   Context, not the winner reference. But the immediate winner reference is
   what FilterComposite needs to compare against the inputs (refaddr-based
   first-wins detection in `_filter_compare`). So the fix is non-trivial.
5. **Bug 4's walker fix is unaffected by Finding 5.** Bug 4 is about TI's
   tree-walk producing the wrong item_types; the side-effect inventory
   doesn't change the walker's behavior.

## Additional findings

Three new findings surfaced during this audit beyond the original five.

### Additional finding A: SA's class-level state isn't reset by `reset_cache()`

`SemanticAction::reset_cache()` (line 117-120) clears `%_ctx_cache` and
`$_one_singleton`. It does NOT clear `$_pending_cfg_update`, `$_current_instance`,
`$_type_context`, or `$_mop`. If a previous parse left state in these (e.g.,
an exception during `_complete_sa`), the next parse starts with stale state.

The audit found no actual cross-parse leak in probes (clean parses always
clear these in `_complete_sa`). But the class-level state is a latent concern.

### Additional finding B: NodeFactory's `instance` is a process singleton

`Chalk::Bootstrap::IR::NodeFactory.instance()` (line 54-57) returns a
process-singleton instance. State (`$node_cache`, `$cfg_counter`,
`$_new_factory`) is shared across all parses in the same process unless
`reset_for_testing` is called.

Test files explicitly call `reset_for_testing()`. Production code (e.g.,
`script/chalk-emit-son-json` if it parses multiple files) would share state
across parses unless it resets explicitly. This is process-level state
mutation that crosses parser boundaries.

### Additional finding C: `_annotation_semirings()` filters by `slot_name` truthiness, not by class

`FilterComposite._annotation_semirings()` (line 21-27) returns all semirings
that have a defined `slot_name`. SA's `slot_name` returns undef, so SA is
excluded. **But any other semiring with a `slot_name` returning undef would
ALSO be excluded.** This is implicit dispatch that depends on a contract
between FilterComposite and the semiring's `slot_name` method.

The dispatch is undocumented in the parsing-pipeline doc (which describes SA
as having no slot but doesn't explain that this exclusion is the mechanism).

If a future filter semiring's `slot_name` returned undef (perhaps because it
operates on the whole Context rather than a slot), it would be silently
excluded from filter dispatch. The same defensive coding suggested in Finding
2's remediation (asserting `_sa()->slot_name() == undef`) applies in reverse:
asserting that all `_annotation_semirings()` have non-undef `slot_name` would
make this contract explicit.

## Cross-finding synthesis

The five findings cluster around two architectural issues:

**Issue 1: FilterComposite's structural assumptions are not documented as
contract.**
- Finding 1: TI's behavior depends on whether it is `_sa()` (last) or in
  `_annotation_semirings()`. The `_sa()` returning `[-1]` is the structural
  enforcement; the documentation calls it convention.
- Finding 2: SA-last is correctness, not performance. Same `_sa()` mechanism.
- Additional finding C: `slot_name == undef` is the dispatch criterion for
  exclusion from `_annotation_semirings()`; not documented as contract.

These three findings together describe an under-specified semiring/composite
contract. The fix is documentation: write down the rules. The semantic content
of the rules is already correct; the docs are wrong.

**Issue 2: SemanticAction has effects that survive losing derivations.**
- Finding 5: MOP mutation, NodeFactory state, class-level fields, on_merge
  in-place mutation.
- Additional finding A: `reset_cache` doesn't clear all class-level state.
- Additional finding B: NodeFactory is a process singleton.

These four findings together describe a leak class. The current corpus does
not exhibit visible bugs from these leaks (the multi-firing rescued by
declare_import dedupe is the most concrete instance), but the design pattern
("SA mutates external state during multiply") is fragile.

**Finding 3 (TI crosses the parser boundary)** is a third issue: TI is a
producer-disguised-as-filter. This is a documentation/architecture issue, not
a bug. Decision 5 (flow-typing) addresses it long-term.

**Finding 4 (inter-filter read/write graph) was a non-finding.** The brief
hypothesized cross-slot reads; the code doesn't have them. Worth noting as
"don't worry about this layer" rather than "this layer is broken."

**How findings interact:**
- Finding 1's mechanism (TI's tree-walker depending on annotation storage)
  is what enables Bug 4. Decision 5 (flow-typing) would dissolve both.
- Finding 5's `on_merge` mutation interacts with Finding 1's tree-walking:
  the walker reads `annotations->{cfg}` indirectly (via SA's CFG state). If
  `on_merge` mutates the cfg on a hash-consed Context, the walker may see
  the mutated state on a different parse path.
- Finding 2's correctness rule (SA-last) interacts with Decision 4 (contract
  strengthening): if all semirings honor `(Context, Context) → Context`, the
  "SA's slot_name returns undef" mechanism becomes the *only* difference
  between SA and the four filters. That's actually a good outcome — explicit,
  documented difference.

## Implications for prior decisions

### Decision 4 (strengthen the contract)

**Validated for Boolean/Precedence/Structural; partially invalidated for TypeInference.**

The contract `(Context, Context) → Context` strengthens the semiring layer's
self-description. For Boolean, Precedence, Structural, this is straightforward
wrapping work (per Audit 2's analysis).

For TypeInference, contract migration is *cosmetic* with respect to the
external consumer (`Perl::Actions::MethodDefinition` reads via
`current_type_context()`, not via the slot directly). Wrapping the slot value
in a Context doesn't change what the external consumer sees. The contract
migration for TI should be sequenced *after* Bug 4's walker fix, so that the
contract migration migrates correct code, not buggy code.

Decision 4's ordering (Structural last, hardest) still holds.

### Decision 5 (flow-typing à la TypeScript)

**Strongly validated.** Findings 1 and 3 both point at the same mechanism —
TI's data is producer-shaped, not filter-shaped. Flow-typing completion is
the architectural conclusion.

The audit's framing ("TypeInference is not just a filter") matches Decision
5's framing ("TypeInference is flow-typing à la TypeScript, not a misnamed
annotation layer"). Decision 5 is consistent with what the code wants to be.

The Bug 4 RCA's note that "Bug 4 may dissolve as a side effect of flow-typing
completion" extends naturally to Finding 1: TI's position-dependence dissolves
when TI's output is no longer stored in `annotations->{type}` slots.

### Bug 4 walker fix — should it land or remain paused?

**Recommendation: land it.**

Bug 4's walker fix (Shape 1, Option 1 in the RCA) is independent of every
other finding in this audit:
- It doesn't depend on Finding 1's documentation; it just patches a bug whose
  trigger Finding 1 explains.
- It doesn't depend on Finding 2; SA-last is unchanged.
- It doesn't depend on Finding 3; TI continues to produce typed data via the
  same channels.
- It doesn't depend on Finding 4; there are no inter-filter dependencies to
  break or fix.
- It doesn't depend on Finding 5; the side-effect inventory doesn't change.

The audit's caution about "patch the symptom" is valid in the context of
Decision 5 (flow-typing will replace `_complete_type` entirely). But:

1. Decision 5's timeline is multi-issue (MOP Phases 3a-3c, then Phase 5).
   Bug 4 affects 14+ files. Holding the fix delays unblocking
   `t/grammar-conformance.t` for those files.
2. Bug 4's fix is single-method scope (one tree-walk method). It does not
   introduce new infrastructure that would need to be ripped out during
   flow-typing completion.
3. The fix's acceptance criteria (per the RCA) include "no regression in
   passing files" — which means it does not introduce new architectural debt
   that interacts with Findings 1, 2, 3, or 5.

**The Bug 4 walker fix should be unblocked.**

The architectural fixes implied by this audit (documentation update for
Findings 1, 2, 4; potential dedupe in MOP for Finding 5; flow-typing
completion for Finding 3) are independent work streams. None of them block
the walker fix.

If the architectural fixes proceed *after* the walker fix:
- Documentation updates land first (cheap, no code).
- Bug 4 walker fix lands next (single-method scope).
- MOP dedupe lands as opportunistic fix (one method per declare_*).
- Decision 4 (contract) and Decision 5 (flow-typing) land per existing
  sequencing.

## Walkthrough of acceptance criteria

The brief's acceptance criteria:

1. **Each of the five findings is verified with at least one isolation probe.**
   - Met. Finding 1: per-stage probe with reordering. Finding 2: SA-position
     probe with focus inspection. Finding 3: text-based code analysis backed
     by reading the consumer site. Finding 4: code-graph analysis backed by
     filter-permutation matrix. Finding 5: monkey-patched declare_* counter +
     NodeFactory.make instrumentation.

2. **For Finding 1, TI position-dependence is mapped to specific code (file:line).**
   - Met. `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:20-27`
     (`_sa()` and `_annotation_semirings()`). Mechanism per
     `FilterComposite.pm:155-166` (slot-results gathering).

3. **For Finding 4, the inter-filter dependency graph is concrete (per-slot
   read/write per semiring).**
   - Met. Read/write table in Finding 4 §"Read/write graph" with code
     citations. Verdict: no cross-slot reads exist among the four filter
     semirings; the brief's hypothesis was incorrect.

4. **For Finding 5, the per-semiring side-effect inventory is concrete.**
   - Met. Per-semiring table at the end of Finding 5; lists pure semirings,
     hash-cons cache mutations, external state mutations, severity rollup.

5. **The audit explicitly states whether it changes the validity of Decisions
   4, 5, and the Bug 4 walker fix.**
   - Met. "Implications for prior decisions" section addresses each.

6. **Findings file committed to `worktree-pu` directly.**
   - To be done after writing this file.

7. **Walk through these acceptance criteria explicitly at the end.**
   - Done above.

## Cross-references

- Phase A.2 synthesis: `docs/plans/2026-04-25-phase-a2-synthesis.md`
- Audit 2 (semirings): `docs/plans/2026-04-25-audit-2-semirings-findings.md`
- Bug 4 RCA: `docs/plans/2026-04-25-bug-4-rca-and-remediation.md`
- Semiring contract drift: `docs/plans/2026-04-24-semiring-contract-drift.md`
- Semiring ordering memory: `~/.claude/projects/-home-perigrin-dev-chalk/memory/semiring_ordering.md`
- Parsing pipeline architecture: `docs/architecture/parsing-pipeline.md`
- TestPipeline: `t/bootstrap/lib/TestPipeline.pm`
- FilterComposite: `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm`
- TypeInference: `lib/Chalk/Bootstrap/Semiring/TypeInference.pm`
- SemanticAction: `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`
- TypeInferenceActions: `lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm`
- Perl Actions: `lib/Chalk/Bootstrap/Perl/Actions.pm`
- MOP: `lib/Chalk/MOP.pm`, `lib/Chalk/MOP/Class.pm`
- NodeFactory: `lib/Chalk/Bootstrap/IR/NodeFactory.pm`

End of findings.
