# Divorce `control_head` from `bindings` — Architectural Design

**Date:** 2026-05-26
**Status:** Design v3 — addresses spec-document-reviewer iteration 2 (1 minor: co-existence invariant + Sentinel test-file grep). Supersedes `2026-05-26-scope-snapshot-restore-design.md`.
**Branch:** `fixup-audit-baseline` (continues from Phase 7d commits).

## Purpose

`Chalk::Bootstrap::Scope` bundles two unrelated parser-time
concerns: **variable bindings** (lexically scoped) and the
**control-chain head** (sibling-to-sibling advancing). They have
different consumers, different propagation needs, and different
invariants — but the bundle forces them to share one propagation
contract through `_merge_scope`. Every consumer of one ends up
paying for the other.

This design separates them into two independent Context fields,
each with its own propagation rule. It retires three accreted
workarounds in Block's action and the six cond_leaf workarounds in
the control-flow rules, all of which exist because the bundled
contract can't deliver what its consumers actually need.

## The evidence that motivates the split

1. **Six `cond_leaf` workaround sites** in `lib/Chalk/Bootstrap/Perl/Actions.pm`
   (IfStatement, ElsifChain, WhileStatement, ForStatement,
   ForeachStatement, TryCatchStatement). They walk the multiply
   tree to recover pre-rule bindings from a child leaf because
   `$ctx->scope->bindings` is contaminated by the time the
   parent rule's action fires. *Symptom: bindings wanted lexical
   propagation; got sibling-merging propagation.*

2. **Block's control-chain rebuild** (Actions.pm:1575+). Side-effect
   IR nodes are rewritten in source order so each one's `inputs[0]`
   points at the previous side-effect. This exists because
   `Scope.control` does NOT propagate sibling-to-sibling within a
   StatementList — `_merge_scope` only fires at the parent rule's
   multiply, too late for the second statement's action to see the
   first statement's effect. *Symptom: control wanted
   sibling-to-sibling propagation; got bound-by-parent-multiply
   propagation.*

3. **Block's exit-type classifier** (Actions.pm:1521-1571). Not a
   bindings or control issue per se, but documents a related
   pattern: parser-time information that consumers need is not
   reaching them at the moment they need it. (Out of scope for
   this design; see `ti_over_pruning_block_type.md`.)

4. **Unread `MOP::Class.scope` field** (Phase 7c-prep). Added as
   "forward infrastructure" with no consumer; the intended
   consumer (method bodies closing over class scope) needs lexical
   bindings, not the control head. *Symptom: a consumer wants ONLY
   bindings; today's `Scope` forces them to carry control too.*

All four reduce to the same underlying defect: bundling forces
bindings and control to share one propagation rule, and neither
gets the rule it actually needs.

## The architectural change

Split `Chalk::Bootstrap::Scope` into two Context concerns:

- **`bindings`** — a lexical-scoped variable→IR-node map. Its
  propagation rule: inner-scope bindings do not leak outward at
  rule-completion. The propagation contract is roughly
  *"lexically nested rules see outer bindings; outer rules
  do not see inner rules' new bindings."* Implemented today by
  the immutable `Chalk::Bootstrap::Scope` class (which becomes
  bindings-only after this design lands).
- **`control_head`** — the current end of the side-effect chain.
  An IR node (or undef before any side effect). Its propagation
  rule: sibling-to-sibling, monotonically advancing. The
  propagation contract is *"each side-effect node advances the
  head; subsequent actions see the most advanced head."* No
  lexical scoping — control flows through Block boundaries
  normally (a `my $x = 1` inside a Block IS a real side effect
  the outer chain must thread through).

Each becomes an independent Context field. Each gets its own
propagation logic in `_mul_ctx`. Neither pays for the other's
contract.

## Consequences of the split (what falls out)

- **Block's control-chain rebuild retires.** With `control_head`
  advancing sibling-to-sibling at parse time, the second
  statement's action sees the first statement's effect as
  `$ctx->control_head` when it runs. No post-hoc rebuild needed.
