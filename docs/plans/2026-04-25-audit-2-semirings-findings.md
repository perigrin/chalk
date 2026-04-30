# Audit 2 — Semiring Findings

**Date:** 2026-04-25
**Companion to:** `docs/plans/2026-04-25-audit-2-semirings-brief.md`
**Status:** Read-only investigation. No code changes.

## Summary

- **Confirmed semiring filter bugs:** 3 (seed) + 0 (discovered);
  but 2 of 3 seed-bug *triggers* were misidentified in the brief
  and are corrected here.
- **Contract violations confirmed:** 3 violations + 1 partial (zero
  only) + 2 honoring (Boolean, FilterComposite). All values empirically
  inspected via `zero()`/`one()`/`multiply(one,one)` calls.
- **Ambiguity-class ownership outcomes:** 7 of 7 canonical examples
  in `ambiguity-classes.md` pass without their claimed-owner semiring
  in the stack. This does not falsify ownership — it shows the
  canonical inputs do not exercise the ambiguity at the grammar
  level.
- **TypeInference completeness gaps:** Rich (15+) tag set, mostly
  consumed; one tag (`method_return_type` registry) populated but
  never read.

## Methodology

Per-stage stack discriminator built from `t/bootstrap/lib/TestPipeline.pm:135-163`:
construct FilterComposite parsers with progressively more semirings
([B], [B,P], [B,P,T], [B,P,T,S], [B,P,T,S,A]) and find the FIRST
stack where the input transitions from PASS → FAIL. SemanticAction
is always last so the semiring construction satisfies FilterComposite's
`_sa()` contract.

Probes saved to `/tmp/audit2-*.pl` during execution; not committed.

## Confirmed semiring filter bugs

### Bug 1: Block-form builtin with parenthesized literal LIST argument

**Brief's claim:** Ternary expression as BLOCK of block-form builtin
is rejected (e.g., `map { defined $_ ? $_ : 0 } (1, 2, 3)`).

**Audit's correction:** The ternary is a red herring. The actual
trigger is **the parenthesized literal LIST argument**. Rejection
fires whenever `map`/`grep`/`sort`'s LIST argument is a parenthesized
literal whose inferred per-position types are not `List`-compatible.

**Minimal failing case:**

```perl
my @x = map { $_ } (1, 2, 3);    # FAILS
my @x = map { $_ } @arr;         # PASSES
```

**Per-stage rejection:**

| Stack | Result |
|---|---|
| [Boolean] | PASS |
| [Boolean, Precedence] | PASS |
| [Boolean, Precedence, TypeInference] | **FAIL** |
| [Boolean, Precedence, TypeInference, Structural] | FAIL |
| [Boolean, Precedence, TypeInference, Structural, SA] | FAIL |

**Rejecting semiring:** TypeInference.

**Code path of rejection:**
- `lib/Chalk/Bootstrap/Semiring/TypeInference.pm:340-365` —
  `CallExpression` branch of `_complete_type`.
- `_get_item_types` (line 346) walks the shared Context tree to
  recover per-position types from `ExpressionList`; for `(1, 2, 3)`,
  these are `[Int, Int, Int]`.
- The signature lookup (`_lookup_builtin('map')`,
  `lib/Chalk/Grammar/Perl/TypeLibrary.pm:141`) returns
  `arg_types => ['Code', 'List']`.
- Block-form builtins with `alt_idx == 2 || alt_idx == 3` get
  `sig_offset = 1` (line 349). For position 0 of `(1, 2, 3)`, the
  expected type is `arg_types[0+1] = 'List'`, then
  `arg_types[-1] = 'List'` for positions 1+ (line 354 fallback).
- `Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Int', 'List')`
  returns false (Int is not a subtype of List, and Int is not in
  `%POLYMORPHIC_TYPES`).
- TypeInference's `_complete_type` returns `undef` (line 356), which
  FilterComposite reads as zero (line 158), short-circuiting the
  multiply.

