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