- **The 6 cond_leaf workarounds retire.** With `bindings`
  lexical-scoped at rule boundaries, `$ctx->bindings` at
  IfStatement's action time is honestly pre-IfStatement
  bindings — because the Block child's inner `my`s don't leak
  outward. No leaf-walking needed.
- **`MOP::Class.scope` gets a concrete semantic.** The field
  carries bindings only (not control). Method bodies that close
  over class scope read `$class->bindings` — a coherent
  consumer for a bindings-only field.

## What ships

Five commits on `fixup-audit-baseline`. The split happens
incrementally so each commit leaves the test suite green.

### Commit 1: `feat(context): add control_head as an independent Context field`

**Files modified:**
- `lib/Chalk/Bootstrap/Context.pm` — add `field $control_head :param :reader = undef;`
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`:
  - `_mul_ctx` populates `control_head` via the precise rule:
    `$control_head = $right->control_head // $left->control_head`.
    **This is NOT identical to `_merge_scope`'s logic** —
    `_merge_scope` has additional Start-vs-non-Start tiebreak
    handling that is bindings-aware. For control_head alone
    (no bindings concern), "right wins unless undef" is the
    correct sibling-to-sibling propagation.
  - `_one_ctx` (line 83 area) currently constructs the initial
    scope via `Chalk::Bootstrap::Scope->new()->with_control($start)`.
    This commit ALSO sets `control_head => $start` on the
    Context constructed at lines 84-92 to keep the shadow field
    in sync with the seed.
- `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` — `_wrap_sa_result`, `_pack_survivors`, and the `_add_unpacked` inline pack propagate `control_head` alongside `mop`/`scope`/`graph`/`factory`.

**Files created:**
- `t/bootstrap/context-control-head.t` — verifies the field default (undef), propagates through `_mul_ctx`, advances on "right wins unless undef" rule, and stays in sync with `scope.control` across a real parse.

**No consumer reads `$ctx->control_head` yet** — `scope.control` is
still the source of truth for the parser at this commit. The new
field exists, gets populated correctly, and is silently consistent
with `scope.control`. This is the "shadow field" stage.

**Sync invariant assert:** at the start of `_complete_sa` (or in
a debug-only path during Commit 1 and Commit 2), assert that
`scope.control` and `control_head` agree. The assert form (handles
undef==undef without warnings):

```perl
my $sc = $value->scope && $value->scope->control;
my $ch = $value->control_head;
my $sync_ok = (!defined $sc && !defined $ch)
    || (defined $sc && defined $ch && refaddr($sc) == refaddr($ch));
die "control_head/scope.control divergence" unless $sync_ok;
```

The assert is removed in Commit 3 when `scope.control` deletes.

**Test gate:** all current baselines pass; new context-control-head.t
asserts the shadow field behaves correctly; sync invariant holds
across `bnf-target-c.t` (178/178).

### Commit 2: `refactor(actions): migrate control reads from scope.control to control_head`

**Verified site counts (per reviewer iteration 1 audit):**
- `with_control` write sites in Actions.pm: **10** (lines 211, 1792, 2329, 2453, 2516, 2680, 2766, 2902, 3059, 3206).
- `with_control` write site in SemanticAction.pm: **1** (line 83, `_one_ctx`).
- `_ctx_control` read-only call sites in Actions.pm: **12**.
- `cfg_state()` in `lib/Chalk/Bootstrap/Context.pm` lines 190-228: reads `$ns->control()` **three times**.
- Total touch points: **~26** distinct sites across 3 files.

**Files modified:**

- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`:
  - Add `update_control_head($node)` method (analog of
    `update_scope`). Stores to a `$_pending_control_head_update`
    class lexical.
  - In `_complete_sa`, after applying `$_pending_scope_update`,
    apply `$_pending_control_head_update` to the result
    Context's `control_head` field.

- `lib/Chalk/Bootstrap/Perl/Actions.pm`:
  - **Read sites** (12 `_ctx_control` calls): `_ctx_control($ctx)`
    becomes `$ctx->control_head`. The `_ctx_control` helper itself
    becomes a one-line wrapper `sub _ctx_control($ctx) { return $ctx->control_head; }`
    OR is deleted entirely (call sites updated to call `->control_head` directly).
    **Decision: keep the helper as a one-line wrapper through Commit 3,
    delete in Commit 3 alongside the other cleanup.** This minimizes
    diff churn in Commit 2.

  - **Write sites** (10 `with_control` chains): each is currently
    one of two shapes:

    **Shape A** — single update, no chaining:
    ```perl
    $sa->update_scope($scope->with_control($region));
    ```
    Migrates to two calls:
    ```perl
    $sa->update_scope($scope);
    $sa->update_control_head($region);
    ```

    **Shape B** — chained with `define`:
    ```perl
    $new_scope = $scope->define($name, $node)->with_control($vd);
    ```
    Migrates to:
    ```perl
    $new_scope = $scope->define($name, $node);
    # control_head update happens separately via update_control_head
    # or by setting on the next constructed Context.
    ```

    The exact migration shape for each of the 10 sites is enumerated
    during implementation. Lines 1792 and 2329 are the chained
    forms (Shape B); lines 211, 2453, 2516, 2680, 2766, 2902, 3059,
    3206 are the single-update forms (Shape A).

- `lib/Chalk/Bootstrap/Context.pm`:
  - **`cfg_state()` method (lines 190-228)** migrates to read
    `$node->control_head` directly instead of walking child
    scopes for `$ns->control()`. The "prefer non-Start" tiebreak
    logic stays — `cfg_state()` walks `@stack` to find the most
    advanced control. New shape:
    ```perl
    method cfg_state() {
        my @stack = ($self);
        my $found_ch;
        my $found_scope;
        my %structural;
        while (@stack) {
            my $node = pop @stack;
            my $nc = $node->control_head;
            if (defined $nc) {
                if (!defined $found_ch
                        || (defined $found_ch && $found_ch->operation eq 'Start'
                            && $nc->operation ne 'Start')) {
                    $found_ch = $nc;
                    $found_scope = $node->scope;
                }
            }
            # ... structural annotation collection unchanged ...
            push @stack, $node->children->@*;
        }
        return undef unless defined $found_ch;
        return {
            control => $found_ch,
            scope   => $found_scope,
            %structural,
        };
    }
    ```
    This preserves `cfg_state()`'s public contract (returns hash
    with `control` and `scope` keys) but sources `control` from
    `control_head` instead of `scope.control`.

    **Co-existence invariant**: `control_head` and `scope` must
    co-exist on a Context — wherever the parser sets one, it sets
    (or already has) the other. `_one_ctx` constructs a Context
    with both `scope` and `control_head` populated from the
    initial Start. `_mul_ctx` propagates both. `_complete_sa`
    applies both pending updates. The `cfg_state` pseudocode
    above assumes this invariant; if any site sets `control_head`
    without scope, the returned `{scope => undef}` is a code bug,
    not a cfg_state defect. Audit each `control_head` setter
    during Commit 2 implementation to confirm co-existence.

- `lib/Chalk/Bootstrap/Scope.pm` — **unchanged in this commit**.
  The `control` field is still populated by `with_control` calls
  for sync-invariant purposes. Both paths remain live.

At this commit, BOTH paths are live: `scope.control` AND
`control_head` carry the same information. Actions read the new
path. The legacy path is still populated to keep the sync invariant
assert from Commit 1 happy.

**Sync invariant**: still active through Commit 2; deleted in Commit 3.

**Test gate:** `bnf-target-c.t` 178/178; all mop/*.t green;
pre-existing failures preserved. The behavior must be
byte-identical because both paths still update in sync.

### Commit 3: `refactor(scope): delete Scope.control; Scope → Bindings rename`

**All importers of `Chalk::Bootstrap::Scope`** (verified by
`grep -rn 'use Chalk::Bootstrap::Scope\|Chalk::Bootstrap::Scope->'`):

Production:
- `lib/Chalk/Bootstrap/Scope.pm` (self)
- `lib/Chalk/MOP/Class.pm` (lines 12 + 24 — the unread MOP::Class.scope field)
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` (lines 8 + 83 — `_one_ctx` seed)

