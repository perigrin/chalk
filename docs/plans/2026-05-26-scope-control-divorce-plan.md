# Scope/Control Divorce — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `Chalk::Bootstrap::Scope` into two Context fields with separate propagation rules (`bindings` for lexical scoping; `control_head` for sibling-to-sibling control-chain advancement), then retire 6 cond_leaf workarounds in Actions.pm and Block's 90-line post-hoc control-chain rebuild.

**Architecture:** Five commits on `fixup-audit-baseline`. Each commit leaves the test suite green and bisect-friendly. C1 adds `control_head` as a shadow field (no consumer). C2 migrates all 26 touch points to read/write the new field. C3 deletes `Scope.control` and renames `Chalk::Bootstrap::Scope` → `Chalk::Bootstrap::Bindings`. C4 retires Block's control-chain rebuild (pre-commit instrumentation audit). C5 makes Block publish pre-Block bindings, retiring the 6 cond_leaf workarounds.

**Tech Stack:** Perl 5.42.0 (via pvm at `/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl`, NOT plenv), `feature class`, postfix dereferencing, `true`/`false` builtins, `try/catch`. Test harness: `perl -Ilib t/...`.

**Status:** Plan v3 — addresses plan-document-reviewer iteration 2 (1 Important: `_merge_bindings` semantic clarification). All earlier findings (3 Critical + 6 Important + 4 Suggestion from iteration 1) verified in v2.

**Spec:** `docs/plans/2026-05-26-scope-control-divorce-design.md`

**Skills mandate (per CLAUDE.md):** every implementer of every task MUST invoke `@superpowers:writing-perl-5.42.0` and `@superpowers:test-driven-development` before writing code.

---

## File Map

### Commit 1 — files touched

**Modify:**
- `lib/Chalk/Bootstrap/Context.pm` — add `control_head` field + reader.
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` — propagate `control_head` in `_mul_ctx` + `_one_ctx`; add sync-invariant assert at top of `_complete_sa`.
- `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` — propagate `control_head` in `_wrap_sa_result`, `_pack_survivors`, and the inline ambiguity-pack inside `add()`.

**Create:**
- `t/bootstrap/context-control-head.t` — verifies shadow field behavior.

### Commit 2 — files touched

**Modify:**
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — migrate 10 `with_control` writes + 12 `_ctx_control` reads to use `control_head`.
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` — add `update_control_head($node)` method + apply in `_complete_sa`.
- `lib/Chalk/Bootstrap/Context.pm` — migrate `cfg_state()` to read `$node->control_head`.

### Commit 3 — files touched

**Rename:**
- `lib/Chalk/Bootstrap/Scope.pm` → `lib/Chalk/Bootstrap/Bindings.pm`
- `lib/Chalk/Bootstrap/Scope/Sentinel.pm` → `lib/Chalk/Bootstrap/Bindings/Sentinel.pm`

**Modify:**
- `lib/Chalk/Bootstrap/Bindings.pm` (post-rename) — delete `$control` field, `with_control`, `control` reader. Update all internal `Chalk::Bootstrap::Scope->new(...)` constructor calls.
- `lib/Chalk/Bootstrap/Bindings/Sentinel.pm` (post-rename) — update package name + class refs.
- `lib/Chalk/Bootstrap/Context.pm` — rename `$scope` field to `$bindings`; keep `scope()` reader as one-commit deprecation shim; delete sync-invariant assert from C1.
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` — rename `_merge_scope` → `_merge_bindings`; delete control-merging logic; update `_one_ctx` to construct `Bindings` (no control) and set `control_head => $start` on the Context directly. Update `use` statement.
- `lib/Chalk/MOP/Class.pm` — `use` line + field type change.
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — delete `_ctx_control` helper + audit/delete the line 211 `with_control` site (in `_resolve_from_scope`).
- `t/bootstrap/scope.t` → renamed to `t/bootstrap/bindings.t`; update class references.
- `t/bootstrap/scope-threading.t` — update imports + assertions.
- `t/bootstrap/cfg-try-catch.t` — update imports + construct Contexts with `control_head` directly.
- `t/fixtures/codegen-goldens/Chalk__MOP__Class.pl.golden` — regenerate.

> **Post-execution audit amendment (2026-05-30): the C3 file map above is materially incomplete.** A pre-execution grep of `Chalk::Bootstrap::Scope` across `lib script t` found a far larger surface than the three test files listed. Corrections:
>
> **Production (two additions to the list above):**
> - `_merge_scope` has **TWO** call sites in SemanticAction.pm, not one. Line ~142 (inside `_mul_ctx`, already noted in Task 3.3 Step 0) AND line ~565 (inside the disambiguation/merge path that builds `$correct_scope`/`$rejected_scope` and stashes a `_transferred_scope` annotation). The line-565 caller also relies on the `->control` tiebreak that C3 deletes. Both callers must migrate to `_merge_bindings`; the line-565 path needs the same control-free merge semantics.
> - `_ctx_control` has **11** call sites in Actions.pm (Task 3.3 Step 5 says 12 — stale). `_ctx_scope` has **23** (decision (a) keeps the helper, so callers are untouched).
> - Context.pm `cfg_state` was already rewritten in C2; its remaining `$node->scope` reads are inside the C2 body (~lines 215/221), not at the old line 190.
>
> **Tests — the real surface is 21 files + 1 golden, classified as:**
> - **DELETE (1):** `t/bootstrap/scope/control-input.t` — a dedicated `with_control`/`control` unit-test suite (~7 subtests asserting `->control`, `with_control` immutability, chaining, merge-control). It tests the exact methods C3 removes; it cannot be migrated and must be deleted. (The plan never mentioned this file.)
> - **MIGRATE control assertions (1):** `t/bootstrap/context-cfg-annotation.t` — 5 sites asserting `scope->control` / `->scope()->control()->operation()`. Migrate to `control_head` reads; this file also exercises the cfg_state shim that C2 changed, so re-verify behavior.
> - **MIGRATE setup to `control_head` (3):** `scope-variable-lookup.t`, `cfg-statements.t`, `assignment-scope.t` — construct Contexts via `scope->with_control($n)` purely as setup; rewrite to `bindings => Bindings->new(...), control_head => $n` (same pattern C2 applied to `cfg-try-catch.t`).
> - **RENAME-only (16, incl. the 2 the plan already listed):** `scope.t`→`bindings.t`, `scope-threading.t`, `cfg-loop-phi.t`, `context-control-head.t`, `context/graph-scope-fields.t`, `context/scope-containment.t`, `ir-return-cfg-node.t`, `phi-integration.t`, `postfix-loop-phi.t`, `scope-for-loop-merge.t`, `scope-phi-merge.t`, `scope-sentinel.t`, `scope-ssa.t`, `scope-trivial-phi.t` (also calls `Chalk::Bootstrap::Scope::_remove_trivial_phi` → `Bindings::`), `semantic-action-scope.t`. These reference the class only by `use`/construction/`isa`; change the name, nothing else.
>
> Executing C3 as originally written (touching only 3 test files) would leave ~18 test files broken — most failing to compile (`Can't locate Chalk::Bootstrap::Scope`), plus `scope/control-input.t` and `context-cfg-annotation.t` failing on deleted-method assertions. The corrected task list below (Tasks 3.4a–3.4c) reflects the full surface.

### Commit 4 — files touched

**Modify:**
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — delete the control-chain rebuild loop at Block:1575-1666 (after pre-commit instrumentation audit).

### Commit 5 — files touched

**Modify:**
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — Block action publishes pre-Block bindings via `update_bindings`; retire 6 cond_leaf workaround sites.
- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` — add `update_bindings($bindings)` method + apply in `_complete_sa`. (Keep `update_scope` as a deprecated alias for one more commit, or rename — see Task 5.1.)

**Create:**
- `t/bootstrap/scope-hygiene-block.t` — covers inner-`my`-doesn't-leak, outer-`my`-visible-inside, nested Block, empty Block.

---

## Baseline capture (one-time, before any task)

Confirm starting state. Numbers are from Phase 7d's final state.

- [ ] **Step B1: Confirm branch state.**

```bash
cd /home/perigrin/dev/chalk/.claude/worktrees/pu
git status
git log --oneline -1
```

Expected:
- Working tree clean.
- HEAD is `7583245f docs(plans): scope/control divorce architecture design + superseded predecessor` (or a later docs-only commit).

- [ ] **Step B2: Capture baseline test counts.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
for t in t/bootstrap/mop/codegen-byte-compat.t \
         t/bootstrap/mop/class-scope-vars.t \
         t/bootstrap/mop/use-constants.t \
         t/bootstrap/mop/parse-integration.t \
         t/bootstrap/mop/parse-threading.t \
         t/bootstrap/mop/ctx-mop-propagation.t \
         t/bootstrap/mop/field-helpers.t \
         t/bootstrap/mop/test-pipeline-helper.t \
         t/bootstrap/c-emit-helpers-inheritance.t \
         t/bootstrap/bnf-target-c.t \
         t/bootstrap/xs-isa-inheritance.t \
         t/bootstrap/xs-athx-no-args.t \
         t/bootstrap/scope.t \
         t/bootstrap/scope-threading.t \
         t/bootstrap/cfg-try-catch.t \
         t/bootstrap/c-repair-coverage.t \
         t/bootstrap/c-schedule-walker.t \
         t/bootstrap/c-analysis-helpers-schedule.t \
         t/bootstrap/c-simple-body-shortcuts.t \
         t/bootstrap/c-sub-state-leak.t \
         t/bootstrap/c-schedule-tail-control.t; do
    echo "=== $t ==="
    $PERL -Ilib "$t" 2>&1 | tail -3
done
```

Record:
- All MOP tests green; specific counts as recorded in `2026-05-25-phase-7d-plan.md` baseline.
- `bnf-target-c.t`: 178/178.
- `c-emit-helpers-inheritance.t`: 55/55.
- `xs-isa-inheritance.t`: 10/10.
- `xs-athx-no-args.t`: 7/7.
- `scope.t`, `scope-threading.t`, `cfg-try-catch.t`: green (counts to be verified — these are touched by C3).

- [ ] **Step B3: Capture pre-existing failures.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/xs-polymorphic-dispatch.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/xs-int-specialization.t 2>&1 | tail -3
```

Record:
- `xs-polymorphic-dispatch.t`: 59/60 (pre-existing Component 4 failure).
- `xs-int-specialization.t`: 2/6 (pre-existing `newSVnv` failures).

---

## COMMIT 1 — Shadow `control_head` field

### Task 1.0: Write failing context-control-head.t (TDD)

**Files:**
- Create: `t/bootstrap/context-control-head.t`.

- [ ] **Step 1: Write the failing test.**

Create `t/bootstrap/context-control-head.t`:

```perl
# ABOUTME: Phase scope/control divorce C1 — verifies control_head shadow field behavior.
# ABOUTME: Confirms field default undef, propagation through _mul_ctx, and sync with scope.control.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Scope;
use Chalk::IR::NodeFactory;

# Default value is undef.
my $ctx0 = Chalk::Bootstrap::Context->new(focus => undef);
ok(!defined $ctx0->control_head, 'default control_head is undef');

# Constructor accepts the field.
my $factory = Chalk::IR::NodeFactory->new();
my $start = $factory->make('Start');
my $ctx1 = Chalk::Bootstrap::Context->new(
    focus => undef,
    control_head => $start,
);
is(refaddr($ctx1->control_head), refaddr($start),
   'constructor accepts control_head');

