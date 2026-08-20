# The "statement modifier" GAP is really a nested ONE-ARMED if. Measured.

**Date:** 2026-08-20
**Status:** MEASURED, not fixed. No code changed.
**Found by:** probing the `deep3` case left open by
`docs/plans/2026-08-20-mixed-effect-refusal-lifted.md`.

## The finding

`deep3` GAPped with:

    GAP: statement modifier with a void effect / element store / die
         inside an if/else arm not yet lowered

The probe contains **no statement modifier** — it is three plain nested `if`
blocks. The message names the shape the refusal was written for, not the shape
that reaches it.

## It is not about depth

| shape | depth | result |
|---|---|---|
| `if { print; $n=7 }` | 1 | **MATCH** |
| `if { if { print; $n=7 } }` | 2 | **GAP** |
| `if { if { if { print; $n=7 } } }` | 3 | **GAP** |
| `if { if { $n=7 } }` (rebind only) | 2 | **MATCH** |
| `if { if { if { $n=7 } } }` (rebind only) | 3 | **MATCH** |
| `if { if { print } }` (print only) | 2 | **GAP** |
| `if { if { if/ELSE { print; $n } } }` | 3 | **MATCH** |

Depth 3 with an `else` passes. Depth 2 without one fails. **The discriminator is
one-armed-ness plus a void effect, not nesting depth.**

## Why, at the optree

Perl compiles a one-armed `if` and a statement modifier to the SAME op:

    if ($x) { if ($x) { print "a"; $n=1 } else { ... } }
      a  <|> and(other->b)        <- outer if
      e  <|> cond_expr(other->f)  <- inner if/ELSE

    if ($x) { if ($x) { print "a"; $n=1 } }
      a  <|> and(other->b)        <- outer if
      e  <|> and(other->f)        <- inner ONE-ARMED if

`_walk_branch` handles the two differently, twenty lines apart:

- **`cond_expr` (`:4342`)** recurses into `_handle_cond_expr`, which computes
  `$mem_branch` (via `_arm_has_void_call` / `_arm_has_element_store` /
  `_arm_has_die`) and, when set, builds REAL control flow — If/Proj/Region and a
  merge. Void effects lower correctly.
- **`and`/`or` (`:4373`)** takes the statement-modifier path, which merges via
  `TernaryExpr` — a pure value select with NO control flow. A void effect has
  nowhere to be pinned, so it refuses.

**The refusal is sound.** Its comment says so explicitly: a void print on that
path "would walk via `_step`, emit an unpinned Print/Call the guard does not
gate, and the value-only merge would drop or misfire it (a silent effect
miscompile -- lli printed nothing where perl printed `hi`)." This is an UNBUILT
PATH, not an expired premise — unlike the three refusals lifted earlier this
week, which each cited a cause that had since been fixed.

## What the fix would take

Route a void-effect `and`/`or` arm into the same control-flow construction
`_handle_cond_expr` uses, rather than the ternary merge.

The obvious move — call `_handle_cond_expr` directly, as `cond_expr` does at
`:4345` — does NOT work: that function assumes `op->other` and `op->next` are the
TWO ARMS of a branch. For an `and`, `op->other` is the guarded body and
`op->next` is the join. A one-armed branch has an implicit empty false arm. The
shared construction (`$walk_arm`, `$join_addr`, `$base_depth`, `:4077-4080`) is
local to `_handle_cond_expr` and not reachable from `_walk_branch`'s `and`
handler.

So the work is one of:

1. **Extract** the If/Proj/Region construction from `_handle_cond_expr` into a
   helper both handlers call, parameterised by "false arm is empty".
2. **Synthesize** the missing arm at the `and` site and delegate.

(1) is the honest shape and the larger change. Neither is a small edit, which is
why this is recorded rather than attempted at the end of a long arc.

## Blast radius, measured

The GAP fires on a nested branch whose body carries a void effect (print, method
call, element store, or die) and which compiles to a one-armed `and`/`or` rather
than a `cond_expr`. Measured across spellings:

| nested spelling | result |
|---|---|
| `if (...) { ... }` (one-armed) | **GAP** |
| `unless (...) { ... }` | **GAP** |
| `EXPR or (...)` | **GAP** |
| `if (...) {...} elsif (...) { print; $n=7 }` | **GAP** |
| `if (...) {...} else {...}` | MATCH |
| four-deep, every level two-armed | MATCH |

**`elsif` is the one that matters.** It is ordinary code, not a modifier idiom,
and it lands on this path — so the refusal's reach is wider than its message
suggests. Depth is confirmed irrelevant in both directions: a four-deep
two-armed nest passes, a two-deep one-armed nest fails.

Rebind-only bodies are unaffected at any depth or spelling. No corpus case
covers any of the failing shapes today, which is how it stayed invisible.

## What this does NOT establish

- **No miscompile was observed.** The refusal is loud and it holds. This is a
  missing capability, not a wrong answer.
- Depth was swept to 4. Nothing beyond.
- The `die` and element-store legs of the same refusal were not separated from
  the void-call leg; all three share one message and only void-call was varied
  across spellings.

---

## RESOLVED 2026-08-20 (perl5-son 3047f35, chalk 89896216)

Built, not lifted. The refusal was sound; the path is now constructed.

**What was actually needed** — neither of the two options recorded above. The
If/Proj/Region construction did not have to be extracted from
`_handle_cond_expr`, because an equivalent construction already existed in the
MAIN WALK's `&&`/`||` handler (`:378-397`, `:494-534`) for the same op in the
same context, 3900 lines above the refusal. The nested handler mirrors it.

The extraction described in "What the fix would take" was therefore the wrong
plan. Reading both handlers before choosing is what surfaced the third one.

**A second defect, only visible once the first was fixed.** The arm scans
(`_arm_has_void_call`, `_arm_has_die`) bail at a nested branch — correct for
attributing an effect to an arm, wrong for the question "does this arm need
control flow?", which is arm-independent. The outer branch saw no effect and
took the value-merge path while the inner built control flow beneath it, so the
inner guard was swallowed: ONE `If` for two source-level `if`s.

    if ($x) { if ($x) { print "in\n" } }    printed NOTHING
    if ($x) { if ($x) { die "boom\n" } }    exited 0, perl exits 255

Both are silent miscompiles — strictly worse than the GAP they replaced. The
scans now descend for the needs-control-flow question only, sharing ONE seen-set
(a per-call set recursed forever on branchy real code: "Deep recursion on
_arm_has_die", then a Killed process, caught by `t/b-son-backend.t`).

**Two shapes stay refused, deliberately.** Both were found by existing tests
asserting a GAP that had stopped firing, and each was verified behaviourally
before the assertion was touched:

| shape | why it still refuses | measured |
|---|---|---|
| element store | needs the memory-Phi merge this handler does not build | `if($c){if($d){$a[0]=9}} $a[0]` printed 1, perl prints 9 — and BOTH polarities printed the same |
| void call | a Call is both a value and an effect; emitted on both paths | `helper()` printed twice where perl printed once |

**Corrections to this document's own measurements.** The blast-radius table
above lists `EXPR or (...)` and `unless` as GAP; both now lower. The table's
claim that no corpus case covered any failing shape was correct and is now
closed by T16–T20.

**Outcome:** corpus gate 209 → 214, all four legs agreeing, worklist 0.
Producer suite 97 files / 523 tests PASS on a clean build. Twenty bilateral
shapes match perl on stdout and exit status.