Tests:
- `t/bootstrap/scope.t`
- `t/bootstrap/scope-threading.t`
- `t/bootstrap/cfg-try-catch.t` (lines 12 + 33 + 65 — uses `with_control`)

Fixtures:
- `t/fixtures/codegen-goldens/Chalk__MOP__Class.pl.golden` (line 9 — used by `codegen-byte-compat.t`; **must regenerate golden** post-rename, mirroring the 7c-prep pattern)

**Files modified/renamed:**

- `lib/Chalk/Bootstrap/Scope.pm` → renamed to `lib/Chalk/Bootstrap/Bindings.pm`
  - Delete `$control` field, `with_control` method, `control` reader.
  - Update class declaration to `class Chalk::Bootstrap::Bindings`.
  - The constructor calls at internal sites (lines 33, 47, 94, 118, 228, 271) update to `Chalk::Bootstrap::Bindings->new(...)` and drop the `control => $control` parameter.
- `lib/Chalk/Bootstrap/Scope/Sentinel.pm` → renamed to `lib/Chalk/Bootstrap/Bindings/Sentinel.pm`
  - Update package name; update `Chalk::Bootstrap::Scope.pm`'s `use Chalk::Bootstrap::Scope::Sentinel` to the new name.
  - **Pre-commit verification:** `grep -rn 'Chalk::Bootstrap::Scope::Sentinel' lib t script` must show only the import inside the (renamed) Bindings module. If any test file imports Sentinel directly, update those imports in this commit.
- `lib/Chalk/Bootstrap/Context.pm`:
  - Rename field `$scope` → `$bindings`; keep `scope()` reader as a deprecation shim returning `$bindings`.
  - Delete the sync-invariant assert from Commit 1.
  - **`cfg_state()`**'s structure stays as updated in Commit 2 (reads `$node->control_head`); the `scope =>` field in its return hash now returns a `Bindings` object instead of a `Scope`.
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`:
  - `_merge_scope` renamed to `_merge_bindings`; delete the
    control-merging logic (already redundant after Commit 2).
  - `_one_ctx` line 83 changes from
    `Chalk::Bootstrap::Scope->new()->with_control($start)` to
    `Chalk::Bootstrap::Bindings->new()` (no control); the Context
    constructed at lines 84-92 sets `control_head => $start`
    directly. (This site was already partially migrated in Commit 1
    to set `control_head`; this commit drops the legacy `with_control` call.)
  - `use Chalk::Bootstrap::Scope` → `use Chalk::Bootstrap::Bindings`.
- `lib/Chalk/MOP/Class.pm`:
  - Line 12: `use Chalk::Bootstrap::Scope` → `use Chalk::Bootstrap::Bindings`.
  - Line 24: `field $scope :reader = Chalk::Bootstrap::Scope->new;` →
    `field $bindings :reader = Chalk::Bootstrap::Bindings->new;`.
    **API change for MOP::Class consumers** — `$mop_class->scope` becomes `$mop_class->bindings`. Per Phase 7c-prep, this field has no production consumers; the only code that reads it would be test code or future work. Audit before committing.
- `lib/Chalk/Bootstrap/Perl/Actions.pm`:
  - Delete `_ctx_control` helper (lines 194-196) — Commit 2 made it a one-line wrapper; Commit 3 deletes it and inlines `$ctx->control_head` at the 12 call sites.
  - Delete the line 211 site (`$new_scope = $new_scope->with_control(...)` inside `_resolve_from_scope`) — this site is fundamentally about bindings construction; it no longer needs the control update post-divorce. **Audit during implementation to confirm**.
- **Test file updates** (mechanical):
  - `t/bootstrap/scope.t` → `t/bootstrap/bindings.t` (rename file; update class references)
  - `t/bootstrap/scope-threading.t` → rename or update imports
  - `t/bootstrap/cfg-try-catch.t` → update imports + change `Chalk::Bootstrap::Scope->new()->with_control($start)` to construct a Context with `control_head => $start` directly
- **Golden file regeneration**:
  - `t/fixtures/codegen-goldens/Chalk__MOP__Class.pl.golden` regenerates because MOP::Class now imports `Chalk::Bootstrap::Bindings` instead of `Chalk::Bootstrap::Scope`. Same pattern as 7c-prep's golden regeneration when MOP::Class gained new fields.

**Test gate:** all baselines preserved (counts unchanged). The rename + control removal is mechanical; behavior unchanged because Commit 2 already moved all control reads off `scope.control`. The golden file regeneration must produce the only Chalk__MOP__Class.pl.golden diff; if any OTHER golden file changes, surface as a regression signal.

### Commit 4: `refactor(actions): retire Block's control-chain rebuild`

