# `_push_methodcall_inward.peel_builtin` investigation: not a guard problem

**Status:** Investigation 2026-05-12 night, after the `method_over_deref` fix
landed at commit `40ebf8ee`. No code changes attached; this is a findings doc.

## Question

`_fix_postfix_chain.method_over_deref` was retired today by gating the
`_push_deref_inward.peel_method` branch on whether the MethodCall's invocant
is itself a peelable wrapper. Two helpers in the same file were fighting each
other; the guard stopped one from corrupting input the other was undoing.

The next-highest-volume walker branch on Bootstrap-partial is
`_push_methodcall_inward.peel_builtin` at 51 fires. Same shape question:
does it have the same "two helpers fighting" structure, or is it doing
genuine filter-gap merge work?

## Test cases

Two source patterns produce IDENTICAL pre-helper IR shape:

  push @arr, $obj->method();    # bare-form push slurps method-call as arg
  push(@arr, $y)->method();     # paren-form push, then method-chain on result

Per perl (B::Concise):

  push @arr, $obj->method()  →  Call(push, [@arr, MethodCall($obj, method, [])])
  push(@arr, $y)->method()    →  MethodCall(Call(push, [@arr, $y]), method, [])

Both should parse cleanly to perlop-correct shapes.

In Chalk today (post-`40ebf8ee`):

  push @arr, $obj->method()  →  Call(push, [@arr, MethodCall($obj, method, [])])  ✓ correct
  push(@arr, $y)->method()    →  Call(push, [@arr, MethodCall($y, method, [])])    ✗ wrong

The bare-form case is correct only because `_push_methodcall_inward.peel_builtin`
fires and rewrites the wrong chart-merge derivation back to the perlop-correct
shape. The paren-form case is wrong because the SAME helper fires on input
that doesn't need rewriting and produces the wrong shape.

## Why this is harder than `method_over_deref`