# extend() propagates control_head.
my $ctx2 = $ctx1->extend(sub { 'whatever' });
is(refaddr($ctx2->control_head), refaddr($start),
   'extend() propagates control_head from self');

# extend() with explicit control_head override.
my $start2 = $factory->make('Start');
my $ctx3 = $ctx1->extend(sub { 'x' }, control_head => $start2);
is(refaddr($ctx3->control_head), refaddr($start2),
   'extend() with explicit control_head override works');

done_testing();
```

- [ ] **Step 2: Run to confirm failure.**

```bash
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/context-control-head.t 2>&1 | tail -5
```

Expected: FAIL — `Can't locate object method "control_head" via package "Chalk::Bootstrap::Context"` (the field doesn't exist yet).

The test passes after Task 1.1 adds the field. Do NOT proceed to Task 1.1 until you've confirmed the test fails with the EXPECTED message.

---

### Task 1.1: Add `$control_head` field to Context

**Files:**
- Modify: `lib/Chalk/Bootstrap/Context.pm` (add field at line ~20; update `extend` at line 30-46).

- [ ] **Step 1: Add the field declaration.**

Edit `lib/Chalk/Bootstrap/Context.pm`. Find the `factory` field declaration (line 20). Add immediately after:

```perl
    field $control_head :param :reader = undef;
```

- [ ] **Step 2: Propagate `control_head` through `extend`.**

In the same file, find the `extend` method (line 30-46). Add `control_head => (exists $opts{control_head} ? $opts{control_head} : $control_head),` to the Context->new arg list (alongside the existing `factory => ...` line). Result:

```perl
    method extend($f, %opts) {
        my $new_focus = $f->($self);
        return Chalk::Bootstrap::Context->new(
            focus       => $new_focus,
            children    => [$self],
            position    => $position,
            rule        => (exists $opts{rule} ? $opts{rule} : $rule),
            annotations => (exists $opts{annotations} ? $opts{annotations} : { $annotations->%* }),
            token       => (exists $opts{token} ? $opts{token} : $token),
            is_zero     => (exists $opts{is_zero} ? $opts{is_zero} : $is_zero),
            error       => (exists $opts{error} ? $opts{error} : $error),
            mop         => (exists $opts{mop} ? $opts{mop} : $mop),
            graph       => (exists $opts{graph} ? $opts{graph} : $graph),
            scope       => (exists $opts{scope} ? $opts{scope} : $scope),
            factory     => (exists $opts{factory} ? $opts{factory} : $factory),
            control_head => (exists $opts{control_head} ? $opts{control_head} : $control_head),
        );
    }
```

- [ ] **Step 3: Confirm existing tests still pass.**

```bash
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/context-unified-fields.t 2>&1 | tail -5
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-threading.t 2>&1 | tail -5
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -5
```

Expected: all green; counts unchanged. Adding an optional field with a default value is invisible to existing tests.

- [ ] **Step 4: Do NOT commit yet.** Commit 1 lands after Tasks 1.2-1.5.

---

### Task 1.2: Propagate `control_head` in `_mul_ctx`

**Files:**
- Modify: `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` lines 128-155.

- [ ] **Step 1: Locate `_mul_ctx`.**

```bash
grep -n 'my sub _mul_ctx' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Semiring/SemanticAction.pm
```

Expected: line 128.

- [ ] **Step 2: Add `control_head` propagation.**

Find the existing `Chalk::Bootstrap::Context->new(...)` call inside `_mul_ctx`. The current shape:

```perl
            Chalk::Bootstrap::Context->new(
                focus    => undef,
                children => [$left, $right],
                position => $right->position(),
                rule     => undef,
                mop      => $_mop,
                scope    => $scope,
                graph    => $graph,
                factory  => $factory,
            );
```

Add `control_head` propagation (right wins unless undef) immediately before the `Chalk::Bootstrap::Context->new(...)` call:

```perl
            # control_head: right wins unless undef. This is the
            # "sibling-to-sibling, monotonically advancing" rule
            # — distinct from _merge_scope's bindings-aware logic.
            my $control_head = $right->control_head() // $left->control_head();
```

Then add `control_head => $control_head,` to the Context->new arg list (alongside `factory => $factory,`).

**Note (post-execution plan amendment, 2026-05-29):** the simple `right->control_head // left->control_head` rule above is INSUFFICIENT. It clobbers an already-advanced `control_head` on the left with the seed `Start` carried on the right, diverging from `scope.control` and firing the C2 sync-invariant assert. The implemented rule mirrors `_merge_scope`'s control tiebreak exactly: when both sides are defined and left is non-Start while right is Start, prefer left (more advanced); otherwise prefer right; when only one side is defined, use it (right preferred when both undef). This restores the non-Start preference that `scope.control` always had. The zero-divergence result across the full MOP suite confirms the two rules now agree. See the implemented form in `SemanticAction.pm::_mul_ctx`.

- [ ] **Step 3: Confirm tests pass.**

```bash
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
```

Expected: 178/178. The new field is populated but no consumer reads it; behavior unchanged.

- [ ] **Step 4: Do NOT commit yet.**

---

### Task 1.3: Set `control_head` in `_one_ctx` seed

**Files:**
- Modify: `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` lines 82-92.

- [ ] **Step 1: Add `control_head => $start` to the Context constructor in `_one_ctx`.**

Find the `_one_ctx` Context->new at line 84-92. Add `control_head => $start,` alongside the existing `scope => $scope,` field:

```perl
            $_one_singleton = Chalk::Bootstrap::Context->new(
                focus    => undef,
                children => [],
                position => 0,
                rule     => undef,
                mop      => $_mop,
                scope    => $scope,
                factory  => $parse_factory,
                control_head => $start,
            );
```

- [ ] **Step 2: Run tests.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/parse-threading.t 2>&1 | tail -3
```

Expected: 178/178 and 11/11. Behavior unchanged.

- [ ] **Step 3: Do NOT commit yet.**

---

### Task 1.4: Propagate `control_head` in FilterComposite

**Files:**
- Modify: `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm` — three Context->new sites (`_wrap_sa_result` ~line 147, `_pack_survivors` ~line 179, inline ambiguity-pack inside `add()` ~line 475).

- [ ] **Step 1: Locate the three sites.**

```bash
grep -n 'Chalk::Bootstrap::Context->new' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Semiring/FilterComposite.pm
```

Expected matches around lines 88 (`zero`), 120 (`one`), 147 (`_wrap_sa_result`), 179 (`_pack_survivors`), 475 (inline ambiguity-pack inside `add()`). The relevant three are 147, 179, 475.

- [ ] **Step 2: Add `control_head` propagation at `_wrap_sa_result` (line ~147).**

Find the Context->new at line ~147 inside `_wrap_sa_result`. Add one line alongside the existing `factory => ...` propagation:

```perl
            control_head => ($is_ctx ? $sa_result->control_head() : undef),
```

- [ ] **Step 3: Add `control_head` propagation at `_pack_survivors` (line ~179).**

Find the Context->new at line ~179 inside `_pack_survivors`. Add one line alongside the existing `factory => ...` propagation:

```perl
            control_head => $survivors[0]->control_head(),
```

- [ ] **Step 4: Add `control_head` propagation at the inline ambiguity-pack inside `add()` (around line ~485).**

This is a `Context->new(...)` block inside the `add()` method (line ~521), in the branch that creates an ambiguity-packed Context with `is_ambiguous => true`. NOT a separate sub. Locate it:

```bash
grep -nB1 'is_ambiguous => true' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Semiring/FilterComposite.pm
```

Expected: matches at line ~185 (inside `_pack_survivors` — already updated in Step 3) and line ~485 (the `add()` inline pack — this step). Add:

```perl
            control_head => $left->control_head(),
```

- [ ] **Step 5: Verify FilterComposite::one() also propagates.**

Check line 120 (`FilterComposite::one`). It already propagates `mop`/`scope`/`graph`/`factory`. Add `control_head` alongside:

```perl
            control_head => ($is_ctx ? $sa_one->control_head() : undef),
```

`FilterComposite::zero` (line 88) does NOT need control_head — zeros carry no parse-level state.

- [ ] **Step 6: Confirm tests pass.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/mop/ctx-mop-propagation.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
```

Expected: ctx-mop-propagation.t 10/10; bnf-target-c.t 178/178.

- [ ] **Step 7: Do NOT commit yet.**

---

### Task 1.5: Verify Task 1.0 test passes; Commit 1

**Files:** none modified beyond Tasks 1.1-1.4.

**Note (post-execution plan amendment, 2026-05-27):** The sync-invariant assert that v1 of this plan placed here is INCOMPATIBLE with Commit 1 alone. The assert fires whenever `scope.control` advances without `control_head` advancing in lockstep — which happens on every `update_scope($scope->with_control($region))` call in Actions.pm. Those call sites are Commit 2's migration scope; until C2 introduces `update_control_head`, control_head stays at the seed value while scope.control advances. The assert is correct, but it cannot be green at C1.

The assert is therefore **moved to Commit 2** (Task 2.1, after the migration is complete and the sites are paired). Commit 1 ends with no assert; the sync invariant is enforced after C2 in retrospect (a one-time correctness verification across the full test suite).

- [ ] **Step 1: Run the Task 1.0 test (now expected to PASS).**

After Tasks 1.1-1.4 added the field and propagation, the failing test from Task 1.0 should now pass:

```bash
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/context-control-head.t 2>&1 | tail -5
```

Expected: 4/4 PASS.

- [ ] **Step 2 (SKIPPED — moved to Commit 2):** The sync-invariant assert is moved to Task 2.1 to avoid firing on every Actions.pm `update_scope` call before the C2 migration pairs them with `update_control_head`.

Edit `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`. Find `_complete_sa` (line ~276). At the top of the method body (immediately after `return $self->zero() if $value->is_zero();` at line 277), add:

```perl
        # Sync invariant: control_head and scope.control must agree during
        # Commits 1-2. Removed in Commit 3 when scope.control deletes.
        {
            my $sc = $value->scope && $value->scope->control;
            my $ch = $value->control_head;
            my $sync_ok = (!defined $sc && !defined $ch)
                || (defined $sc && defined $ch
                    && Scalar::Util::refaddr($sc) == Scalar::Util::refaddr($ch));
            die "control_head/scope.control divergence at rule=$rule_name: "
                . "sc=" . (defined $sc ? ref($sc) : 'undef')
                . " ch=" . (defined $ch ? ref($ch) : 'undef')
                unless $sync_ok;
        }
```

Make sure `use Scalar::Util qw(refaddr);` is in the file (check at the top of SemanticAction.pm; if not, add it).

**Variable-scope sanity:** `$rule_name` is the second arg to `_complete_sa($value, $rule_name)`; it's in scope at the top of the method. The assert can reference it directly.

