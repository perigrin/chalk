# Scope-Hygiene Fix for Scoping Rules — Design v2 (SUPERSEDED)

> **SUPERSEDED 2026-05-26 by `2026-05-26-scope-control-divorce-design.md`.**
>
> This spec proposed a Block-action-level fix that publishes pre-Block
> bindings via `update_scope`. The reviewer's iteration-2 findings
> (Block accumulating workarounds; ElsifChain's "correct by accident"
> behavior) prompted a deeper architectural look: `Chalk::Bootstrap::Scope`
> bundles two unrelated concerns (variable bindings and control-chain
> head) that need different propagation rules. The successor design
> separates them at the Context level, which makes this v2 fix
> trivially correct as a downstream consequence (Commit 5 of the
> divorce design).
>
> Kept here for historical reference and to document the architectural
> evolution. Do not implement this spec directly.

---

# Scope-Hygiene Fix for Scoping Rules — Design v2

**Date:** 2026-05-26
**Status:** Design v2 — addresses spec-document-reviewer iteration 1 (Critical: original mechanism doesn't fire at the claimed site). Revised approach is action-level, not parser-level.
**Branch:** `fixup-audit-baseline` (continues from Phase 7d commits).

## Purpose

Replace the six `$ctx->scope`-via-leaf-walk workarounds in
`lib/Chalk/Bootstrap/Perl/Actions.pm` with a localized fix in the
`Block` action that sets its own post-rule scope explicitly.

Currently, when `IfStatement`'s action (and friends) reads
`$ctx->scope`, the scope reflects the post-Block scope — including
any `my`s declared inside the if-block. The actions work around this
by walking the multiply tree to find a leaf Context whose scope
predates the Block. Six known sites do this:

- IfStatement (Actions.pm:2548 + 2625)
- ElsifChain (Actions.pm:2741)
- WhileStatement (Actions.pm:2788 + 2834)
- ForStatement (Actions.pm:2935 + 2984)
- ForeachStatement (Actions.pm:~3128)
- TryCatchStatement (Actions.pm:1131) — reads `_ctx_scope($ctx)`
  directly, contaminated, but the action's logic apparently doesn't
  notice; investigate during implementation.

## Why the original design (v1) was wrong

v1 proposed marking `Block` rules as `is_scoping` on
`Chalk::Grammar::Rule`, then suppressing scope propagation in
`_mul_ctx` when a multiply child carried a complete event for a
scoping rule. The reviewer correctly identified that:

1. `multiply()` early-returns to `_complete_sa()` for complete
   events (SemanticAction.pm:262-266); `_mul_ctx` never sees the
   complete-annotated context.
2. After `_complete_sa` returns, the result Context no longer
   carries `annotations->{complete}`; subsequent `_mul_ctx` calls
   that combine the Block-result with later siblings see no flag
   to dispatch on.

The architectural fix is one level down: **Block's action is the
right place to set the post-Block scope**. Block knows that its
inner `my`s should not leak outward; it should write the pre-Block
scope to the result Context via `update_scope(...)`. Then
`_complete_sa`'s inherit-from-`$value` fallback (SemanticAction.pm:354-373)
sees a result-Context with explicit scope and leaves it alone.

The "scoping" concept stays inside the action that owns the
language-semantic decision. The parser machinery stays oblivious.
No grammar-level flag, no `_complete_sa` change, no `_mul_ctx`
change.

## What ships

Two commits on `fixup-audit-baseline`.

### Commit 1: `feat(actions): Block sets explicit post-rule scope`

**Files:**
- Modify `lib/Chalk/Bootstrap/Perl/Actions.pm` — Block action.
- Create `t/bootstrap/scope-hygiene-block.t` — unit test for the
  scope-leak invariant.

**Mechanism:**

Block's action walks its `$ctx` subtree to find the leftmost leaf
Context — that's the Context for whatever rule first multiplied
into Block's RHS accumulator (typically the opening `{` token).
That leaf's `scope` field is the scope as-of-when-Block-started-parsing.
Block's action stashes this and, just before returning, calls
`Chalk::Bootstrap::Semiring::SemanticAction->current_instance->update_scope($pre_block_scope)`.

```perl
# Pseudocode for the Block-action change:
method Block($ctx) {
    # ... existing logic that computes @stmts, $type, $graph, etc ...

    # Recover the scope as-of-Block-entry by walking to the
    # leftmost leaf of $ctx.
    my $pre_block_scope;
    {
        my $n = $ctx;
        while (defined $n && $n->children->@*) {
            $n = $n->children->[0];
        }
        $pre_block_scope = $n->scope if defined $n;
    }

    # ... existing logic that finalizes the Block IR ...

    # Suppress inner my-declarations from leaking to enclosing scope:
    # explicitly publish the pre-Block scope as Block's result.
    if (defined $pre_block_scope) {
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance;
        $sa->update_scope($pre_block_scope) if $sa;
    }

    return $block_ir_node;
}
```

**Why this works:**

The leftmost leaf of the multiply tree IS the first child multiplied
into the rule's RHS accumulator. For Block, that's the opening-brace
leaf — built BEFORE Block's StatementList was processed, so its scope
field still has the pre-Block value.

`_complete_sa`'s scope handling flow:
1. After Block's action returns, `_complete_sa` checks for a pending
   `update_scope` from the action (line 306). If set,
   `_complete_sa` rebuilds the result Context with `scope => $_pending_scope_update`.
2. The fallback "inherit from `$value` if result has no scope" branch
   (line 354) is skipped because scope IS now set.

Result: when `IfStatement`'s action subsequently runs (one level up),
`$ctx->scope` is the pre-Block scope. The cond_leaf workarounds become
unnecessary. The same holds for WhileStatement, ForStatement,
ForeachStatement, TryCatchStatement, ElsifChain.

**Tests:**

`t/bootstrap/scope-hygiene-block.t`:
- Parse `class A { method m($self) { if (1) { my $x = 2; } return $x; } }`.
- Assert: the IR for `return $x` references an UNRESOLVED $x (Phi
  or sentinel), NOT the `my $x = 2` VarDecl. (Block's scope hygiene
  is what prevents the leak.) The exact assertion depends on what
  the resolver produces when $x is not in scope; the test should
  capture the current behavior pre-fix to confirm the lookup is
  broken (returns wrong thing) and post-fix to confirm it's now
  correct.
- Negative test: `class A { method m($self) { my $x = 2; if (1) { my $y = $x; } } }`.
  Inner $y should still resolve $x from the enclosing scope (the
  fix must not over-suppress).

If pre-fix behavior is already wrong in a specific observable way,
write the test to assert the corrected behavior and watch it fail
pre-fix, then pass post-fix. If pre-fix happens to produce the
right answer by accident, the test still serves as a regression
guard.

**Test gate:**
- `bnf-target-c.t` 178/178 unchanged.
- `mop/*.t` all green at current counts.
- New `scope-hygiene-block.t` passes.
- Pre-existing failures preserved.

### Commit 2: `refactor(actions): retire cond_leaf scope workarounds (6 sites)`

**Files:**
- Modify `lib/Chalk/Bootstrap/Perl/Actions.pm` — delete the
  cond_leaf workarounds at the 6 sites identified below.

**Sites to clean up:**

For each site, the pattern is:
- Capture `$cond_leaf` during a leaves walk.
- Read `_ctx_scope($cond_leaf)` to recover pre-rule scope.
- Use that scope for downstream computations (phi merges, post-rule
  scope).

After Commit 1, `$ctx->scope` IS the pre-rule scope (because Block's
action wrote it). The captures and reads can be replaced with direct
`$ctx->scope` reads.

1. **IfStatement** (Actions.pm:2548 + 2625):
   - Delete `my $cond_leaf` capture during the leaves walk.
   - Replace `$pre_scope = _ctx_scope($cond_leaf)` with `$pre_scope = $ctx->scope`.

2. **ElsifChain** (Actions.pm:2741):
   - Already reads `_ctx_scope($ctx)` directly; verify it's correct
     post-Commit-1. If it was contaminated before, it's fixed now.
     If it was working by accident, the behavior may change —
     surface during testing.

3. **WhileStatement** (Actions.pm:2788 + 2834):
   - Delete `$cond_leaf` capture.
   - Replace `$pre_loop_scope = _ctx_scope($cond_leaf)` with
     `$pre_loop_scope = $ctx->scope`.

4. **ForStatement** (Actions.pm:2935 + 2984):
   - Same pattern as WhileStatement.

5. **ForeachStatement** (Actions.pm:~3128):
   - Same pattern.

6. **TryCatchStatement** (Actions.pm:1131):
   - Already reads `_ctx_scope($ctx)`. Audit whether it was correct
     before (the spec author hasn't traced this); confirm correct
     after Commit 1.

**Tests:**

The existing `bnf-target-c.t`, `mop/*.t`, and the entire test suite
serve as regression guards. If any test changes pass/fail count
after Commit 2, that's a real signal — investigate before
declaring done. The expectation: zero regressions because the
behavior is unchanged (the workarounds were doing the right thing
by another path; Commit 1 lets us do it directly).

**Test gate:**
- `bnf-target-c.t` stays 178/178.
- All `mop/*.t` stay green at current counts.
- `xs-polymorphic-dispatch.t` 59/60 (baseline preserved).
- `xs-int-specialization.t` 2/6 (baseline preserved).
- `xs-isa-inheritance.t` 10/10, `xs-athx-no-args.t` 7/7.
- `t/bootstrap/scope-hygiene-block.t` from Commit 1 still passes.
- Actions.pm: grep `cond_leaf` returns zero matches. (Documents
  that the workaround pattern is fully retired.)

## Risks

1. **Block's pre-block scope recovery may fail in edge cases.**
   The leftmost-leaf walk assumes `$ctx` has children whose
   children eventually terminate at a leaf with a scope. If
   `$ctx` is a leaf itself (Block with empty body?), or if the
   leftmost leaf has no scope, the walk returns undef and the
   `update_scope` call is skipped — leaving the legacy
   `_complete_sa` inherit-from-`$value` fallback in effect. This
   is the LEGACY behavior, so falling back is safe but doesn't
   help. **Mitigation:** the test for an empty Block (`method m($self) { }`)
   should be present in `scope-hygiene-block.t`; document the
   fallback semantics.

2. **The leftmost leaf may not be what I think it is.** If
   Block's parsing dispatches differently than I expect (e.g.,
   the opening-brace token is consumed by an OUTER rule and Block
   only sees the StatementList), the leftmost leaf's scope might
   be mid-block, not pre-block. **Mitigation:** instrument Block's
   action during development to print the leftmost leaf's `rule()`
   and `scope()`; verify it's pre-block. If it's not, adapt the
   walk (e.g., find the leftmost leaf whose `rule` is the opening
   brace token, or trace upward from `$ctx`).

3. **Commit 2's workaround deletions may surface latent bugs.**
   The cond_leaf workarounds may have been compensating for
   scope-contamination but ALSO compensating for other unrelated
   bugs (e.g., scope-merge order, sibling propagation). When
   deleted, those other bugs may surface. **Mitigation:** the test
   gate is broad (full test suite); if any test fails after
   Commit 2, surface and investigate before merging.

4. **TryCatchStatement and ElsifChain may need adjustments
   different from the 4 named cond_leaf sites.** Both read
   `_ctx_scope($ctx)` directly, not via a captured `cond_leaf`.
   The Commit 1 fix (Block writes pre-Block scope) means
   `$ctx->scope` for those rules is now correct, so they may
   become correct for the first time. **Mitigation:** audit
   their tests pre/post Commit 1; document any behavior changes.

5. **Block's existing logic may rely on scope being unset.**
   The current Block action does NOT call `update_scope`, so
   `_complete_sa`'s inherit-from-`$value` fallback fires. After
   Commit 1, the fallback no longer fires (scope IS set). If some
   downstream code path depends on the fallback's specific
   choice of `$value->scope`, that path may break. **Mitigation:**
   the `bnf-target-c.t` 178/178 baseline is the canary; if any
   test starts failing after Commit 1, the fallback was
   load-bearing somewhere.

## Open question for implementation

`SemanticAction->current_instance->update_scope($scope)` — does
the `update_scope` API accept any Scope object, or does it
validate against the current Block context? Read
SemanticAction.pm:188-192 to confirm semantics. If `update_scope`
requires the scope to be a descendant of the current scope (e.g.,
for invariant-preservation), the leftmost-leaf scope may not
qualify. In that case, the API may need an `update_scope_replace`
variant.

If the API is too restrictive, the alternative is to set scope
directly via the pending-scope-update mechanism that
`_complete_sa` reads at line 306, bypassing `update_scope`'s
validation. The result is equivalent; the API path is just
different.

## What was rejected from v1

- **Grammar-level `Rule.is_scoping` flag.** Rejected because the
  fix lives in Block's action, not in parser machinery. The
  grammar doesn't need to know which rules are scoping.
- **`_mul_ctx` suppression check.** Rejected because the complete
  event for Block never reaches `_mul_ctx`; the multiply call
  that combines Block's result with later siblings sees a
  Context without `annotations->{complete}`.
- **`_complete_sa` scoping-rule check.** Considered but rejected
  in favor of action-level fix: keeping the suppression logic
  inside the action that owns the language-semantic decision is
  more cohesive than spreading it across parser code.

## Acceptance

This design is approved when:
1. Block's action explicitly publishes pre-Block scope via
   `update_scope` or equivalent.
2. The 6 cond_leaf workaround sites in Actions.pm are deleted
   (grep `cond_leaf` returns zero).
3. ElsifChain and TryCatchStatement are audited and either
   confirmed correct post-fix or adjusted in the same commit.
4. `bnf-target-c.t` 178/178; all baselines preserved; pre-existing
   failures unchanged.
5. `scope-hygiene-block.t` covers: (a) inner my doesn't leak; (b)
   outer my is still visible inside; (c) empty Block edge case.

## Acknowledged but out of scope: Block action is accreting workarounds

Block's action in Actions.pm now contains three workarounds for
the same structural fact — `multiply()` consolidates effects at
parent-rule completion, which is too late for sibling-to-sibling
or pre-rule-state propagation to reach child actions directly.
The three workarounds:

1. **Control-chain rebuild** (Actions.pm:1575+). Side-effect IR
   nodes' chain heads can't propagate sibling-to-sibling at
   action time; Block rebuilds the chain post-hoc by walking
   `@stmts` in source order. Phase 3a-migration introduced this.
2. **Exit-type classification** (Actions.pm:1521-1571). TI prunes
   at ExpressionStatement boundaries; Block carries a 20-line
   `_classify_value_type` helper to recover the "Block as
   expression value" type the consumer needs.
3. **Explicit scope publication** (proposed in this design).
   `my` declarations inside Block leak to enclosing scope unless
   Block's action explicitly writes pre-Block scope back via
   `update_scope`.

This design adds the third workaround. The pattern is accreting.
The proper architectural fix would be a unified treatment of
"parser-time multi-statement effects" — likely a change to
`_merge_scope` semantics or to when multiply consolidates child
effects. That change would let all three workarounds retire.

That cleanup is **not in this design's scope**. The accretion is
acknowledged in memory at `block_action_workaround_accretion.md`
so future work can find the pattern. The TI-pruning question is
acknowledged in memory at `ti_over_pruning_block_type.md`.

## Out of scope

- Grammar-level scoping marks (deferred indefinitely).
- Other scoping rules besides Block (none known in Perl today).
- A general scope-effect type system.
- Re-litigating the comonad's multiply semantics; the fix lives
  inside an action, not in the comonad's plumbing.
- The architectural cleanup of Block's accreted workarounds
  (acknowledged above; deferred to a separate brainstorm).
- TI pruning revision (acknowledged separately; out of this
  fix's scope).