**Pre-commit audit required.** Per reviewer iteration 1 findings,
the rebuild loop at Block:1575+ does more than rewire `inputs[0]`.
Reading lines 1575-1666:

| Stmt type | Operation | Becomes no-op when control_head propagates? |
|---|---|---|
| `VarDecl` | `unmerge($s)` + `make('VarDecl', inputs => [$current_control, ...])` + `merge($rebuilt)` — **identity replacement** | Conditional. If VarDecl actions construct nodes with the correct `inputs[0]` because they read `$ctx->control_head`, the rebuilt node is identical (hash-cons returns same). If not, the rebuild is still load-bearing. |
| `Return` / `Unwind` | `unmerge($s)` + `make_cfg('Return', ...)` + `merge($rebuilt)` | Same conditional as VarDecl. ReturnStatement reads `_ctx_control($ctx)` to set its `inputs[0]`; after Commit 2 this is `$ctx->control_head`, so the construct should already be correct. |
| `Call` / `Assign` / `CompoundAssign` / `RegexSubst` / `TryCatch` | `$s->set_control_in($current_control)` — **mutation on existing node** | No-op if action constructs nodes with correct control. The mutation is idempotent when current==target. |
| `If` / `Loop` | `$s->set_control_in($current_control)` + advance `$current_control = $s->region` | Same as Call. The region-advance is implicit in how control_head propagates through If/Loop scheduler annotations; verify. |

**Audit conclusion:** the rebuild's `unmerge`/`merge` pattern for
VarDecl/Return/Unwind is **load-bearing graph identity replacement**.
If any action constructs a node with the WRONG `inputs[0]` (e.g.,
because it ran before `control_head` propagated through some
sibling), the rebuild ensures the graph ends up with a single
correct node. Removing the rebuild blindly risks leaving stale
nodes in the graph alongside the correct ones.

**Required pre-commit verification:** instrument the rebuild loop
to count how many statements actually need replacement (the
`refaddr($existing_ctrl) != refaddr($current_control)` branch
fires). Run `bnf-target-c.t` with the instrumentation. If the
counter is zero across all 178 tests, the rebuild is fully
redundant post-Commit-2 and safe to delete. If non-zero, identify
which actions are producing stale-control nodes and fix those
upstream BEFORE deleting the rebuild.

**Files modified (post-audit):**
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — delete the
  control-chain rebuild loop at Block:1575-1666 (~90 lines).

**Test gate:** all baselines preserved. The audit instrumentation
is removed in this commit (or stays as a debug-only assert if the
instrumenter wants to keep monitoring).