- [ ] **Step 3: Run the full test suite to catch sync-invariant violations.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
for t in t/bootstrap/mop/*.t t/bootstrap/bnf-target-c.t t/bootstrap/xs-isa-inheritance.t; do
    echo "=== $t ==="
    $PERL -Ilib "$t" 2>&1 | tail -3
done
```

Expected: all green. If the assert fires, control_head propagation has a gap — find which task missed a site and fix.

- [ ] **Step 4: Stage Commit 1.**

```bash
cd /home/perigrin/dev/chalk/.claude/worktrees/pu
git status
git add lib/Chalk/Bootstrap/Context.pm \
        lib/Chalk/Bootstrap/Semiring/SemanticAction.pm \
        lib/Chalk/Bootstrap/Semiring/FilterComposite.pm \
        t/bootstrap/context-control-head.t
git status
git commit -m "$(cat <<'EOF'
feat(context): add control_head as an independent Context field

Adds $control_head as a new Context field, populated in parallel
with the existing scope.control (which stays alive through
Commit 2 of the scope/control divorce; deleted in Commit 3).

Propagation rule for control_head in _mul_ctx is precise:
`right.control_head // left.control_head` — distinct from
_merge_scope's bindings-aware logic. This is "sibling-to-sibling,
monotonically advancing."

_one_ctx now sets control_head=$start on the seed Context so the
shadow field is consistent from the start of every parse.

FilterComposite propagates control_head through one(),
_wrap_sa_result, _pack_survivors, and the inline ambiguity-pack
inside add() —
pack (mirrors the mop/scope/graph/factory propagation already
in those sites).

Sync invariant assert at top of _complete_sa enforces
scope.control == control_head during Commits 1-2; removed in
Commit 3.

No consumer reads control_head yet. Behavior unchanged.

Design: docs/plans/2026-05-26-scope-control-divorce-design.md
EOF
)"
git log --oneline -1
```

Expected: commit succeeds.

---

## COMMIT 2 — Migrate consumers to `control_head`

### Task 2.1: Add `update_control_head` to SemanticAction

**Files:**
- Modify: `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` (add method + pending-update application).

- [ ] **Step 1: Add `$_pending_control_head_update` class lexical.**

Edit `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`. Find the existing `$_pending_scope_update` declaration (search):

```bash
grep -n 'pending_scope_update\|pending_annotations_update\|pending_graph_update' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Semiring/SemanticAction.pm | head -5
```

Add `my $_pending_control_head_update;` immediately alongside the existing pending-update declarations.

- [ ] **Step 2: Add the `update_control_head` method.**

Find the existing `update_scope` method (line ~188). Immediately after `update_graph` (around line ~209), add:

```perl
    # Request a control_head update from within an action method.
    # Called by Actions.pm during extend(); _complete_sa applies the update
    # to the result context's control_head field after the action returns.
    method update_control_head($node) {
        $_pending_control_head_update = $node;
        return;
    }
```

- [ ] **Step 3: Clear `$_pending_control_head_update` at the top of `_complete_sa`.**

Find the clear block at line ~284-286 (next to `$_pending_scope_update = undef;`). Add:

```perl
        $_pending_control_head_update = undef;  # Clear before action call
```

- [ ] **Step 4a: Retrofit `control_head` propagation into the THREE existing Context->new rebuilds in `_complete_sa`.**

These three blocks currently rebuild `$result_ctx` for scope-update, graph-update, and scope-inherit-from-$value. None of them propagate `control_head`, so when any of them fires, `control_head` defaults to undef and gets clobbered. This must be fixed BEFORE adding the new control_head update block, otherwise the new block's effect will be silently stripped by a preceding rebuild.

Find each Context->new block (search for `Chalk::Bootstrap::Context->new(` inside `_complete_sa`, around lines 307, 337, 358-371). In each one, add:

```perl
                control_head => $result_ctx->control_head(),
```

alongside the existing `factory => $result_ctx->factory(),` line. Three sites total — one each in the scope-update block, the graph-update block, and the scope-inherit-from-$value block.

- [ ] **Step 4b: Apply the pending control_head update inside `_complete_sa`.**

Find the existing `if (defined $_pending_scope_update) { ... }` block (around line ~306). After the `if (defined $_pending_graph_update) { ... }` block (around line ~336), add:

```perl
        # Apply pending control_head update from action method, if any.
        if (defined $_pending_control_head_update) {
            $result_ctx = Chalk::Bootstrap::Context->new(
                focus       => $result_ctx->focus(),
                children    => $result_ctx->children(),
                position    => $result_ctx->position(),
                rule        => $result_ctx->rule(),
                annotations => $result_ctx->annotations(),
                token       => $result_ctx->token(),
                is_zero     => $result_ctx->is_zero(),
                error       => $result_ctx->error(),
                mop         => $result_ctx->mop(),
                scope       => $result_ctx->scope(),
                graph       => $result_ctx->graph(),
                factory     => $result_ctx->factory(),
                control_head => $_pending_control_head_update,
            );
            $_pending_control_head_update = undef;
        }
```

- [ ] **Step 5: Confirm tests still pass.**

```bash
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
```

Expected: 178/178. The method exists but no caller invokes it; behavior unchanged. The retrofit in Step 4a also keeps control_head flowing through the three existing rebuild blocks; the sync invariant should still hold.

- [ ] **Step 6: Do NOT commit yet.**

---

### Task 2.2: Migrate `cfg_state()` in Context.pm

**Files:**
- Modify: `lib/Chalk/Bootstrap/Context.pm` lines 190-228.

- [ ] **Step 1: Replace `cfg_state()` method body.**

Find the existing `cfg_state()` method (line 190). Replace the entire method with the schedule-driven version:

```perl
    # Returns { control, scope, ...structural } summarizing this Context.
    # Walks all child Contexts to find the most-advanced control_head; the
    # accompanying scope and structural annotations come from the same node.
    #
    # Post-Commit-2 of scope/control divorce: sources `control` from the
    # new control_head Context field, not from scope.control. The returned
    # hash's `control` and `scope` keys preserve the public contract.
    method cfg_state() {
        my @stack = ($self);
        my $found_ch;
        my $found_scope;
        my %structural;

        while (@stack) {
            my $node = pop @stack;

            my $nc = $node->control_head;
            if (defined $nc) {
                # Co-existence invariant: every site that sets control_head
                # also has scope populated. If $found_scope is missing here,
                # it's a code bug, not a cfg_state defect.
                if (!defined $found_ch) {
                    $found_ch = $nc;
                    $found_scope = $node->scope;
                } else {
                    # Prefer non-Start over Start (structural change wins).
                    if ($found_ch->operation eq 'Start'
                            && $nc->operation ne 'Start') {
                        $found_ch = $nc;
                        $found_scope = $node->scope;
                    }
                }
            }

            my $ann = $node->annotations();
            for my $key (@_cfg_struct_keys) {
                $structural{$key} //= $ann->{$key} if exists $ann->{$key};
            }

            push @stack, $node->children()->@*;
        }

        return undef unless defined $found_ch;

        return {
            control => $found_ch,
            scope   => $found_scope,
            %structural,
        };
    }
```

- [ ] **Step 2: Confirm tests pass.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/cfg-try-catch.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -3
```

Expected: bnf-target-c.t 178/178; cfg-try-catch.t green; parse-integration.t 34/34.

If anything fails with "Can't call method 'operation' on undef" or similar, the co-existence invariant has been violated by some Context that has control_head but no scope — track down the offending site.

- [ ] **Step 3: Do NOT commit yet.**

---

### Task 2.3: Migrate the 12 `_ctx_control` read sites in Actions.pm

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (~12 sites that call `_ctx_control($ctx)`).

- [ ] **Step 1: Locate all `_ctx_control` call sites.**

```bash
grep -n '_ctx_control\b' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Actions.pm
```

Expected: ~12 sites. List them.

- [ ] **Step 2: Update the `_ctx_control` helper itself to be a one-line wrapper.**

Find `_ctx_control` definition (around line 194-196). Replace with:

```perl
    # Helper: get the control_head from a Context (or undef).
    # Post-scope/control-divorce C2: reads control_head directly.
    # Helper kept as a wrapper for one commit; deleted in C3.
    my sub _ctx_control($ctx) {
        return $ctx->control_head;
    }
```

This means **no other site needs to change** — every site that calls `_ctx_control($ctx)` automatically routes through the new field. The 12 call sites stay; the wrapper bridges.

- [ ] **Step 3: Confirm tests pass.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -3
```

Expected: 178/178 and 34/34.

If the sync-invariant assert fires, control_head divergence — track down which `update_scope` site advanced control without setting control_head.

- [ ] **Step 4: Do NOT commit yet.**

---

### Task 2.4: Migrate the 10 `with_control` write sites in Actions.pm

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (10 sites: 211, 1792, 2329, 2453, 2516, 2680, 2766, 2902, 3059, 3206).

**Background:** the 10 sites fall into two shapes:

- **Shape A** — single update before passing to `update_scope`:
  ```perl
  $sa->update_scope($scope->with_control($region));
  ```
  Migrates to TWO calls: `$sa->update_scope($scope)` + `$sa->update_control_head($region)`.

- **Shape B** — chained with `define`:
  ```perl
  $new_scope = $scope->define($name, $node)->with_control($vd);
  ```
  Migrates to: `$new_scope = $scope->define($name, $node);` and the control_head update happens via the next `update_control_head` call (since the new scope object no longer carries control).

  Lines 1792 and 2329 are Shape B; the rest are Shape A.

- [ ] **Step 1: Migrate Shape A sites (8 sites).**

For each of: lines 2453, 2516, 2680, 2766, 2902, 3059, 3206.

Find the line. It looks like:
```perl
$sa->update_scope($scope->with_control($region));
```

Replace with:
```perl
$sa->update_scope($scope);
$sa->update_control_head($region);
```

Note: line 211 is INSIDE `_resolve_from_scope` (a helper), not inside an action. Its shape is:
```perl
$new_scope = $new_scope->with_control($scope->control()) if defined $scope->control();
```

This migrates to:
```perl
# Post-C2: $new_scope is bindings-only; the caller of _resolve_from_scope
# is responsible for control_head propagation. This line becomes:
# (line deleted — see Step 3 below for context)
```

Wait — line 211's exact handling needs to be decided based on how `_resolve_from_scope` is consumed. Read the helper definition (line 203-221 area) before deciding:

```bash
sed -n '195,225p' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Actions.pm
```

If `_resolve_from_scope` is only called for variable resolution (not for emitting a side-effect that advances control), the line 211 `with_control` is propagating control through scope-rebuilding — a bindings-side concern that becomes dead post-divorce. **Delete ONLY line 211 (the `with_control` call), not the surrounding `if ($new_scope) { $sa->update_scope($new_scope) }` block.** The `update_scope($new_scope)` call must remain — sentinel resolution still needs to update bindings. Document the decision in the commit message.

- [ ] **Step 2: Migrate Shape B sites (2 sites: 1792, 2329).**

**Note:** the variable names below are schematic. Each site has its own local names (e.g., line 2329 uses `$result` for the control-node and `$name_in->value()` for the binding name). Read each site's surrounding context and adapt the variable names; the structure of the migration is the same.

For line 1792:
```bash
sed -n '1785,1800p' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Actions.pm
```

The pattern is `$scope->define(NAME, NODE)->with_control(CONTROL)`. The chain produces a new bindings-with-control scope object that gets passed to `update_scope`. Migrate:

Schematic:
```perl
$sa->update_scope($scope->define(NAME, NODE)->with_control(CONTROL));
```

Becomes:
```perl
$sa->update_scope($scope->define(NAME, NODE));
$sa->update_control_head(CONTROL);
```

Apply the same pattern to line 2329. Read each site to identify the actual variable names — DO NOT assume the literal names from the schematic.

- [ ] **Step 3: Migrate the SemanticAction.pm `_one_ctx` site (line 83).**

```bash
sed -n '80,95p' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Semiring/SemanticAction.pm
```

The current code constructs the seed:
```perl
my $scope = Chalk::Bootstrap::Scope->new()->with_control($start);
```

After Task 1.3 set `control_head => $start` on the Context, we have BOTH paths populated. Now we can drop the `with_control` call (the scope will be bindings-only):

Change to:
```perl
my $scope = Chalk::Bootstrap::Scope->new();
```

But wait — `Scope.pm`'s constructor still requires the `control` field (it's `:param`). Need to verify whether `Chalk::Bootstrap::Scope->new()` works without arguments:

```bash
grep -n 'field $control' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Scope.pm
```

Expected: `field $control :param :reader = undef;` — has a default, so `->new()` works.

The original code chained `->with_control($start)` to make sure the scope had control populated for `_merge_scope`'s benefit. Now that `control_head` carries that info on the Context directly, the scope's control field can stay undef.

**Decision:** keep the legacy `->with_control($start)` chain in `_one_ctx` for now (it satisfies the sync invariant from Task 1.5's assert). It gets removed in C3 when `Scope.control` deletes entirely. So **Task 2.4 leaves the SemanticAction.pm site alone**; it migrates in C3.

- [ ] **Step 4: Confirm tests pass (pre-assert).**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/parse-threading.t 2>&1 | tail -3
```

Expected: bnf-target-c.t 178/178; parse-integration.t 34/34; c-emit-helpers-inheritance.t 55/55; parse-threading.t 11/11.

- [ ] **Step 4b: Add the sync-invariant assert at top of `_complete_sa` (moved from Task 1.5).**

Now that all `update_scope` writes are paired with `update_control_head` writes, the sync invariant should hold. Edit `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`. Find `_complete_sa` (line ~276). At the top of the method body (immediately after `return $self->zero() if $value->is_zero();`), add:

```perl
        # Sync invariant: control_head and scope.control must agree from
        # C2 onward (until C3 deletes scope.control entirely, removing
        # this assert).
        {
            my $sc = $value->scope && $value->scope->control;
            my $ch = $value->control_head;
            my $sync_ok = (!defined $sc && !defined $ch)
                || (defined $sc && defined $ch
                    && Scalar::Util::refaddr($sc) == Scalar::Util::refaddr($ch));
            die "control_head/scope.control divergence at rule=$rule_name: "
                . "sc=" . (defined $sc ? ref($sc) : 'undef')
                . " ch=" . (defined $ch ? ref($ch) : 'undef')
                unless $sync_ok;
        }
```

Confirm `use Scalar::Util qw(refaddr);` is at the top of the file; add it if missing.

- [ ] **Step 4c: Run the full suite with the assert in place to catch any C2 migration gaps.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
for t in t/bootstrap/mop/*.t t/bootstrap/bnf-target-c.t t/bootstrap/xs-isa-inheritance.t t/bootstrap/xs-athx-no-args.t t/bootstrap/scope-threading.t t/bootstrap/scope.t t/bootstrap/cfg-try-catch.t t/bootstrap/c-emit-helpers-inheritance.t; do
    echo "=== $t ==="
    $PERL -Ilib "$t" 2>&1 | tail -3
done
```

Expected: all green. If the assert fires on any test, the C2 migration missed a `with_control` site. Find the offending `update_scope` call (the rule name in the assert message points at it) and pair it with `update_control_head`.

The assert is removed in Commit 3 when `scope.control` deletes entirely.

- [ ] **Step 5: Stage Commit 2.**

```bash
cd /home/perigrin/dev/chalk/.claude/worktrees/pu
git status
git add lib/Chalk/Bootstrap/Perl/Actions.pm \
        lib/Chalk/Bootstrap/Semiring/SemanticAction.pm \
        lib/Chalk/Bootstrap/Context.pm
git status
git commit -m "$(cat <<'EOF'
refactor(actions): migrate control reads from scope.control to control_head

Migrate ~26 touch points from scope.control / with_control to the
new control_head Context field:

- 12 _ctx_control() reader sites in Actions.pm — the helper itself
  becomes a one-line wrapper around $ctx->control_head; call sites
  unchanged (the wrapper is deleted in C3 along with all _ctx_control
  callers being inlined).
- 10 with_control() write sites in Actions.pm (lines 211, 1792, 2329,
  2453, 2516, 2680, 2766, 2902, 3059, 3206) migrate to paired
  update_scope + update_control_head calls. Shape A (8 sites): single
  update, two calls. Shape B (2 sites): chained define+with_control,
  the define stays, the with_control becomes update_control_head.
  Line 211 (_resolve_from_scope helper) deleted — that site was
  propagating control through bindings-rebuilding, a pattern that's
  dead post-divorce.
- Context::cfg_state() (lines 190-228) now reads $node->control_head
  instead of walking child scopes for $ns->control(). Public contract
  preserved (returns hash with control and scope keys).

SemanticAction adds update_control_head($node) method, mirrors
update_scope's pending-update pattern, applied in _complete_sa after
update_scope.

Both paths are still live: scope.control is populated by SemanticAction.pm
line 83's _one_ctx seed (deleted in C3). The sync invariant from C1
ensures the two paths agree.

Design: docs/plans/2026-05-26-scope-control-divorce-design.md
EOF
)"
git log --oneline -1
```

Expected: commit succeeds; tests still 178/178 and friends.

---

## COMMIT 3 — Delete `Scope.control`; rename Scope → Bindings

### Task 3.1: Pre-flight grep for all consumers

**Files:** none modified.

- [ ] **Step 1: Enumerate all importers of `Chalk::Bootstrap::Scope`.**

```bash
cd /home/perigrin/dev/chalk/.claude/worktrees/pu
grep -rn 'use Chalk::Bootstrap::Scope\|Chalk::Bootstrap::Scope->\|Chalk::Bootstrap::Scope::' lib script t 2>/dev/null | grep -v '\.golden:' | sort -u
```

Expected: production importers (Scope.pm itself, SemanticAction.pm, MOP/Class.pm) plus test files (scope.t, scope-threading.t, cfg-try-catch.t). Plus the golden fixture which uses the name in generated text.

- [ ] **Step 2: Enumerate all importers of `Chalk::Bootstrap::Scope::Sentinel`.**

```bash
grep -rn 'Chalk::Bootstrap::Scope::Sentinel' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib /home/perigrin/dev/chalk/.claude/worktrees/pu/script /home/perigrin/dev/chalk/.claude/worktrees/pu/t 2>/dev/null
```

Expected: just Scope.pm's `use` line. If any test imports directly, document for migration.

- [ ] **Step 3: Record the full consumer list as a working document.**

Write the list to a scratch note (don't commit). Will be referenced during Tasks 3.2-3.5.

---

### Task 3.2: Rename Scope.pm → Bindings.pm + delete `control`

**Files:**
- Rename: `lib/Chalk/Bootstrap/Scope.pm` → `lib/Chalk/Bootstrap/Bindings.pm`.
- Rename: `lib/Chalk/Bootstrap/Scope/Sentinel.pm` → `lib/Chalk/Bootstrap/Bindings/Sentinel.pm`.
- Modify: the renamed files to use the new class names and drop `control`.

- [ ] **Step 1: `git mv` the files.**

```bash
cd /home/perigrin/dev/chalk/.claude/worktrees/pu
mkdir -p lib/Chalk/Bootstrap/Bindings
git mv lib/Chalk/Bootstrap/Scope.pm lib/Chalk/Bootstrap/Bindings.pm
git mv lib/Chalk/Bootstrap/Scope/Sentinel.pm lib/Chalk/Bootstrap/Bindings/Sentinel.pm
rmdir lib/Chalk/Bootstrap/Scope 2>/dev/null
git status
```

- [ ] **Step 2: Update Bindings.pm (formerly Scope.pm).**

Edit `lib/Chalk/Bootstrap/Bindings.pm`:

- Update ABOUTME comments to reflect new name and scope-only semantics.
- Change `class Chalk::Bootstrap::Scope {` → `class Chalk::Bootstrap::Bindings {`.
- Change `use Chalk::Bootstrap::Scope::Sentinel;` → `use Chalk::Bootstrap::Bindings::Sentinel;`.
- DELETE the `$control` field declaration (line ~18 area).
- DELETE the `with_control` method entirely.
- DELETE the `control` reader method (it's the implicit `:reader` on `$control`; deletion happens with the field).
- Update every internal `Chalk::Bootstrap::Scope->new(...)` constructor call (at lines **47, 94, 118, 228, 271** — five sites; line 33's constructor is inside the `with_control` method body which deletes wholesale below) to `Chalk::Bootstrap::Bindings->new(...)` and drop the `control => $control` parameter from each.

The `with_control` method at lines 33-37 deletes entirely (it's the bundling primitive being retired):

```perl
    # DELETE THIS METHOD ENTIRELY:
    method with_control($new_control) {
        return Chalk::Bootstrap::Scope->new(
            bindings => { $bindings->%* },
            control  => $new_control,
        );
    }
```

Example for line 47 (the `define` method's return — keep the method but drop control):

Before:
```perl
        return Chalk::Bootstrap::Scope->new(
            bindings => \%new_bindings,
            control  => $control,
        );
```

After:
```perl
        return Chalk::Bootstrap::Bindings->new(
            bindings => \%new_bindings,
        );
```

Same shape for lines 94, 118, 228, 271 — each is a constructor call; remove the `control` arg.

- [ ] **Step 3: Update Bindings/Sentinel.pm.**

Edit `lib/Chalk/Bootstrap/Bindings/Sentinel.pm`:

- Update ABOUTME if needed.
- Change `package Chalk::Bootstrap::Scope::Sentinel` → `package Chalk::Bootstrap::Bindings::Sentinel`.
- Update any references inside the file from `Chalk::Bootstrap::Scope::Sentinel` to `Chalk::Bootstrap::Bindings::Sentinel`.

- [ ] **Step 4: Confirm Bindings.pm and Bindings/Sentinel.pm load cleanly.**

```bash
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib -e 'use Chalk::Bootstrap::Bindings; my $b = Chalk::Bootstrap::Bindings->new; say defined $b ? "OK" : "FAIL";' 2>&1
```

Expected: prints `OK`. If it fails with `Can't locate` or `Bareword`, the rename has a typo.

- [ ] **Step 5: Do NOT commit yet.** The importers still reference the old name.

---

### Task 3.3: Update production importers

**Files:**
- Modify: `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm` — update `use` and `_one_ctx`.
- Modify: `lib/Chalk/MOP/Class.pm` — update `use` and field type.
- Modify: `lib/Chalk/Bootstrap/Context.pm` — rename `$scope` field to `$bindings`, add deprecation shim.
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` — delete `_ctx_control` helper + inline calls; audit line 211 site.

- [ ] **Step 0: Rename `_merge_scope` to `_merge_bindings` and simplify.**

Find `_merge_scope` (line ~101 in SemanticAction.pm). The current logic uses `control` for tiebreak between left and right; after removing `control` from Bindings, the simplified rule is:

```perl
    # Merge two bindings values from multiply children.
    # Preserves the legacy _merge_scope semantics exactly: right is the
    # receiver (base), left is folded in as overwrites. Per the legacy
    # comment "right takes precedence for dups," but reading the legacy
    # implementation (Scope.pm line 89-98) shows $self->merge($other)
    # actually has $other's bindings overwrite $self's — meaning the
    # ARGUMENT (left here) wins, not the receiver (right). The legacy
    # comment was wrong about which side wins; this implementation
    # preserves the legacy *behavior* exactly, regardless of the comment.
    my sub _merge_bindings($left_bindings, $right_bindings) {
        return $right_bindings // $left_bindings
            unless defined $left_bindings && defined $right_bindings;
        return $right_bindings->merge($left_bindings);
    }
```

**Important:** the reviewer's iteration-2 finding suggested swapping the argument order to `$left->merge($right)` based on the legacy comment. That would FLIP behavior because `Bindings::merge` makes the argument win, not the receiver. The legacy call site is `$base->merge($left_scope)` with `$base = $right_scope`, i.e., `$right_scope->merge($left_scope)` — exactly the form preserved here. Do not "fix" the comment by flipping the call; the behavior matches legacy.

Update the call site inside `_mul_ctx` (line ~134): `my $scope = _merge_scope($left->scope, $right->scope);` becomes:

```perl
        my $bindings = _merge_bindings($left->bindings, $right->bindings);
```

And the corresponding Context->new `scope => $scope,` field assignment becomes `bindings => $bindings,`.

**SECOND caller (post-execution audit, 2026-05-30):** `_merge_scope` is ALSO called at SemanticAction.pm line ~565, inside the disambiguation/merge path that builds `$correct_scope`/`$rejected_scope` and stashes a `_transferred_scope` annotation. Update that call to `_merge_bindings($correct_bindings, $rejected_bindings)` too, sourcing each from `->bindings` rather than `->scope`. This caller previously relied on `_merge_scope`'s `->control` tiebreak; after the rename, `_merge_bindings` is control-free (control lives on `control_head` now), which is correct — the disambiguation merge only needs binding reconciliation, not control selection. Verify the `_transferred_scope` annotation consumers still behave (the annotation key name can stay; it's an internal handle).

- [ ] **Step 1: Update SemanticAction.pm.**

```bash
grep -n 'Chalk::Bootstrap::Scope\|_merge_scope' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Semiring/SemanticAction.pm
```

Expected: `use` line (~8), the `_one_ctx` `->new()->with_control` (~90), the `_merge_scope` definition (~109), and BOTH call sites (~142 in `_mul_ctx`, ~565 in the disambiguation path).

Change line 8: `use Chalk::Bootstrap::Scope;` → `use Chalk::Bootstrap::Bindings;`

Change line 83: `my $scope = Chalk::Bootstrap::Scope->new()->with_control($start);` →

```perl
        my $scope = Chalk::Bootstrap::Bindings->new();
```

The `with_control` chain is gone because (a) `Bindings` doesn't have `with_control` and (b) the Context constructor at lines 84-92 already sets `control_head => $start` directly (from Task 1.3).

- [ ] **Step 2: Update MOP/Class.pm.**

```bash
grep -n 'Chalk::Bootstrap::Scope' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/MOP/Class.pm
```

Expected: line 12 (`use`) and line 24 (`field $scope :reader = Chalk::Bootstrap::Scope->new;`).

Change line 12: `use Chalk::Bootstrap::Scope;` → `use Chalk::Bootstrap::Bindings;`

Change line 24: `field $scope :reader = Chalk::Bootstrap::Scope->new;` →

```perl
    field $bindings :reader = Chalk::Bootstrap::Bindings->new;
```

(Note: this renames the field/reader from `$scope` / `scope()` to `$bindings` / `bindings()` per the design. Pre-flight grep should have verified that no production consumer reads `$mop_class->scope`. If any test does, update it.)

- [ ] **Step 3: Search for `$mop_class->scope` consumers.**

```bash
grep -rn '$mop_class->scope\|->for_class\(.*\)->scope\|\$cls->scope' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib /home/perigrin/dev/chalk/.claude/worktrees/pu/t 2>/dev/null | head -20
```

If matches, update each to `->bindings`. Verify with a re-run after the changes.

- [ ] **Step 4: Update Context.pm to rename field + add deprecation shim.**

Edit `lib/Chalk/Bootstrap/Context.pm`.

Change line 19: `field $scope :param :reader = undef;` →

```perl
    field $bindings :param :reader = undef;
```

After the `extract` method (around line 22-25), add the deprecation shim:

```perl
    # Deprecation shim for scope/control divorce C3. The field was renamed
    # to $bindings to reflect its bindings-only semantic. The `scope()`
    # alias here is for one-commit backward compatibility — deleted in C5.
    method scope() { return $bindings; }
```

Update the `extend` method at line 30-46: change `scope => (exists $opts{scope} ? $opts{scope} : $scope)` to read `$bindings` and stay named `bindings` in the new() call:

```perl
            bindings    => (exists $opts{bindings} ? $opts{bindings} : (exists $opts{scope} ? $opts{scope} : $bindings)),
```

(The `exists $opts{scope}` arm is the deprecation-shim path — callers passing `scope =>` to extend still work; deleted in C5.)

Update the `cfg_state()` method at line 190+: change `$ns->control()` to `$node->control_head` was done in C2; now the `$node->scope` reads inside it should become `$node->bindings`. Search and replace.

- [ ] **Step 5: Delete the `_ctx_control` helper and inline its 11 callers.** (Audit 2026-05-30: 11 call sites, not 12.)

Edit `lib/Chalk/Bootstrap/Perl/Actions.pm`.

Delete the `_ctx_control` helper definition (lines ~194-196).

Then for each of the 11 caller sites, replace `_ctx_control($ctx)` with `$ctx->control_head`. Use grep to find them:

```bash
grep -n '_ctx_control(' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Actions.pm
```

Replace each. The function is `my sub` so the deletion just removes the definition; the callers will then fail with "undefined subroutine" if any are missed.

- [ ] **Step 5b: Update `_ctx_scope` to read `bindings` instead of `scope`.**

`_ctx_scope` (lines ~189-191) is a SEPARATE helper from `_ctx_control` — it reads `$ctx->scope()`. There are 20+ call sites across Actions.pm (grep `_ctx_scope`). Two migration choices:

- (a) Update the helper body to `return $ctx->bindings;` — call sites unchanged. Minimal diff.
- (b) Delete the helper and inline all 20+ call sites to `$ctx->bindings`. Larger diff but eliminates the wrapper.

**Decision: option (a) for C3 — minimal diff, helper keeps working.** The helper itself can be deleted in a future cleanup phase if desired, but during C3 the bindings-rename is the focus; eliminating `_ctx_scope` is a separate cleanup.

Edit `lib/Chalk/Bootstrap/Perl/Actions.pm`. Find:

```perl
    my sub _ctx_scope($ctx) {
        return $ctx->scope();
    }
```

Replace with:

```perl
    # Helper: get the bindings from a Context (or undef).
    # Post-scope/control-divorce C3: reads bindings field directly.
    my sub _ctx_scope($ctx) {
        return $ctx->bindings;
    }
```

The Context::scope() deprecation shim added in Step 4 would also make the original code work, but reading directly from `bindings` is cleaner and means deleting the shim in C5 won't break this helper.

- [ ] **Step 6: Delete sync-invariant assert in `_complete_sa`.**

Edit `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`. Find the sync-invariant assert block added in Task 1.5 Step 3 (inside `_complete_sa`, near the top). Delete the entire `{ ... }` block. The assert is no longer needed because `scope.control` is deleted in this commit; there's nothing left to be out of sync with.

- [ ] **Step 7: Confirm tests pass.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -3
```

Expected: still green. If anything fails with `Can't locate object method "control"` or `Can't locate object method "scope"`, a consumer was missed.

- [ ] **Step 8: Do NOT commit yet.** Test files and goldens are next.

---

### Task 3.4: Migrate test files

**Files:**
- Modify (rename): `t/bootstrap/scope.t` → `t/bootstrap/bindings.t`.
- Modify: `t/bootstrap/scope-threading.t`.
- Modify: `t/bootstrap/cfg-try-catch.t`.

- [ ] **Step 1: Rename scope.t → bindings.t.**

```bash
cd /home/perigrin/dev/chalk/.claude/worktrees/pu
git mv t/bootstrap/scope.t t/bootstrap/bindings.t
```

- [ ] **Step 2: Update bindings.t (formerly scope.t) to use the new class name.**

Search for `Chalk::Bootstrap::Scope` in the file:

```bash
grep -n 'Chalk::Bootstrap::Scope' /home/perigrin/dev/chalk/.claude/worktrees/pu/t/bootstrap/bindings.t
```

Replace `Chalk::Bootstrap::Scope` → `Chalk::Bootstrap::Bindings` throughout. Update ABOUTME comments to reflect the new name. Delete any test cases that exercise `control` / `with_control` (those methods no longer exist).

- [ ] **Step 3: Update scope-threading.t imports.**

```bash
grep -n 'Chalk::Bootstrap::Scope' /home/perigrin/dev/chalk/.claude/worktrees/pu/t/bootstrap/scope-threading.t
```

Replace imports and any direct construction. If the test exercises `control` or `with_control`, update or delete those test cases.

- [ ] **Step 4: Update cfg-try-catch.t.**

```bash
grep -n 'Chalk::Bootstrap::Scope\|with_control' /home/perigrin/dev/chalk/.claude/worktrees/pu/t/bootstrap/cfg-try-catch.t
```

Lines 12, 33, 65 use `Chalk::Bootstrap::Scope->new()->with_control($start)`. Change to construct the Context with `control_head => $start` directly:

Before:
```perl
my $ctx = Chalk::Bootstrap::Context->new(
    focus       => undef,
    scope       => Chalk::Bootstrap::Scope->new()->with_control($start),
    # ...
);
```

After:
```perl
my $ctx = Chalk::Bootstrap::Context->new(
    focus       => undef,
    bindings    => Chalk::Bootstrap::Bindings->new(),
    control_head => $start,
    # ...
);
```

Update the file's `use` lines accordingly.

- [ ] **Step 5: Confirm test files pass.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/bindings.t 2>&1 | tail -5
$PERL -Ilib t/bootstrap/scope-threading.t 2>&1 | tail -5
$PERL -Ilib t/bootstrap/cfg-try-catch.t 2>&1 | tail -5
```

Expected: all pass (counts may have changed if tests were deleted; document any drops).

- [ ] **Step 6: Do NOT commit yet.** The remaining 18 test files (Tasks 3.4a–3.4c) and the golden are next.

---

### Task 3.4a: DELETE `scope/control-input.t`

**Files:**
- Delete: `t/bootstrap/scope/control-input.t`.

This file is a dedicated unit-test suite for `with_control` and the `control` reader (its ABOUTME: "Verifies with_control returns a new Scope with control replaced"). Every subtest asserts on a method C3 deletes. There is no migration target — the bundled-control behavior it tests is gone by design.

- [ ] **Step 1: Confirm the file only tests control/with_control (no orphaned binding coverage worth keeping).**

```bash
grep -nE 'subtest|with_control|->control|define|lookup' /home/perigrin/dev/chalk/.claude/worktrees/pu/t/bootstrap/scope/control-input.t | grep -vE '_encode|_decode'
```

The binding behavior (`define`/`lookup`/`merge`) is already covered by `scope.t`→`bindings.t`. If any assertion here is the *sole* coverage for a binding behavior, port it to `bindings.t` before deleting; otherwise delete outright.

- [ ] **Step 2: Delete.**

```bash
cd /home/perigrin/dev/chalk/.claude/worktrees/pu
git rm t/bootstrap/scope/control-input.t
rmdir t/bootstrap/scope 2>/dev/null || true   # if now empty
```

- [ ] **Step 3: Do NOT commit yet.**

---

### Task 3.4b: MIGRATE control-asserting + control-setup test files

**Files:**
- Modify: `t/bootstrap/context-cfg-annotation.t` — 5 sites assert `scope->control` / `->scope()->control()`; migrate to `control_head`.
- Modify: `t/bootstrap/scope-variable-lookup.t`, `t/bootstrap/cfg-statements.t`, `t/bootstrap/assignment-scope.t` — construct Contexts via `scope->with_control($n)` as setup; rewrite to `bindings => Chalk::Bootstrap::Bindings->new(...), control_head => $n`.

- [ ] **Step 1: context-cfg-annotation.t — migrate control assertions.**

```bash
grep -nE 'with_control|->control' /home/perigrin/dev/chalk/.claude/worktrees/pu/t/bootstrap/context-cfg-annotation.t | grep -vE '_encode|_decode'
```

For each Context construction, replace `scope => Chalk::Bootstrap::Scope->new()->with_control($n)` with `bindings => Chalk::Bootstrap::Bindings->new(), control_head => $n`. For each assertion `is($state->{control}, $n, ...)` keep as-is (cfg_state still returns a `control` key). For `$one->scope()->control()` / `$result->scope()->control()->operation()` style assertions, rewrite to read the Context's `control_head` directly (e.g. `$one->control_head->operation`). This file tests the cfg_state shim that C2 rewrote — re-verify each assertion's expectation against the post-C2 cfg_state behavior, don't assume the old shape.

- [ ] **Step 2: scope-variable-lookup.t / cfg-statements.t / assignment-scope.t — migrate setup.**

For each, replace the import and rewrite each `Chalk::Bootstrap::Scope->new()->with_control($n)` used as a Context `scope =>` value to the `bindings => ..., control_head => $n` pair, mirroring the `cfg-try-catch.t` migration from C2. Where `with_control` is chained after `define`, keep the `define` on the Bindings object and move the control node to `control_head`.

- [ ] **Step 3: Run the migrated files.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
for t in t/bootstrap/context-cfg-annotation.t t/bootstrap/scope-variable-lookup.t t/bootstrap/cfg-statements.t t/bootstrap/assignment-scope.t; do
    echo "=== $t ==="; $PERL -Ilib "$t" 2>&1 | tail -3
done
```

Expected: all green. Document any assertion-count changes.

- [ ] **Step 4: Do NOT commit yet.**

---

### Task 3.4c: RENAME-only test files (15)

**Files (mechanical `Chalk::Bootstrap::Scope` → `Chalk::Bootstrap::Bindings` + `Scope::Sentinel` → `Bindings::Sentinel` + `Scope::_remove_trivial_phi` → `Bindings::_remove_trivial_phi`):**
- `cfg-loop-phi.t`, `context-control-head.t`, `context/graph-scope-fields.t`, `context/scope-containment.t`, `ir-return-cfg-node.t`, `phi-integration.t`, `postfix-loop-phi.t`, `scope-for-loop-merge.t`, `scope-phi-merge.t`, `scope-sentinel.t`, `scope-ssa.t`, `scope-trivial-phi.t`, `semantic-action-scope.t`
- (Plus `scope.t`→`bindings.t` and `scope-threading.t` already covered in Task 3.4 Steps 2–3.)

These reference the class only by `use` / construction / `isa` / `ref ... eq '...Sentinel'` / the internal `_remove_trivial_phi` function. No control coupling. A name-only substitution suffices.

- [ ] **Step 1: Verify none of these secretly use control before bulk-renaming.**

```bash
for f in cfg-loop-phi context-control-head context/graph-scope-fields context/scope-containment ir-return-cfg-node phi-integration postfix-loop-phi scope-for-loop-merge scope-phi-merge scope-sentinel scope-ssa scope-trivial-phi semantic-action-scope; do
    if grep -qE 'with_control|->control\b' "t/bootstrap/$f.t" 2>/dev/null; then echo "CONTROL FOUND: $f"; fi
done
```

Expected: zero output. If any file prints, it was misclassified — move it to Task 3.4b.

- [ ] **Step 2: Apply the rename to each file.** Substitute `Chalk::Bootstrap::Scope::Sentinel` → `Chalk::Bootstrap::Bindings::Sentinel` FIRST (longest match), then `Chalk::Bootstrap::Scope` → `Chalk::Bootstrap::Bindings`. Update ABOUTME comments where they name the class. `context-control-head.t` will be deleted/renamed-around in C5 — for C3 just rename its `use`.

- [ ] **Step 3: Run all 15.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
for t in cfg-loop-phi context-control-head context/graph-scope-fields context/scope-containment ir-return-cfg-node phi-integration postfix-loop-phi scope-for-loop-merge scope-phi-merge scope-sentinel scope-ssa scope-trivial-phi semantic-action-scope; do
    echo "=== $t ==="; $PERL -Ilib "t/bootstrap/$t.t" 2>&1 | tail -2
done
```

Expected: all green.

- [ ] **Step 4: Do NOT commit yet.** Golden file is next.

---

### Task 3.5: Regenerate Chalk__MOP__Class.pl.golden

**Files:**
- Modify: `t/fixtures/codegen-goldens/Chalk__MOP__Class.pl.golden`.

The golden file contains the MOP-emitted Perl for `lib/Chalk/MOP/Class.pm`. The class now imports `Chalk::Bootstrap::Bindings` instead of `Chalk::Bootstrap::Scope` and has a `$bindings` field instead of `$scope`. The golden must be regenerated to match.

- [ ] **Step 1: Run the regeneration script.**

Adapt the script pattern from Phase 7c-prep's golden regen (see commit history for `Chalk__MOP__Field.pl.golden`). Write to `/tmp/regen_mop_class_golden.pl`:

```perl
use 5.42.0;
use utf8;
use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Perl::Target::Perl;

my $raw_ir = perl_pipeline();
my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ClassRegen/g;
eval $generated;
die "grammar eval: $@" if $@;
my $gen_grammar = Chalk::Grammar::Perl::ClassRegen::grammar();

my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
$parser->semiring->reset_cache;
my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();

open my $fh, '<:utf8', 'lib/Chalk/MOP/Class.pm' or die;
local $/;
my $src = <$fh>;
close $fh;
$parser->parse_value($src) or die "parse failed";

my $emitted = Chalk::Bootstrap::Perl::Target::Perl->new->generate($mop);
for my $cand (values %$emitted) {
    next unless $cand =~ /class Chalk::MOP::Class/;
    open my $out, '>:utf8', 't/fixtures/codegen-goldens/Chalk__MOP__Class.pl.golden' or die;
    print $out $cand;
    close $out;
    print "wrote golden (", length($cand), " bytes)\n";
    last;
}
```

```bash
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib -It/bootstrap/lib /tmp/regen_mop_class_golden.pl
rm /tmp/regen_mop_class_golden.pl
```

- [ ] **Step 2: Verify byte-compat test passes.**

```bash
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/mop/codegen-byte-compat.t 2>&1 | tail -5
```

Expected: 19/19 — the only golden change is `Chalk__MOP__Class.pl.golden`; all other goldens still match.

- [ ] **Step 3: Confirm full regression suite.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
for t in t/bootstrap/mop/*.t t/bootstrap/bnf-target-c.t t/bootstrap/xs-isa-inheritance.t t/bootstrap/xs-athx-no-args.t; do
    echo "=== $t ==="
    $PERL -Ilib "$t" 2>&1 | tail -3
done
```

Expected: all green at baseline counts.

- [ ] **Step 4: Stage and commit Commit 3.**

```bash
cd /home/perigrin/dev/chalk/.claude/worktrees/pu
git status
git add -A
git status
git commit -m "$(cat <<'EOF'
refactor(scope): delete Scope.control; rename Chalk::Bootstrap::Scope to Bindings

Scope.control field deleted; with_control method removed; the
Scope class is now purely about variable bindings. Renamed to
Chalk::Bootstrap::Bindings (and Chalk::Bootstrap::Scope::Sentinel
to Chalk::Bootstrap::Bindings::Sentinel) so the name matches the
contract.

Touched files:
- lib/Chalk/Bootstrap/Scope.pm → lib/Chalk/Bootstrap/Bindings.pm
  (file renamed; control field/method deleted; constructor calls
  updated)
- lib/Chalk/Bootstrap/Scope/Sentinel.pm →
  lib/Chalk/Bootstrap/Bindings/Sentinel.pm
- lib/Chalk/Bootstrap/Context.pm — $scope field renamed to
  $bindings; scope() kept as one-commit deprecation alias
  (deleted in C5); cfg_state's $node->scope reads now read
  $node->bindings
- lib/Chalk/Bootstrap/Semiring/SemanticAction.pm — import
  updated; _one_ctx no longer chains with_control (control_head
  is set on the Context directly per C1); sync-invariant assert
  in _complete_sa deleted (no more dual paths)
- lib/Chalk/MOP/Class.pm — $scope field renamed to $bindings;
  use line updated. Pre-flight grep confirmed no production
  consumer; the field was Phase 7c-prep forward infrastructure.
- lib/Chalk/Bootstrap/Perl/Actions.pm — _ctx_control helper
  deleted; 11 call sites inlined to $ctx->control_head;
  line 211 with_control in _resolve_from_scope deleted (was
  propagating control through bindings-rebuilding, dead post-divorce)
- t/bootstrap/scope.t → t/bootstrap/bindings.t (renamed; class
  references updated; control-related test cases deleted)
- t/bootstrap/scope-threading.t — imports updated
- t/bootstrap/cfg-try-catch.t — imports updated; Context
  construction uses control_head directly
- t/fixtures/codegen-goldens/Chalk__MOP__Class.pl.golden —
  regenerated (mirrors 7c-prep's golden regen pattern)

Behavior unchanged: all baselines preserved at their post-C2
counts; pre-existing failures preserved.

Design: docs/plans/2026-05-26-scope-control-divorce-design.md
EOF
)"
git log --oneline -1
```

---

## COMMIT 4 — Retire Block's control-chain rebuild

> **BLOCKED — premise invalidated by the Task 4.1 audit (2026-05-31).**
>
> The Task 4.1 instrumentation was run across the Block-exercising suite
> (bnf-target-c, mop/parse-integration, mop/codegen-byte-compat,
> c-emit-helpers-inheritance, build-graph-control-chain/loop-phi/ifelse-phi,
> cfg-statements, cfg-try-catch). It counted three kinds of work, not just
> the plan's single "rewrite branch":
>   - `rewrite_fires` — a control-input rewrite actually changed a VarDecl/
>     Return/Unwind node (the C2 sibling-propagation claim is false if >0)
>   - `merge_adds`    — `$graph->merge($s)` added a Call-family node not
>     already in the graph
>   - `ctrl_in_sets`  — `set_control_in` changed a Call-family/If/Loop node
>
> Of 46 blocks that ran the rebuild: **22 had rewrite_fires>0, 29 had
> merge_adds>0, 43 had ctrl_in_sets>0.** The rebuild is heavily
> load-bearing. Per Task 4.1 Step 4, this means STOP — do not delete.
>
> **Why the plan's premise was wrong.** C2 made `control_head` propagate
> sibling-to-sibling through the *semiring multiply* (`_mul_ctx`), carrying
> the *parse-time* control. But the Block rebuild wires the *materialized
> IR-node* effect chain — a different problem. Earley synthesizes actions
> bottom-up: each statement in a StatementList is an independent subtree
> built from `one()` (Start control); siblings merge only at the parent
> rule, *after* both have completed. So when statement N+1's action runs,
> statement N's materialized IR node does not yet exist — the action falls
> back to `$ctx->control_head // make('Start')`, and the rebuild is the
> pass that retroactively wires each node's inputs[0] to its true
> predecessor. `control_head` propagation and the IR-node rebuild solve
> different problems; C2 did not make the rebuild redundant. This is the
> same structural gap documented in the `phase_3a_migration_cross_stmt_scope.md`
> memory note (which recommended the rebuild — "approach 1" — in the first
> place).
>
> **The rebuild cannot be deleted; it can at best be relocated.** The
> control-threading must happen after all sibling nodes materialize, which
> only occurs at the StatementList action (a pure collector today) or the
> Block action (current location). Relocating it is not deletion. True
> redundancy requires the note's approach 2 (SA-instance mutable
> thread-local state — breaks the immutability/determinism design
> principle) or approach 3 (mutable control attribute — diverges from the
> Return/Unwind positional-input convention). Both are invasive
> architectural changes, out of scope for this plan.
>
> **Disposition:** C4 is shelved. C5 does not depend on the rebuild's
> deletion and can proceed independently. If retiring the rebuild becomes
> a goal, it needs its own design brief evaluating approaches 2/3 against
> the immutability principle — not this plan's "it's already redundant"
> framing.

### Task 4.1: Pre-commit instrumentation audit

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (temporary — add a counter inside Block's action; reverted in Task 4.2).

Goal: confirm that the rebuild loop's `refaddr($existing_ctrl) != refaddr($current_control)` branch (line ~1592 area in Actions.pm:1575+) never fires post-C2. If it doesn't, the rebuild is fully redundant and safe to delete.

- [ ] **Step 1: Add a counter to the rebuild loop.**

Edit `lib/Chalk/Bootstrap/Perl/Actions.pm`. Find the rebuild loop inside `Block`'s action (search for `# Control-chain post-processing` comment around line 1575). At the top of the loop body (`for my $i (0..$#stmts) { ... }`), add a counter:

```perl
    # Temporary instrumentation for C4 audit — count rebuild fires.
    my $rebuild_fires = 0;
```

Inside the loop, every time the rebuild branch fires (e.g., `if (!defined $existing_ctrl || refaddr($existing_ctrl) != refaddr($current_control)) { ... }` at line ~1591-1605 area), add `$rebuild_fires++;` before the rebuild itself.

At the end of the Block action, before the `return`, add:

```perl
    if ($rebuild_fires > 0) {
        warn "Block rebuild fired $rebuild_fires times for class/method ...";
    }
```

- [ ] **Step 2: Run the full test suite with the instrumentation.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | grep -c 'Block rebuild fired'
```

Expected: zero warnings if the rebuild is fully redundant. If any warnings fire, that's evidence the rebuild is still load-bearing for those cases — investigate which action paths produce stale-control nodes and fix them upstream BEFORE deleting the rebuild.

- [ ] **Step 3: If the counter shows zero fires, proceed to Task 4.2 (delete the rebuild).**

- [ ] **Step 4: If the counter shows non-zero fires, STOP and surface.** Do NOT delete the rebuild. Investigate the action paths that produce stale-control nodes; fix them upstream; rerun the counter; only proceed when fires == 0.

- [ ] **Step 5: Whether or not fires == 0, REVERT the instrumentation before Task 4.2.**

Edit Actions.pm to remove the counter and warn. The instrumentation is only for the audit; it doesn't ship.

---

### Task 4.2: Delete the rebuild loop

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (delete ~90 lines starting at the rebuild loop).

**Pre-requisite:** Task 4.1 confirmed zero rebuild fires across the test suite.

- [ ] **Step 1: Identify the exact boundaries of the rebuild loop.**

```bash
grep -nC2 'Control-chain post-processing' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Actions.pm
```

Expected: the comment is around line 1575. The loop starts shortly after and ends before the Block action's return statement (around line 1666 area). Read carefully to find the exact end.

- [ ] **Step 2: Delete the rebuild loop.**

The block to delete includes:
- The `# Control-chain post-processing` comment (lines ~1575-1582).
- The `my $start = $graph->start() // $factory->make('Start');` line.
- The `$graph->merge($start);` line.
- The `my $current_control = $start;` line.
- The `for my $i (0..$#stmts) { ... }` loop with all its inner per-stmt-type branches.

What stays:
- The setup BEFORE the rebuild (computing `$type`, `$graph`, etc.).
- The Block IR node construction AFTER the rebuild.

If unclear, read 50 lines of context. The loop is a contained "for $i" block; the rebuild was a post-pass.

- [ ] **Step 3: Confirm tests pass.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/codegen-byte-compat.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -3
```

Expected: all green at baseline counts. If anything regresses, the rebuild was load-bearing for some path the instrumentation missed — restore the rebuild, investigate, fix upstream, retry.

- [ ] **Step 4: Commit.**

```bash
cd /home/perigrin/dev/chalk/.claude/worktrees/pu
git add lib/Chalk/Bootstrap/Perl/Actions.pm
git status
git commit -m "$(cat <<'EOF'
refactor(actions): retire Block's control-chain rebuild

Block's action contained a ~90-line post-hoc control-chain rebuild
that rewired side-effect nodes' inputs[0] (and in some cases
replaced them via unmerge/merge for hash-cons identity) so each
side-effect pointed at its predecessor in source order. The
rebuild existed because Scope.control didn't propagate
sibling-to-sibling within a StatementList — _merge_scope only
fired at the parent rule's multiply, too late for the second
statement's action to see the first statement's effect.

After Commit 2 of the scope/control divorce, control_head
propagates sibling-to-sibling at parse time via _mul_ctx's
"right wins unless undef" rule. The second statement's action
now sees the first statement's effect as $ctx->control_head when
it materializes its side-effect node. The post-hoc rebuild is
redundant.

Pre-commit audit (Task 4.1 instrumentation): counter on the
rebuild's "needs-fixup" branch reported zero fires across
bnf-target-c.t (178 tests). Confirmed the rebuild is fully
dead post-Commit-2 and safe to delete.

Design: docs/plans/2026-05-26-scope-control-divorce-design.md
EOF
)"
git log --oneline -1
```

---

## COMMIT 5 — Block publishes pre-Block bindings; retire 6 cond_leaf workarounds

### Task 5.1: Add `update_bindings` to SemanticAction

**Files:**
- Modify: `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`.

**Naming decision:** Per the spec, `update_scope` was the existing API. After C3, "scope" was bindings-only, so `update_scope` was honest. For C5, the design recommends `update_bindings` for precision. The migration: add `update_bindings` as the new canonical name; keep `update_scope` as a deprecation alias.

- [ ] **Step 1: Add `update_bindings` method.**

Find the existing `update_scope` method definition. Immediately after it, add:

```perl
    # Request a bindings update from within an action method.
    # Same mechanism as update_scope; new canonical name reflects
    # post-divorce semantic (scope was renamed to bindings in C3).
    method update_bindings($bindings) {
        $_pending_scope_update = $bindings;  # reuse the same pending slot
        return;
    }
```

(We could rename `$_pending_scope_update` to `$_pending_bindings_update` for consistency — but doing so requires updating `_complete_sa`'s apply block too. Decision: leave the internal slot named `$_pending_scope_update` for now; it's an internal name. Future cleanup can rename if desired.)

**Important behavioral note:** `update_bindings` and `update_scope` share the same pending slot. Calling both within a single action's execution silently clobbers the first — last writer wins. This is fine because post-C3 the two methods refer to the same concept (bindings = the renamed scope); they are aliases via shared storage. No action should call both. If a future need for separate semantics emerges, rename the slot first.

- [ ] **Step 2: Confirm tests pass.**

```bash
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
```

Expected: 178/178. No consumer calls `update_bindings` yet.

- [ ] **Step 3: Do NOT commit yet.**

---

### Task 5.2: Update Block's action to publish pre-Block bindings

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (Block action, line 1508+).

- [ ] **Step 1: Identify where to insert the publish.**

Find Block's action. After all its existing logic (after the `return $block_ir_node;` line), there's nothing — but the publish needs to happen BEFORE the return. Find the line just before the final `return`.

- [ ] **Step 2: Add the leftmost-leaf walk and `update_bindings` call.**

Insert just before the final `return` statement in Block's action:

```perl
    # Suppress inner my-declarations from leaking to enclosing scope.
    # Recover the pre-Block bindings by walking to the leftmost leaf
    # of $ctx — for Block ::= "{" StatementList "}", that's the "{"
    # scan leaf whose bindings predates StatementList.
    my $pre_block_bindings;
    {
        my $n = $ctx;
        while (defined $n && $n->children->@* > 0) {
            $n = $n->children->[0];
        }
        $pre_block_bindings = $n->bindings if defined $n;
    }
    if (defined $pre_block_bindings) {
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance;
        $sa->update_bindings($pre_block_bindings) if $sa;
    }
```

- [ ] **Step 3: Confirm tests pass.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -3
```

Expected: still green. Block now publishes pre-Block bindings; the 6 cond_leaf workarounds still capture leaves but also work; both paths produce the same result.

- [ ] **Step 4: Do NOT commit yet.** Task 5.3 retires the workarounds.

---

### Task 5.3: Retire the 6 cond_leaf workaround sites

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (6 sites).

For each of the 6 sites, the pattern is:
- Capture `$cond_leaf` during a `_collect_ir_leaves` walk.
- Read `_ctx_scope($cond_leaf)` (now `$cond_leaf->bindings`) for pre-rule scope.

After Task 5.2, `$ctx->bindings` IS pre-rule bindings (because Block published it). So `_ctx_scope($cond_leaf)` reads can become `$ctx->bindings` reads, and the leaf-captures can be deleted.

**For TryCatchStatement and ElsifChain** (which read `_ctx_scope($ctx)` directly, not via captured leaf): the read is already against `$ctx`, but the value was wrong pre-fix. Now it's right. **Verify the call site behaves correctly** — no code change needed, just confirm tests still pass.

- [ ] **Step 1: IfStatement (lines ~2548 + ~2625).**

Find:
```bash
sed -n '2540,2650p' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Actions.pm
```

Around line 2548: `my $cond_leaf;` and `$cond_leaf = $leaf;` capture lines.

Delete the capture. Then around line 2625-2629:

Before:
```perl
                my $pre_scope;
                if (defined $cond_leaf) {
                    $pre_scope = _ctx_scope($cond_leaf);
                }
                $pre_scope //= $scope;
```

After:
```perl
                my $pre_scope = $ctx->bindings;
                $pre_scope //= $scope;
```

(Or simply `my $pre_scope = $ctx->bindings // $scope;` if cleaner.)

- [ ] **Step 2: ElsifChain (line ~2741).**

```bash
sed -n '2735,2780p' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Actions.pm
```

This site reads `_ctx_scope($ctx)` directly. After Task 5.2, `$ctx->bindings` is pre-rule. The existing `_ctx_scope($ctx)` reads `$ctx->bindings`. **Verify it produces correct behavior; no code change required.**

If `_ctx_scope` helper still exists (it was deleted in Commit 3 Task 3.3 Step 5 — confirm), replace with `$ctx->bindings`. If already deleted, the call site is using the inlined form.

- [ ] **Step 3: WhileStatement (lines ~2788 + ~2834).**

Same pattern as IfStatement. Delete `$cond_leaf` capture; replace `_ctx_scope($cond_leaf)` with `$ctx->bindings`.

- [ ] **Step 4: ForStatement (lines ~2935 + ~2984).**

Same pattern.

- [ ] **Step 5: ForeachStatement (line ~3128).**

Same pattern.

- [ ] **Step 6: TryCatchStatement (line ~1131).**

Same as ElsifChain — already reads via `$ctx`. Verify correct behavior post-fix.

- [ ] **Step 7: Confirm tests pass.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/codegen-byte-compat.t 2>&1 | tail -3
```

Expected: all green at baseline counts.

If anything fails:
- For IfStatement/While/For/Foreach: re-run with the cond_leaf captures restored; if it passes then, the issue is in the pre_scope migration (probably an edge case where $ctx->bindings doesn't match what cond_leaf had).
- For ElsifChain/TryCatchStatement: those were reading $ctx directly all along; if they fail post-fix but passed pre-fix, the fix changed what $ctx->bindings returns — that's the architectural change at work. Decide whether the new behavior is correct (it should be, per Perl's lexical scoping) and update the test if needed.

- [ ] **Step 8: Do NOT commit yet.** The new regression test + Context::scope() deprecation shim removal come next.

---

### Task 5.4: Create scope-hygiene regression test

**Files:**
- Create: `t/bootstrap/scope-hygiene-block.t`.

- [ ] **Step 1: Write the test.**

Create `t/bootstrap/scope-hygiene-block.t`:

```perl
# ABOUTME: Phase scope/control divorce C5 — verifies Block's pre-Block bindings publication.
# ABOUTME: Inner my doesn't leak; outer my still visible inside; nested Block; empty Block.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(parse_perl_source);

# Test 1: inner my doesn't leak past the Block.
{
    my $src = q{
        class A {
            method m($self) {
                if (1) {
                    my $x = 2;
                }
                return $x;
            }
        }
    };
    my $mop = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
    my ($ir, $sa, $ctx) = parse_perl_source($src);
    ok(defined $ctx, 'inner-my source parses');
    # The exact assertion depends on what the resolver produces when $x
    # is not in scope at "return $x". Either an unresolved Constant or a
    # Phi sentinel; either way, NOT a VarDecl referencing the inner my.
    # The test serves as a regression guard regardless of which.
}

# Test 2: outer my IS visible inside Block (must not over-suppress).
{
    my $src = q{
        class B {
            method m($self) {
                my $x = 2;
                if (1) {
                    my $y = $x;
                }
            }
        }
    };
    my $mop = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
    my ($ir, $sa, $ctx) = parse_perl_source($src);
    ok(defined $ctx, 'outer-my source parses');
    # The inner $y = $x assignment must resolve $x to the outer VarDecl.
    # If over-suppression happened, $x would be unresolved.
}

# Test 3: empty Block edge case.
{
    my $src = q{
        class C {
            method m($self) {
                if (1) { }
                return 1;
            }
        }
    };
    my $mop = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
    my ($ir, $sa, $ctx) = parse_perl_source($src);
    ok(defined $ctx, 'empty Block source parses');
}

# Test 4: nested Block.
{
    my $src = q{
        class D {
            method m($self) {
                if (1) {
                    my $y = 1;
                    if ($y) {
                        my $z = 2;
                    }
                }
            }
        }
    };
    my $mop = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
    my ($ir, $sa, $ctx) = parse_perl_source($src);
    ok(defined $ctx, 'nested Block source parses');
    # The middle layer can see $y; the outer cannot see $z; the inner-inner
    # can see $y.
}

done_testing();
```

- [ ] **Step 2: Run the test.**

```bash
/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/scope-hygiene-block.t 2>&1 | tail -10
```

Expected: 4/4 PASS. The assertions are lightweight — they confirm parsing succeeds, not detailed IR shape. The strong gate for "Block hygiene works" is `bnf-target-c.t` continuing to be 178/178.

- [ ] **Step 3: Do NOT commit yet.** Final cleanup is next.

---

### Task 5.5: Delete Context::scope() deprecation shim

**Files:**
- Modify: `lib/Chalk/Bootstrap/Context.pm` (delete the shim method added in Task 3.3 Step 4).

- [ ] **Step 1: Confirm no remaining callers use `$ctx->scope`.**

```bash
grep -rn '\$ctx->scope\b\|\$node->scope\b\|\->scope\(\)' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib /home/perigrin/dev/chalk/.claude/worktrees/pu/t /home/perigrin/dev/chalk/.claude/worktrees/pu/script 2>/dev/null | head -30
```

If any matches outside of the deprecation shim itself, migrate them to `->bindings` before deleting the shim. If none, proceed.

- [ ] **Step 2: Delete the shim method.**

Edit `lib/Chalk/Bootstrap/Context.pm`. Find the shim:

```perl
    # Deprecation shim for scope/control divorce C3.
    method scope() { return $bindings; }
```

Delete the method. Update the `extend` method to remove the `exists $opts{scope}` arm:

Before (from Task 3.3 Step 4):
```perl
            bindings    => (exists $opts{bindings} ? $opts{bindings} : (exists $opts{scope} ? $opts{scope} : $bindings)),
```

After:
```perl
            bindings    => (exists $opts{bindings} ? $opts{bindings} : $bindings),
```

- [ ] **Step 3: Confirm tests pass.**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/mop/parse-integration.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -3
```

Expected: all green at baseline counts.

If anything fails with `Can't locate object method "scope"`, the grep in Step 1 missed a caller. Find it and migrate.

- [ ] **Step 4: Stage and commit Commit 5.**

```bash
cd /home/perigrin/dev/chalk/.claude/worktrees/pu
git status
git add lib/Chalk/Bootstrap/Perl/Actions.pm \
        lib/Chalk/Bootstrap/Semiring/SemanticAction.pm \
        lib/Chalk/Bootstrap/Context.pm \
        t/bootstrap/scope-hygiene-block.t
git status
git commit -m "$(cat <<'EOF'
feat(actions): Block publishes pre-Block bindings; retire 6 cond_leaf workarounds

Block's action now explicitly publishes pre-Block bindings via
update_bindings before returning. Pre-Block bindings are recovered
by walking the leftmost leaf of $ctx — for Block ::= "{"
StatementList "}", that's the "{" scan leaf whose bindings
predates StatementList.

With Block publishing pre-Block bindings, the 6 cond_leaf
workaround sites in Actions.pm can read $ctx->bindings directly
without leaf-walking:

- IfStatement (lines 2548 + 2625): cond_leaf capture deleted;
  pre_scope reads $ctx->bindings.
- ElsifChain (line 2741): already reads $ctx->bindings directly
  via the helper; now produces correct results.
- WhileStatement (lines 2788 + 2834): same pattern as IfStatement.
- ForStatement (lines 2935 + 2984): same pattern.
- ForeachStatement (line 3128): same pattern.
- TryCatchStatement (line 1131): already reads $ctx->bindings
  directly; now produces correct results.

SemanticAction adds update_bindings($bindings) as the new
canonical method name (update_scope kept as deprecation alias).
The internal $_pending_scope_update slot keeps its name.

Context::scope() deprecation shim from C3 deleted. extend()'s
opts handling drops the {scope} arm. Callers use ->bindings.

New test: t/bootstrap/scope-hygiene-block.t covers inner-my-
doesn't-leak, outer-my-visible-inside, empty Block, nested Block.

Test gates: bnf-target-c.t 178/178; mop/*.t green at baseline;
xs-isa-inheritance.t 10/10; xs-athx-no-args.t 7/7. Pre-existing
failures preserved: xs-polymorphic-dispatch.t 59/60,
xs-int-specialization.t 2/6.

Design: docs/plans/2026-05-26-scope-control-divorce-design.md
EOF
)"
git log --oneline -1
```

---

## Final acceptance checks (post all 5 commits)

- [ ] **All five commits land** on `fixup-audit-baseline`:

```bash
git log --oneline -5
```

Expected: top 5 commits are the C1-C5 series.

- [ ] **All baseline test gates pass at expected counts:**

```bash
PERL=/home/perigrin/.local/share/pvm/versions/5.42.0/bin/perl
for t in t/bootstrap/mop/codegen-byte-compat.t \
         t/bootstrap/mop/class-scope-vars.t \
         t/bootstrap/mop/use-constants.t \
         t/bootstrap/mop/parse-integration.t \
         t/bootstrap/mop/parse-threading.t \
         t/bootstrap/mop/ctx-mop-propagation.t \
         t/bootstrap/mop/field-helpers.t \
         t/bootstrap/mop/test-pipeline-helper.t \
         t/bootstrap/c-emit-helpers-inheritance.t \
         t/bootstrap/bnf-target-c.t \
         t/bootstrap/xs-isa-inheritance.t \
         t/bootstrap/xs-athx-no-args.t \
         t/bootstrap/bindings.t \
         t/bootstrap/scope-threading.t \
         t/bootstrap/cfg-try-catch.t \
         t/bootstrap/c-repair-coverage.t \
         t/bootstrap/c-schedule-walker.t \
         t/bootstrap/c-analysis-helpers-schedule.t \
         t/bootstrap/c-simple-body-shortcuts.t \
         t/bootstrap/c-sub-state-leak.t \
         t/bootstrap/c-schedule-tail-control.t \
         t/bootstrap/context-control-head.t \
         t/bootstrap/scope-hygiene-block.t; do
    echo "=== $t ==="
    $PERL -Ilib "$t" 2>&1 | tail -3
done
```

- [ ] **Working tree clean.**

```bash
git status
```

- [ ] **`Chalk::Bootstrap::Scope` no longer exists.**

```bash
ls /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Scope.pm 2>&1
grep -rn 'Chalk::Bootstrap::Scope' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib /home/perigrin/dev/chalk/.claude/worktrees/pu/t /home/perigrin/dev/chalk/.claude/worktrees/pu/script 2>/dev/null | grep -v '\.golden' | head -5
```

Expected: file does not exist; grep returns zero matches (except possibly in goldens, which are regenerated text).

- [ ] **`cond_leaf` workarounds gone.**

```bash
grep -nE 'cond_leaf|body_leaf' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Actions.pm | head
```

Expected: zero matches.

- [ ] **Block's control-chain rebuild gone.**

```bash
grep -nE 'Control-chain post-processing' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Actions.pm
```

Expected: zero matches.

- [ ] **Branch NOT pushed** (per project hard constraint on this branch).

If all checks pass, the scope/control divorce is complete. Next phases: TI pruning revision (separate brainstorm; see `ti_over_pruning_block_type.md` memory note), Phase 7e (TestXSHelpers migration), Phase 7g (cfg_lookup infrastructure deletion).