For `_push_deref_inward.peel_method`, the helper had no legitimate case for
plain invocants. The guard `_method_invocant_needs_peel` (peel only when the
MethodCall's invocant is itself peelable) sufficed: `$obj->method()->@*`
correctly skipped the peel, `PostfixDeref(MethodCall(BuiltinCall(push, [...]),
m, []), @)` (filter-gap merge artifact) correctly took the peel.

For `_push_methodcall_inward.peel_builtin`, both source patterns produce
identical input shapes to the helper:

  Input: invocant = Call(push, [@arr, X]), method = "method", args = []

  - For `push @arr, $obj->method()`: this is the FILTER-GAP MERGE artifact.
    The wrong derivation B `MethodCall(Call(push, [@arr, $obj]), method, [])`
    won the chart, and the helper correctly rebuilds it as
    `Call(push, [@arr, MethodCall($obj, method, [])])`.
  - For `push(@arr, $y)->method()`: this is the LEGITIMATE chain. The
    paren-form push is the complete invocant; method-chain wraps it. The
    helper INCORRECTLY rebuilds it as `Call(push, [@arr, MethodCall($y,
    method, [])])`.

The IR shape is the same. The CALLER (PostfixExpression action) is the same.
The HELPER has no provenance information to distinguish.

## Why parser-level rejection alone doesn't help

Attempted: mark bare-form CallExpression (alts 1-3) with a precedence level
(`bare_call_level = 4.4`) so that MethodCall/Subscript/PostfixDeref scanning
`->`/`[`/`{` rejects it as a postfix target. PostfixExpression completion
exempts level=4.4 so a bare-form call is still a valid expression on its own.

Result on `push @arr, $obj->method()` (the bare-form case):

  push @arr, $obj->method();  →  TWO statements:
    Call(push, [@arr])
    Call($obj, method, [])

The push's second arg falls outside. The rejection is too broad.

**Why**: the rejection kills not just the wrong derivation B
(`MethodCall(Call(push, [@arr, $obj]), method, [])`) but also some derivation
path through which `$obj->method()` becomes push's second argument. The
ExpressionList's recursive comma-handling apparently relies on the
inner MethodCall completing through the same chart cells the rejection
touches.

The interaction between the bare-call rejection and ExpressionList comma
recursion is subtle. Without a deeper understanding of the chart structure
(read of `Earley.pm`'s chart-traversal logic), I can't predict which
derivation paths the rejection breaks.

This is structurally the same problem Class I (list-op slurping) ran into:
encoding a parser-greediness rule as a precedence-level marker breaks
adjacent legitimate parses.

## What's actually needed

Three real options, none cheap:

### Option A: provenance marker on Call nodes (paren-vs-bare)

Add a `paren_form` field to `Chalk::IR::Node::Call`. Set it from
CallExpression `alt_idx` (alt 0 = paren, alts 1-3 = bare). Use it in the
helper guard:

  if ($invocant isa Chalk::IR::Node::Call
          && $invocant->dispatch_kind() eq 'builtin'
          && !$invocant->paren_form()) {
      # Filter-gap merge case — peel
  } else {
      # Legitimate paren-form chain — don't peel
  }

Mechanical, narrow, doesn't risk Class-I-style chart breakage. Cost: every
Call node carries a permanent `paren_form` field for one specific helper's
benefit.

### Option B: grammar restructure (left-recursive PostfixChain)

Change the grammar so a bare-form CallExpression literally cannot be the
target of a postfix operator. Requires restructuring `MethodCall`,
`Subscript`, `PostfixDeref` to compose only with paren-form CallExpressions,
parenthesized expressions, atoms, and other postfix results.

Major surgery. The Earley parser admits both shapes today through the
`Expression _ /->/ ...` rules; restricting the LHS Expression to specific
shapes requires either splitting Expression into "postfix-targetable" and
"non-postfix-targetable" subsets, or using grammar mechanics we haven't
explored.

### Option C: fix the chart-merge artifact directly

The bare-form case has TWO derivations admitted in the chart:

  - A: Call(push, [@arr, MethodCall($obj, method, [])])  ← perlop-correct
  - B: MethodCall(Call(push, [@arr, $obj]), method, [])  ← wrong

The chart-merge picks B. Investigating WHY (which Earley step prefers B
over A) would let us fix it at the chart layer.

This is the same investigation `method_over_deref` initially appeared to
need, before the static analysis revealed the bug was in `_push_deref_inward`
all along. For `peel_builtin`, the bug genuinely IS at the chart level —
both derivations are admitted and the wrong one wins.

This is the open task #4 territory (FilterComposite tie-break bug). Multi-
session architectural work.

## Why the helper survives

After today's `method_over_deref` fix:

  Walker branch                              Was        Now    Status
  _fix_postfix_chain.subscript_over_builtin   827          0    retired (named-unary)
  _fix_postfix_chain.subscript_over_unary      96          0    retired (Class B unary)
  _fix_postfix_chain.method_over_deref         25          0    retired (this morning)
  _push_deref_inward.peel_method               11          0    retired (this morning)
  _push_methodcall_inward.peel_builtin         51         51    pending (this investigation)
  _push_deref_inward.peel_builtin              11         11    pending (similar shape)

The remaining branches are precisely the ones doing genuine filter-gap
merge work, where the parser admits two derivations and the wrong one wins.
Retiring them requires either fixing the parser (Options B/C) or threading
provenance through to the helper (Option A).

## Recommendation

Stop here. Pick the next direction in a fresh session, with the framing:

> "Filter-gap merge in chart-level disambiguation" is a separate
> architectural concern from "the precedence work" we just completed.
> Today's precedence fixes worked because the underlying ambiguity was
> a precedence question (operator binding priority). The remaining
> walker branches address ambiguities that are NOT precedence questions
> (parser greediness, chart-merge selection). Different category, different
> tools.

Tonight's session pushed deep enough to confirm the architectural diagnosis
without committing a regression. The branch state is clean at `40ebf8ee`.

## Cross-references

- Today's `method_over_deref` fix: commit `40ebf8ee`
- Class I post-mortem (same architectural family):
  `docs/plans/2026-05-12-list-operators-as-predeclared.md`
- Open task #4 (FilterComposite tie-break bug)
- The pattern of "two helpers fighting" was first identified in the
  `method_over_deref` investigation (this session); the analogous pattern
  applies but the fix doesn't transfer.