### Commit 5: `feat(actions): Block publishes pre-Block bindings; retire 6 cond_leaf workarounds`

**Leftmost-leaf walk termination condition** (clarifying the v2-superseded mechanism):

The walk descends `$ctx->children->[0]` until it reaches a leaf
(a Context with empty `children`). For Block's grammar
(`Block ::= "{" StatementList "}"`), the leftmost leaf is the
`{` scan leaf, whose `bindings` predates StatementList. Termination
condition:

```perl
my $n = $ctx;
while (defined $n && $n->children->@* > 0) {
    $n = $n->children->[0];
}
my $pre_block_bindings = defined $n ? $n->bindings : undef;
```

If `$ctx` is itself a leaf (empty Block), the walk terminates
immediately with `$n == $ctx`. If the leftmost leaf has undef
bindings (edge case), `update_bindings` is not called and
`_complete_sa`'s inherit-from-`$value` fallback handles it.


This is the v2 scope-hygiene fix, now narrowed correctly because
`bindings` is the right field to suppress (control_head is
separate and SHOULDN'T be suppressed — the chain threads through
Block normally).

**Files modified:**
- `lib/Chalk/Bootstrap/Perl/Actions.pm`:
  - `Block` action publishes pre-Block bindings via
    `update_bindings($pre_block_bindings)`. Pre-Block bindings
    are recovered from the leftmost leaf of `$ctx`. (The `extend`
    contract clarification from the v2 reviewer applies:
    `$ctx` IS the multiply tree, so `$ctx->children->[0]`
    descended to a leaf gives the `{`-token leaf whose bindings
    pre-date StatementList.)
  - The 6 cond_leaf workaround sites
    (IfStatement 2548+2625, ElsifChain 2741, WhileStatement
    2788+2834, ForStatement 2935+2984, ForeachStatement ~3128,
    TryCatchStatement 1131) get cleaned up: leaf captures
    deleted; `_ctx_scope($cond_leaf)` reads replaced with
    `$ctx->bindings`.
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` — add
  `update_bindings($bindings)` (or repurpose `update_scope` —
  see "Naming" below).
- `lib/Chalk/Bootstrap/Context.pm` — delete the `scope()`
  deprecation shim added in Commit 3. Callers use `bindings()`.

**Naming question for this commit:** `update_scope` is the
existing API name. After Commit 3, "scope" is just bindings, so
`update_scope` is honest. But future-proofing for the eventual
`MOP::Class.scope` consumer suggests renaming to
`update_bindings` to be precise. Defer the decision to
implementation time — both names are correct post-Commit-3.

**Test gate:** all baselines preserved; the 6 sites' tests stay
green; `bnf-target-c.t` 178/178.

**Files created:**
- `t/bootstrap/scope-hygiene-block.t` — covers inner-my-doesn't-leak,
  outer-my-visible-inside, nested Block, empty Block edge case.

## Risks

1. **Commit 2's dual-path invariant.** `scope.control` and
   `control_head` must stay in sync after Commit 2. If a code path
   updates one but not the other, behavior diverges.
   **Mitigation:** an assert (or warn) at the start of `_complete_sa`
   that `$value->scope->control == $value->control_head` (allowing
   undef==undef). Catches divergence in CI before Commit 3 lands.
   Remove the assert in Commit 3 once `scope.control` deletes.

2. **Commit 4's rebuild deletion may surface latent work.** Block's
   control-chain rebuild may be doing more than chain rewriting —
   e.g., synthesizing missing nodes, normalizing shapes that the
   parser produces inconsistently. **Mitigation:** pre-commit audit
   (read Block:1575+ carefully); document any auxiliary work; move
   it to the appropriate location BEFORE deleting the rebuild.

3. **Commit 5's leftmost-leaf walk relies on grammar shape.** If
   Block's grammar alternative starts with something other than a
   token leaf (e.g., if `{` is consumed by an outer rule),
   leftmost-leaf may not be pre-Block bindings. **Mitigation:**
   the spec's prior v2 review acknowledged this; the mitigation is
   instrumentation during development. The current Perl grammar
   has `Block ::= "{" StatementList "}"` so the leftmost-leaf IS
   the `{` token leaf, which IS pre-Block bindings.

4. **The 6 cond_leaf workaround sites might be doing different
   things in subtle ways.** ElsifChain and TryCatchStatement read
   `_ctx_scope($ctx)` directly without capturing `$cond_leaf` —
   they may need a different mechanism than the 4 leaf-capturing
   sites. **Mitigation:** audit each of the 6 sites individually
   in Commit 5; surface any that don't fit the "$ctx->bindings is
   now pre-rule" pattern.

5. **`MOP::Class.scope` field semantic shift.** The field today
   holds a `Chalk::Bootstrap::Scope` (bindings+control). After
   Commit 3, it holds a `Chalk::Bootstrap::Bindings`. The single
   consumer that exists (none in production; just the 7c-prep
   forward-infra) is unaffected, but any future consumer should
   read `bindings`, not `scope`.

6. **Cross-commit interaction with the unused 7d repair counters.**
   None — the counters are independent of scope/control mechanics.
   No interaction.

## Bisect contract

Each commit leaves the test suite in a known state:
- **C1**: shadow field added; behavior unchanged.
- **C2**: control reads route through the new field; behavior
  unchanged (sync invariant guards via assert).
- **C3**: `Scope.control` deleted; `Scope` → `Bindings` rename;
  behavior unchanged.
- **C4**: Block's control-chain rebuild deleted; behavior
  unchanged.
- **C5**: bindings hygiene published by Block; the 6 cond_leaf
  workarounds retire; behavior unchanged.

A `git bisect` between any two commits identifies which one
introduced a regression. The "behavior unchanged" claim at each
commit is verifiable via the full `bnf-target-c.t` 178/178 +
mop/*.t suite.

## Acceptance

This design is approved when:

1. `control_head` is a first-class Context field with its own
   propagation rule (sibling-to-sibling, monotonically advancing).
2. `Bindings` (the renamed `Scope`) carries variable bindings only;
   no control field.
3. Block's control-chain rebuild (Actions.pm:1575+) is deleted.
4. The 6 cond_leaf workaround sites are deleted; `$ctx->bindings`
   is honest pre-rule at each site.
5. `bnf-target-c.t` 178/178; all mop/*.t green at current counts;
   pre-existing failures preserved (xs-polymorphic-dispatch.t 59/60,
   xs-int-specialization.t 2/6).
6. `lib/Chalk/Bootstrap/Scope.pm` and `lib/Chalk/Bootstrap/Scope/Sentinel.pm`
   are renamed/moved; no stale references survive.

## Out of scope (deferred)

- **TI pruning revision.** The TI-prunes-Block-type issue from
  `ti_over_pruning_block_type.md` is a separate architectural
  question.
- **`MOP::Class.scope` activation.** The field becomes a
  Bindings (not a Scope) at Commit 3; activating it (i.e., having
  method bodies actually close over it) is a separate phase, not
  part of this design.
- **A general scope-effect type system.** Not needed for the
  current consumers.
- **Grammar-level scoping marks.** Not needed; the action-level
  fix is sufficient and the parser stays oblivious.
- **The "Block accreted workarounds" cleanup** — this design
  retires the control-chain rebuild and adds the bindings
  publication, but the exit-type classifier remains. That's a
  TI-pruning question, not a scope/control question.

## Memory references

- `block_action_workaround_accretion.md` — documents the
  three workarounds. This design removes #1 (control chain
  rebuild, Commit 4) and #3 (scope publication, Commit 5).
  #2 (exit-type classification) remains; it's not a
  scope/control issue.
- `ti_over_pruning_block_type.md` — out-of-scope reference;
  the TI pruning question is separate.