**Why `@arr` works:** `@arr` (ArrayVariable) gets type `Array` at
scan time (`TypeInference.pm:423`). `is_subtype('Array', 'List')`
is true (Array is a subtype of List in TypeLibrary's hierarchy).
Per-position type is `Array` → satisfies `List`.

**Why `(1, 2, 3)` fails:** ExpressionList tracks per-position types
explicitly. The parenthesized list of integers gets `item_types =
[Int, Int, Int]`. Each Int fails the List subtype check.

**Why this is incorrect behavior:** Perl's evaluation context
flattens lists; `map { ... } (1, 2, 3)` is exactly equivalent to
`map { ... } 1, 2, 3` in the runtime. The TypeInference signature
asks "is this whole position a List?" but per-position type
tracking returns the *element* type, not the list type. The check
is asking the wrong question.

**Suggested remediation shape (NOT proposed work, just shape):**
The signature contract for variadic LIST positions should be
satisfied either by an aggregate-typed argument (Array, Hash, List)
*or* by per-position scalar values that are subtypes of the element
type. The fix is in either `type_satisfies` (treat List as the
union of List and any sequence of Scalars) or in `_complete_type`
(detect variadic LIST and accept per-position scalars).

**Cross-effect on other patterns:**
- Affects ALL block-form builtin invocations whose LIST argument
  is a parenthesized literal list. Given that `lib/` heavily uses
  `map { ... } @ref->@*` rather than `map { ... } (1, 2, 3)`, the
  count of *real* affected files is much smaller than the brief
  suggested. The brief's "12-15 files" estimate was attributed to
  "the dominant pattern in the IR metadata cluster" — those files
  pass the per-stage probe (`map BLOCK $ref->@*` → BOTH PASS in
  `/tmp/pattern-a-probe.pl` lines A1-A5), so the failure mechanism
  for that cluster is something else, not Bug 1.

### Bug 2: Block-form builtin with `=>` in BLOCK

**Brief's claim:** `qw(...)` as LIST argument to block-form builtin
is rejected.

**Audit's correction:** `qw` is incidental. The actual trigger is
**`=>` inside the BLOCK** of the block-form builtin. The same
pattern fails with bare lists, with array variables, with single-
or multi-line `qw`, and with literal commas.

**Minimal failing cases:**

```perl
my %h = map { $_ => 1 } qw(a b c);    # FAILS (qw)
my %h = map { $_ => 1 } @arr;         # FAILS (array var)
my %h = map { $_ => 1 } ("a", "b");   # FAILS (paren list — also Bug 1!)
my %h = map { $_, 1 } @arr;           # FAILS (comma instead of fat arrow)
my %h = map { ($_, 1) } @arr;         # FAILS (paren-wrapped pair)
```

**Per-stage rejection:**

| Stack | Result |
|---|---|
| [Boolean] | PASS |
| [Boolean, Precedence] | PASS |
| [Boolean, Precedence, TypeInference] | **FAIL** |

**Rejecting semiring:** TypeInference.

**Code path of rejection:**
- `lib/Chalk/Bootstrap/Semiring/TypeInference.pm:340-364` again —
  `CallExpression` branch.
- The BLOCK in `map { $_ => 1 }` produces a 2-element list (`$_,
  1`) at runtime, but the parser sees `Block` containing
  `ExpressionList(alt 2)` (fat arrow form) with `list_arity = 2`.
  The `Block` action (`TypeInferenceActions.pm:210`) does not
  preserve `list_arity` in its returned focus hash — only `type`
  is propagated. So the BLOCK position's type to the outer
  CallExpression is whatever `_get_rightmost_type` returns from
  inside the block (in this case `Int` from the `1`, possibly).
- Meanwhile the outer CallExpression's `_get_item_types` walks
  the Context tree from the leftmost ExpressionList (the
  CallExpression's arg list) which contains the Block plus the
  trailing `qw(a b c)` / `@arr` / etc. Per-position types are
  computed for the block-form invocation.
- For block-form builtins (alt_idx 2/3), the type-checker uses
  sig_offset=1, so position 0 (the BLOCK) is checked against
  `arg_types[1] = 'List'` (the `map`'s second signature slot, which
  is `List`).
- The Block returns type `Int` (or another scalar) which is not a
  List subtype. Reject.

**Why `map { $_ } @arr` works but `map { $_ => 1 } @arr` fails:**
Without fat-arrow inside the block, the inner ExpressionList is
alt 0 (single Expression), which doesn't trigger the type-aggregation
path that produces the wrong type. With fat-arrow, the inner
ExpressionList is alt 2 (fat-arrow pair), and the block's outermost
expression has type `Int` (from `1` on the right side of `=>`).

**Why this is incorrect behavior:** The BLOCK's runtime semantics
are "evaluate this in list context and produce the elements." The
type system should treat block-form builtin arguments as Code
returning List, not as a plain expression whose return type is
checked against the LIST type signature slot. The
`{ $_ => 1 }` case in particular shows the type-inference engine
isn't modeling Perl's block-as-callback semantics.

**Suggested remediation shape:** TypeInference should treat the
BLOCK position of `map`/`grep`/`sort` as a `Code` return — checking
whether the block's body would produce a List in list context — or
simply accept any block at that position (defer the check, since
the runtime produces a flat list regardless).

**Cross-effect:** Bug 1 and Bug 2 are the same root cause — both
are TypeInference's `CallExpression` branch incorrectly applying
per-position type checking to block-form builtins. Bug 1 is
"argument doesn't satisfy the LIST slot when it's a literal list."
Bug 2 is "block doesn't satisfy the LIST slot when its inferred
return type isn't List." Same `type_satisfies` call site
(`TypeInference.pm:355`); different upstream type-inference
quirks.

### Bug 3: Two AssignmentExpressions in `for` header

**Brief's claim:** Postfix dereference in implicit numeric context
(`for (...; $i < $arr->@*; ...)`) is rejected.

**Audit's correction:** Postfix dereference is incidental. The
actual trigger is **two AssignmentExpressions in the C-style `for`
header** — one in position 1 (`my $i = 0`) and one in position 3
(`$i += 2`). With either alone, parse passes. With both, parse
fails at Precedence.

**Minimal failing cases:**

```perl
# All FAIL
for (my $i = 0; 1; $i += 2) { last; }
for (my $i = 0; $i < $arr->@*; $i += 2) { last; }
for (my $i = 0; 1; 1) { ... }            # actually PASSES — see note
for (my $i = 0, my $j = 0; 1; $i += 2) { last; }

# All PASS
for (my $i = 0; 1; $i++) { last; }       # ++ instead of +=
for ($i; 1; $i += 2) { last; }            # no my
for (my $i = 0; 1; 1) { last; }           # third expr is literal — wait, this FAILS too
for (my $i = 0; 1; $i = 0) { last; }      # bare = passes
```

Probe corrected: re-running confirms `for (my $i = 0; 1; 1)` PASSES
in isolation but the trigger for `+=` specifically remains `my $i = 0; ...; $i += 2`.

**Per-stage rejection:**

| Stack | Result |
|---|---|
| [Boolean] | PASS |
| [Boolean, Precedence] | **FAIL** |

**Rejecting semiring:** Precedence.

**Code path of rejection (hypothesis based on code reading,
NOT confirmed via instrumentation):**
- `lib/Chalk/Bootstrap/Semiring/Precedence.pm:170-186` —
  `_scan_multiply` for `AssignOp` operators.
- The check at line 180 rejects same-level left operands for
  right-associative operators: "`(my $x = $y) //= 1` is invalid
  because the left operand is an AssignmentExpression (level=101,
  right-assoc)."
- A C-style `for` header has three semicolon-separated expressions.
  The grammar likely produces all three as `AssignmentExpression`
  alternates. The accumulated Precedence value going into the third
  expression appears to carry forward the level=101 from the first
  expression (`my $i = 0`), and when `+=` (an AssignOp) scans, it
  sees `existing->{level} == 101 == op_level` and rejects per the
  right-associative same-level rule.
- Why `=` (alone) and `++` work: `=` ends up with the same level
  but the bare `=` doesn't seem to leave is_operator state in the
  same way. `++` is a PostfixIncDec, not an AssignOp, so doesn't
  go through `_scan_multiply`'s AssignOp branch.

**Why this is incorrect behavior:** A `for` header's three
expressions are syntactically and semantically independent — the
grammar should treat them as separate expression contexts. The
Precedence semiring's accumulated state should reset between the
three semicolon-separated parts. The current code resets state at
parenthesized boundaries (`ParenExpr` in `$RESETS` at line 68) but
the C-style `for` header is not a `ParenExpr` — it's a special
ForLoop construction with semicolons between expressions. The
state leaks across them.

**Suggested remediation shape:** The grammar's `ForLoopHeader`
rule (or equivalent) should reset Precedence state at each
semicolon boundary, or be added to Precedence's `$RESETS` set with
appropriate per-position handling. Alternatively, the Precedence
state for an enclosing BinaryExpression should not leak into the
following AssignmentExpression in the same parser context.

**Cross-effect:** Affects only C-style `for` headers with two
assignments (not the dominant pattern in `lib/`). Per the brief's
seed data, only 1 file affected: `lib/Chalk/Bootstrap/Perl/Target/C.pm:107`.
Audit confirms this is a narrow trigger.

### Addendum 2026-04-30: Bug 3 reframed post-RCA

The Bug 3 section above contains three incorrect claims, identified by the
RCA at `docs/plans/2026-04-29-bug-3-rca.md` and confirmed by instrumented
probes run against commit `89001c63`.

**Claim 1 (per-stage table) — wrong.** The table above shows `[Boolean,
Precedence]` as FAIL. Instrumentation (`/tmp/bug3-audit2-verify.pl`)
confirms `[Boolean, Precedence]` PASSES. The minimum failing combination is
`[Boolean, Precedence, TypeInference]` or `[Boolean, Precedence, Structural]`.
Bug 3 is a Category-C interaction bug: Precedence has a latent defect (see
below) that is only exposed when a second annotation semiring alters
chart-cell identity and reveals chart-complete multiply paths that `[B, P]`
alone never takes.

**Claim 2 (code path) — wrong.** The hypothesis above points to
`_scan_multiply` lines 170–186 (AssignOp same-level branch). Instrumented
tracing shows that branch does not fire on any of the Bug 3 inputs. The
rejection is in `_prec_multiply` (lines 305–308), reached via a
chart-complete multiply at `Earley.pm:1337`, not a scan-time multiply.

**Claim 3 (remediation shape) — wrong.** The suggested fix above recommends
adding `ForStatement` to `$RESETS`. The RCA rejects this: the rejection
occurs during an in-flight chart-complete multiply, not at `ForStatement`
completion; `$RESETS` fires on rule-completion and is therefore too late.
The actual defect is a dead-code bug in `_complete_prec`: the intended
`assoc='right'` clause at the old lines 414–417 (`if ($rule_name eq
'AssignmentExpression') { return _intern(..., 'right', ...) }`) was
unreachable because the `$EXPR_LEVELS` lookup above it matched first and
returned `assoc=undef`. With `assoc=undef`, `_prec_multiply` defaulted to
`'left'`, causing the same-level reject to misfire.

**Implemented fix (commit `25364037`):** `$EXPR_LEVELS` converted to a
`rule => [level, assoc]` table; `_complete_prec` returns the per-rule assoc;
the dead `AssignmentExpression` clause deleted. `TernaryExpression`
simultaneously corrected to `assoc='right'` (Perl's `?:` is right-assoc,
same latent shape). See `docs/plans/2026-04-29-bug-3-rca.md` for the full
root-cause analysis and probe results.

The original Bug 3 section is preserved as the historical audit record.

## Contract violations

Verified empirically by calling `zero()`, `one()`, and
`multiply(one, one)` on each semiring. Probe at
`/tmp/audit2-contract.pl`.

| Semiring | zero() | one() | multiply(o,o) | Honors `(Context,Context)→Context`? |
|---|---|---|---|---|
| Boolean | Context | Context | Context | **YES** |
| Precedence | HashRef | HashRef | HashRef | NO |
| TypeInference | undef | Context | Context | NO (zero violates) |
| Structural | -1 (int) | 0 (int) | 0 (int) | NO |
| SemanticAction | undef | Context | Context | NO (zero violates) |
| FilterComposite | Context | Context | Context | YES |

This matches the contract-drift document. Detail per violator:

### Violation 1: Precedence does not honor `(Context, Context) → Context`

**Documented contract:** `(Context, Context) → Context`
(`docs/plans/2026-04-12-unified-context-design.md` line 179).

**Actual signature:** `(slot_value | Context, slot_value | Context) → slot_value`,
where `slot_value` is a hash-consed hashref with shape
`{ valid, level, assoc, is_operator, op }`.

**FilterComposite compensation:** `_filter_compare` at
`FilterComposite.pm:213-218` extracts
`$left->annotations()->{precedence}` and the equivalent for right,
then calls `Precedence.add()` on the bare slot values. Precedence
also has its own `_slot_val` (`Precedence.pm:86-93`) to extract
the slot from a Context if one is passed at the multiply boundary.
This is bidirectional accommodation: FilterComposite unwraps for
add, Precedence unwraps for multiply.

**Cost of bringing into contract:** Medium. Precedence values are
hash-consed (~5 distinct shapes per parse) and used in tight inner
loops. Wrapping each in a Context would require either:
- A second hash-cons cache for the Context wrapper (Context-per-slot-value).
- Lazy unwrapping in compare paths (Context still cheap).
The harder issue is that the `add()` method tests `refaddr()` for
identity collapse; wrapping breaks current refaddr semantics.

### Violation 2: Structural does not honor `(Context, Context) → Context`

**Documented contract:** `(Context, Context) → Context`.

**Actual signature:** `(int | Context, int | Context) → int`,
where the integer is a 0-255 bitfield (or -1 sentinel for zero).

**FilterComposite compensation:** Same shape as Precedence —
`_filter_compare` extracts `annotations->{structural}` (an integer)
before calling `Structural.add()`. Structural has its own
`_slot_val` at `Structural.pm:57-64` for multiply-time unwrapping.

**Cost of bringing into contract:** Highest of the three. Structural
operates on integer bitwise OR in tight loops; every multiply is
two small integer reads and a single OR. Wrapping integers in
Contexts would 100x the allocation count and break the bitwise OR
shortcut. Practical fix: relax the contract per the contract-drift
doc's "Option 2" — accept that each semiring has its own carrier
type T and the contract is `(T, T) → T` per semiring.

### Violation 3: TypeInference has mixed return types

**Documented contract:** `(Context, Context) → Context`.

**Actual signature:** mixed:
- `zero()` returns `undef` (not a Context).
- `one()` returns a Context with `{ valid => true }` focus.
- `multiply()` returns:
  - `undef` (zero) when rejecting at scan or complete.
  - A hash-consed Context with two children (regular multiply tree).
  - **A bare hash ref** when right is scan-annotated or complete-annotated
    (lines 304, 313 — see `_type_tag_for_scan` and `_complete_type`,
    both return tag hashes, not Contexts).

**FilterComposite compensation:** Most special-cased of the three.
- `FilterComposite.multiply()` lines 154, 163-165: captures TI's
  result as `$ti_result_tag_hash` when complete-event, then wraps
  in a Context (lines 172-178) before threading to SemanticAction's
  `set_type_context()`. The bare hash from TI multiply gets stored
  as `annotations->{type}` for downstream consumers.
- `FilterComposite._filter_compare()` line 228: skips calling
  `add()` for the type slot entirely, comments that "TI never
  expresses a preference via add()" because TI's add returns a
  merged Context that equals neither input. Identity check at line
  221 is sufficient.
- `FilterComposite.one()` lines 70-77: special-cases the type slot
  to extract the focus from TI's Context-wrapped one(), so
  annotations->{type} holds a tag hash rather than a Context.

**Cost of bringing into contract:** High but achievable. Three
sub-cases:
1. Make `zero()` return a Context (small; matches Boolean/SA pattern).
2. Make `multiply()` consistently return Contexts (medium; touch
   ~10 return sites, change downstream FC compensation).
3. Decide whether tag hashes should be the carrier or the
   focus. Currently they're sometimes the focus of a Context,
   sometimes a bare hash. Reconciling this is the bulk of the work.

## Ambiguity-class ownership verification

Methodology: for each documented class, run the canonical example
through (a) full stack and (b) full stack minus the claimed-owner
semiring, with `CHALK_COUNT_FILTER_TIES=1` to count unresolved
ties. If owner removal produces ties or rejections, ownership is
load-bearing. If owner removal still passes with zero ties,
ownership is unverifiable from this input.

Probe at `/tmp/audit2-ambiguity-ablation.pl`. All seven classes
yielded the same outcome:

| Class | Documented owner | Stack with owner | Stack without owner | Mismatch? |
|---|---|---|---|---|
| 1: Precedence (`1 + 2 * 3`) | Precedence | PASS, 0 ties | PASS, 0 ties | unverifiable from input |
| 2: Keyword vs identifier (`class => "Foo"`) | TypeInference | PASS, 0 ties | PASS, 0 ties | unverifiable from input |
| 3: Block vs hash (`{ a => 1 }` RHS) | Structural | PASS, 0 ties | PASS, 0 ties | unverifiable from input |
| 4: Slash as division/regex (`1 / 2`) | TypeInference | PASS, 0 ties | PASS, 0 ties | unverifiable from input |
| 5: Named unary vs list op (`defined $x + 1`) | Precedence | PASS, 0 ties | PASS, 0 ties | unverifiable from input |
| 6: Unary vs binary minus (`3 - -$y`) | Precedence | PASS, 0 ties | PASS, 0 ties | unverifiable from input |
| 7: map BLOCK form (`map { } @arr`) | Structural | PASS, 0 ties | PASS, 0 ties | unverifiable from input |

**Interpretation:** The canonical examples in
`docs/architecture/ambiguity-classes.md` do *not* exercise the
ambiguity at the Boolean level — Boolean alone produces zero
ambiguity, so removal of the disambiguating semiring is not
observable. This does not mean the classes don't exist or that
the ownership claims are wrong. It means the canonical examples
in the docs are insufficient to verify ownership empirically.

To verify ownership, the audit would need either (a) inputs that
Boolean alone produces multiple derivations for, or (b)
instrumentation that records *which* semiring rejected/preferred
in the chart, not just final pass/fail.

**Recommendation for `ambiguity-classes.md`:** add for each class
a *verification example* that produces ambiguity at Boolean alone,
so a future auditor can verify the claimed owner is the actual
resolver. Current examples show what each class is about, not
where the disambiguation happens.

## TypeInference completeness gap analysis

Inventory of type tags that TypeInference and TypeInferenceActions
read or write to `annotations->{type}` (a hash with these named
slots):

| Tag | Tracked by code? | Documented? | Used by | Gap |
|---|---|---|---|---|
| `valid` | yes (boolean marker on every focus hash) | implicit | TI internal | none |
| `type` | yes (Regex, Scalar, Array, Hash, Str, CodeRef, Num, Int, Undef, Bool, ArrayRef, HashRef, List, Code, plus Object) | yes (parsing-pipeline.md §6) | TI complete-time (signature checks); SA via `set_type_context` | none |
| `op_text` | yes (BinaryOp, UnaryExpression operator scans) | yes | TI Actions (BinaryExpression, UnaryExpression for result-type lookup) | none |
| `call_symbol` | yes (QualifiedIdentifier scan for known builtins) | yes | TI scan-time (% disambiguation), TI complete-time (CallExpression signature lookup), TI Actions (Atom, Expression for propagation) | none |
| `ident_text` | yes (any QualifiedIdentifier scan) | yes | TI Actions (MethodDefinition method name extraction) | none |
| `item_types` | yes (ExpressionList Action) | yes | TI complete-time (CallExpression per-position checks) | none |
| `list_arity` | yes (ExpressionList Action) | yes | TI complete-time (CallExpression min_arity check) | none |
| `eval_context` | yes (AssignmentExpression, ExpressionStatement) | partial (mentioned in TI docs but consumer unclear) | downstream consumer not located in TI; possibly SA Actions for evaluation context narrowing | **CODE-TRACKS-NOT-DOCUMENTED**: `eval_context` set but no consumer found in TI itself |
| `method_name` | yes (MethodDefinition Action) | no | populated to `_method_returns` registry | partial — see below |
| `method_return_type` | yes (MethodDefinition Action) | no | populated to `_method_returns` registry | **registry never read externally** |

**Specific gap discovered:** `_method_returns` registry at
`TypeInferenceActions.pm:62` is populated by every MethodDefinition
completion (line 323) and the `lookup_method_return` accessor
exists (line 351), but `ag` finds no caller of `lookup_method_return`
or `register_method_return` outside the file itself. So the
method-return-type tracking is dead code from the consumer's
perspective. Either:
- The registry was forward-looking infrastructure (consumer not
  yet implemented), or
- The consumer was removed/replaced and the producer remained.

The brief's framing ("TypeInference may be a tag-checker labeled
type-inference") is partially correct: TypeInference does maintain
a real type system (TypeLibrary with 20+ types, subtype checking,
polymorphic types, builtin signatures, operator signatures). It
performs scan-time keyword rejection, complete-time signature
validation with arity and per-position checks, and propagates
types through wrapper rules. That's more than tag-checking.

But it has architectural gaps:
1. No type *inference* in the Hindley-Milner sense — types are
   declared at scans and propagated, not unified across positions.
2. The method-return-type registry is unused; methods aren't
   actually contributing to caller-side type inference.
3. Block-form builtin signature checking has the bugs documented
   in Bug 1 and Bug 2 — type signatures don't model Perl's list-
   flattening semantics correctly.
4. `eval_context` produced but no documented consumer; possibly
   waiting for a consumer that doesn't exist.

The implementation is closer to "type-checked annotation" than
either "tag-checker" or "type-inference engine."

## Cross-references

- **Audit 1 inputs:** Bug 1 and Bug 2 are TypeInference bugs and
  belong to Audit 2's punch list, not grammar. Bug 3 is
  Precedence-specific and likely needs grammar attention to mark
  C-style `for` header as a precedence-resetting boundary, so
  there's some grammar/semiring overlap there.
- **Audit 3 inputs:** Audit 2 surfaces no MOP/IR concerns beyond
  what the audit-plan already named. The dead-code
  `_method_returns` registry might point to MOP work (consumer
  could be SA Actions reading method types), but that's
  speculative.
- **`ambiguity-classes.md` updates needed:** add per-class
  verification examples that produce Boolean-level ambiguity,
  so ownership claims are empirically falsifiable. Update Class 7
  documentation: the canonical examples don't exercise the
  Block-vs-Hash ambiguity (Boolean accepts only one parse), so the
  Structural ownership claim is currently unverifiable from the
  doc's examples.
- **`semiring-contract-drift.md` updates needed:** the empirical
  inspection of `zero()`/`one()`/`multiply()` matches the doc's
  table exactly. No update needed; the doc is accurate.

## Walkthrough of acceptance criteria

The brief's six acceptance criteria:

1. **All three seed bugs have a confirmed rejecting semiring named
   with code-path evidence.**
   - Met. Bug 1 → TypeInference (`TypeInference.pm:340-365`),
     Bug 2 → TypeInference (same site), Bug 3 → Precedence
     (`Precedence.pm:170-186`, hypothesis from code reading not
     instrumented confirmation). The audit also corrected the
     stated triggers for Bug 1 (parenthesized list, not ternary)
     and Bug 3 (two AssignmentExpressions in `for` header, not
     postfix-deref-in-numeric-context).

2. **Three contract violations from the seed doc each have
   return-type inventory and FilterComposite compensation analysis.**
   - Met. Empirical inspection table matches the seed doc;
     FilterComposite compensation paths cited at exact line
     numbers.

3. **All nine documented ambiguity classes have ownership
   verification probes recorded.**
   - Partially met. The doc's classes 8 and 9 are explicitly
     "excluded by restriction" rather than handled by a semiring,
     so seven classes were probed. All seven probes recorded;
     all yielded the unverifiable-from-this-input outcome.
     A real verification harness would need richer probes than
     what the brief specified.

4. **TypeInference completeness gap analysis is at least
   surface-level complete.**
   - Met. Inventory of all type tags with code-tracks/documented/
     consumed status; one specific gap (dead-code registry) named.

5. **Findings file committed to `worktree-pu` directly.**
   - Will be done at the end of this session.

6. **Subagent reports: punch list summary with rejecting semiring
   per bug. No claims of "fixed."**
   - Met. Punch list at top; nothing claims to be fixed; the audit
     stayed read-only.

## Punch list (pure summary, no opinions)

1. **TypeInference signature check incorrectly rejects parenthesized
   literal lists as block-form-builtin LIST argument.** Site:
   `TypeInference.pm:340-365`. Affected pattern: `map/grep/sort
   { BLOCK } (literal, list)`. Audit's seed-bug count is reduced
   from 3 to 2 distinct root causes (Bug 1 and Bug 2 share the
   same site).

2. **TypeInference signature check incorrectly rejects block-form-
   builtin BLOCK whose return type isn't List.** Same site. Pattern:
   `map { $_ => 1 } LIST`, `map { ($_, 1) } LIST`, etc. Same
   `type_satisfies` mis-modeling.

3. **Precedence rejects two AssignmentExpressions in a C-style for
   header.** Site (hypothesis): `Precedence.pm:170-186`. Pattern:
   `for (my $x = 0; ...; $x += 2)`. State leaks across the three
   semicolon-separated for-header expressions.

4. **Three semirings violate the documented `(Context, Context)
   → Context` contract.** Precedence, Structural, TypeInference.
   FilterComposite compensates via `_slot_val` helpers and
   special-case branches. SemanticAction's `zero()` also violates
   (returns undef).

5. **Ambiguity-class doc examples are insufficient for ownership
   verification.** Canonical examples in
   `docs/architecture/ambiguity-classes.md` do not exercise
   ambiguity at Boolean alone, so removing the claimed-owner
   semiring still passes with zero ties.

6. **TypeInference's `_method_returns` registry has a producer but
   no consumer.** Site:
   `TypeInferenceActions.pm:62, 323, 348, 352`. Either dead code
   or forward-looking infrastructure with the consumer missing.

7. **TypeInference `eval_context` tag set on AssignmentExpression
   and ExpressionStatement but no documented consumer in TI itself.**
   Possibly consumed by SA Actions for context-narrowing; if so,
   should be documented as a TI→SA contract.

## Addendum: IR-cluster rejection pattern (2026-04-25 follow-up probe)

The main audit explicitly noted (line 119) that the IR-metadata cluster's
failure mechanism is *not* Bug 1 — `map BLOCK $ref->@*` passes BOTH stages
in `/tmp/pattern-a-probe.pl`. This addendum identifies the actual mechanism
via per-stage stack discrimination on the IR-cluster files.

**Methodology summary.** Built FilterComposite parsers with all 2^4 subsets
of {Precedence, TypeInference, Structural, SemanticAction} (Boolean is
unconditional; SA-last is enforced when present). Ran each subset against
canonical IR-cluster files (`MethodInfo.pm`, `SubInfo.pm`, `UseInfo.pm`)
and against synthesised minimal cases. The first subset where the input
transitions PASS → FAIL identifies the rejection mechanism.

Probe scripts: `/tmp/audit2-followup-stage.pl`,
`/tmp/audit2-followup-localize.pl`, `/tmp/audit2-followup-isolate.pl`,
`/tmp/audit2-followup-defined.pl`, `/tmp/audit2-followup-stage2.pl`,
`/tmp/audit2-followup-combo.pl`, `/tmp/audit2-followup-bt.pl`,
`/tmp/audit2-followup-narrow.pl`, `/tmp/audit2-followup-isa.pl`,
`/tmp/audit2-followup-cross.pl`, `/tmp/audit2-followup-final.pl`,
`/tmp/audit2-followup-bisect-block.pl`. Deleted at end of session.

### Bug 4: Named-unary / list-op builtin in `map`/`grep`/`sort` BLOCK rejected only when both TypeInference and SemanticAction are present

**Trigger / minimal failing case:**

```perl
my @arr;
my @x = map { defined $_ } @arr;     # FAILS at full stack
my @x = map { $_ } @arr;             # PASSES
```

**Per-stage discrimination on `lib/Chalk/IR/MethodInfo.pm`:**

| Stack | Result |
|---|---|
| [Boolean] | PASS |
| [Boolean, Precedence] | PASS |
| [Boolean, Precedence, TypeInference] | PASS |
| [Boolean, Precedence, TypeInference, Structural] | PASS |
| [Boolean, Precedence, TypeInference, Structural, SemanticAction] | **FAIL** |

`SubInfo.pm` and `UseInfo.pm` show the identical PASS-PASS-PASS-PASS-FAIL
shape. SA-last is the failing addition.

**Subset bisection on the minimal case** (`/tmp/audit2-followup-combo.pl`):

| Stack | Result |
|---|---|
| [B] | PASS |
| [B, A] | PASS |
| [B, P, A] | PASS |
| [B, T, A] | **FAIL** |
| [B, S, A] | PASS |
| [B, P, T, A] | FAIL |
| [B, P, S, A] | PASS |
| [B, T, S, A] | FAIL |
| [B, P, T, S, A] | FAIL |

Cross-confirmed with `[B, T]` alone (`/tmp/audit2-followup-bt.pl`) — passes.

**Rejecting semiring (single-name claim is wrong here): the rejection is an
*interaction* between TypeInference's annotations and SemanticAction's
action dispatch.** TI alone does not return zero from `multiply` — `[B, T]`
parses cleanly. SA alone does not reject — `[B, A]` parses cleanly. The
rejection arises only when both are in the stack.

**Site count:** Bug 4 affects every IR-cluster file confirmed-failing
in `t/grammar-conformance.t`, plus additional files outside the cluster
that use the same pattern. Whole-file probes confirm:

- `lib/Chalk/IR/MethodInfo.pm` — FAIL (one trigger site, in `id()`).
- `lib/Chalk/IR/SubInfo.pm` — FAIL. Stripping `defined` from `id()` makes
  it parse (`/tmp/audit2-followup-cross.pl`), confirming `defined` is the
  trigger.
- `lib/Chalk/IR/UseInfo.pm` — FAIL.
- `lib/Chalk/IR/FieldInfo.pm` — FAIL. Has multiple trigger sites in `id()`
  (nested map with `ref`, `join`, `keys`); stripping just `defined` is
  insufficient to make it parse, but stubbing the entire `id()` body does.
- `lib/Chalk/IR/Node.pm` — FAIL.
- `lib/Chalk/Bootstrap/IR/NodeFactory.pm` — FAIL.
- `lib/Chalk/Bootstrap/BNF/Target/XS/AST/XSUB.pm` — FAIL.
- `lib/Chalk/Grammar/Rule.pm` — has the pattern, expected FAIL (probe
  not run individually but pattern matches).

Files outside the IR cluster that share the pattern:
`lib/Chalk/Bootstrap/Perl/Actions.pm`, `lib/Chalk/Bootstrap/Earley.pm`,
`lib/Chalk/Bootstrap/Optimizer/DCE.pm`, `lib/Chalk/Bootstrap/DepChaser.pm`
(skipped per audit policy),
`lib/Chalk/Bootstrap/Perl/Target/ClassRegistry.pm`,
`lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm`,
`lib/Chalk/Bootstrap/Perl/Target/Perl.pm`,
`lib/Chalk/Bootstrap/Semiring/FilterComposite.pm`,
`lib/Chalk/IR/Serialize/JSON.pm`. Some of these may have additional
unrelated bugs that mask Bug 4 in the conformance corpus.

**Trigger-builtin classification** (`/tmp/audit2-followup-isa.pl`): not
every builtin in a `map`/`grep`/`sort` BLOCK triggers Bug 4. Behaviour by
builtin:

- **Trigger (FAIL)**: `warn`, `print`, `say`, `push`, `defined`, `ref`,
  `length`, `uc`, `lc`, `scalar`, `chr`, `ord`, `exists`, `delete`,
  `join`, `split`, `substr`, `index`, `sprintf`, `bless`, `chomp`, `chop`.
- **No trigger (PASS)**: `return`, `die`, `pop`, `shift`, `keys`,
  `values`, `each`, `sort`, `reverse`, `local`. (`isa` is an operator,
  not a builtin, also passes.)

The split correlates roughly but not exactly with TypeLibrary signatures
(see `lib/Chalk/Grammar/Perl/TypeLibrary.pm:90-145`). `pop`/`shift` (which
take Array) pass; `delete` (which takes Scalar) fails. `return` (return_type
'Any', and listed in KEYWORD_RULES as a dedicated rule) passes; `defined`
(return_type 'Bool', not in KEYWORD_RULES) fails. The classification
likely tracks which builtins reach `_complete_type`'s CallExpression
branch with a tagged call_symbol and which take a code path that bypasses
it; full RCA was not pursued.

**Trigger context** (`/tmp/audit2-followup-narrow.pl`): the failure is
specific to the **Block-form CallExpression** (`Identifier WS Block WS
ExpressionList`, alt 3). Variants:

| Form | Result |
|---|---|
| `defined $_;` (top-level statement) | PASS |
| `defined $_` in `if` / `for` / `while` cond | PASS |
| `defined $_` in `do { ... }` block | PASS |
| `defined $_` as last expression in sub body | PASS |
| `map { defined $_ } @arr` | FAIL |
| `grep { defined $_ } @arr` | FAIL |
| `sort { defined $a } @arr` | FAIL |
| `map { sub { defined $_ }->() } @arr` (anon sub call) | FAIL |
| `my $f = sub { defined $_ }; map { $f->() } @arr` (sub var) | PASS |
| `map(sub { defined $_ }, @arr)` (paren-call form) | PASS |

The last two cases pinpoint the rule shape: it is `Identifier WS Block WS
ExpressionList` (alt 3 of `CallExpression`, see `docs/chalk-bootstrap.bnf`)
that breaks. Anonymous sub bodies inside this form still fail (the outer
shape, not the inner code, is the trigger). Routing the same code through
a different parse rule (assigned to a variable, or paren-call form) makes
it pass.

**Code path of rejection (hypothesis from code reading, not instrumented):**

The actual zero-return is from `FilterComposite::multiply` line 184:
`return $self->zero() if $self->_sa()->is_zero($sa_result);`. SA's
`_complete_sa` calls the action method for the rule (e.g. `Block`,
`CallExpression`, or `MapGrepExpression`) via `extend()`. A returned
`undef` from the action would propagate as zero.

What changes between `[B, T]` and `[B, T, A]`:
- `[B, T]`: TI annotations are computed and stored in the shared Context's
  `annotations->{type}`. No action methods run. `_filter_compare` skips
  TI (line 228), so TI's annotations don't directly disambiguate. With
  no other annotation semiring expressing a preference and no SA, the
  parse forest collapses to whichever derivation FC's tie-break selects
  (left-prefer in `_filter_compare`).
- `[B, T, A]`: TI annotations are computed *and* SA actions run. SA's
  `set_type_context($ti_ctx_wrapper)` (FC line 178) threads TI's tag
  hash into SA's per-action state. `ConciseTree::Actions` does not read
  `current_type_context` (verified by `ag` — no callers in Actions.pm),
  so the threaded context is unused. But the *action dispatch* itself
  may differ: with TI flagging certain alts as kept and others as zero
  via its multiply, the parse forest reaching SA contains different
  alternatives than `[B, A]` would see.

The concrete failure surfaces with diagnostic "parse failed at line N,
column C" pointing past the closing brace of the `map` BLOCK + LIST,
unable to accept the trailing `;`. Combined with the per-stage data,
this suggests SA's action for some inner rule (likely `CallExpression`
for the Block-form alt, or the implicit `Block`/`Statement` chain inside
the map BLOCK) fails to *complete* the rule — leaves the parse in a state
that can't transition to "end of expression."

A definitive RCA would require instrumenting SA's `_complete_sa` and
ConciseTree::Actions methods to log returns of `undef` per rule per
position, with TI annotations attached. That instrumentation was not
performed for this probe (out of scope — read-only).

**Suggested remediation shape (NOT proposed work, just shape):** Three
candidate directions:

1. SA-side: If a specific action in `ConciseTree::Actions` or
   `Chalk::Bootstrap::Perl::Actions` returns `undef` for the
   Block-form-CallExpression-with-builtin shape, audit those actions
   and ensure they handle the call_symbol-tagged path that TI creates.
2. FC-side: The `set_type_context` plumbing routes TI's tag hash to SA,
   but `ConciseTree::Actions` doesn't consume it. If the threaded context
   is causing side effects via some action's input handling, consider
   gating the threading on whether the active actions object actually
   reads it.
3. TI-side: TI's CallExpression complete-type may be tagging the outer
   `map {...} @arr` invocation in a way that the outer Statement/Block
   action then trips on. Specifically: when the BLOCK contains a builtin
   call that produces a typed result, the outer CallExpression's
   `_get_item_types` walk reads that type into the item_types array,
   which may then satisfy the `Code` slot incorrectly.

**Side effects:** Bug 4 explains the bulk of `t/grammar-conformance.t`
failures that the brief attributed to "Pattern A" (`map BLOCK $ref->@*`)
but Audit 2's per-stage probe ruled out — Pattern A passed, but the
*specific* shape `map { BUILTIN ... } LIST` is the actual trigger and
appears in ~9 of the same files. Site-count overlap with Bug 1 and
Bug 2 in the brief is partial: Bug 1 (paren-list LIST arg) and Bug 2
(`=>` in BLOCK) are independent triggers that this probe did not
re-check; they may also fire on the same files alongside Bug 4.

**Cross-effect on Audit 2's other bugs:**

- Bug 1 (paren-list as LIST): independent. Bug 4 fires regardless of LIST
  shape (verified with `@arr`, `$ref->@*`, `qw(a b c)` — all FAIL when
  BLOCK has a triggering builtin).
- Bug 2 (`=>` in BLOCK): independent but overlapping mechanism — both
  are TI's CallExpression complete-type interaction with the BLOCK
  position, but Bug 2 is about the BLOCK's *return type* not satisfying
  `List`, while Bug 4 is about TI's annotations causing SA to fail.
  Some IR-cluster files have both patterns.
- Bug 3 (two AssignmentExpressions in `for` header): fully independent;
  different rule, different semiring (Precedence).
- Contract violations (Sec. "Contract violations" of main findings): TI
  returns mixed types (Context vs. tag hash vs. undef). Bug 4 may be a
  surface-level symptom of TI's tag-hash-in-annotations design
  interacting with SA actions that expect Context-shaped inputs. The
  remediation work for the contract violations and for Bug 4 might
  share a root cause.

End of findings.

