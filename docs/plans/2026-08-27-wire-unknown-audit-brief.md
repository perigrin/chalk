# Brief: why does the wire carry `Unknown`? (perl5-son workstream)

**Date:** 2026-08-27
**Status:** BRIEF for a separate session, in the PRODUCER repo (`~/dev/perl5-son`).
**Origin:** perigrin, 2026-08-27 — "there's no reason why the wire should be
carrying Unknowns … we're not doing anything new / different on the backend that
couldn't be done by B::SoN".
**Filed as:** plan §5.0b of `docs/plans/2026-08-26-t1-architecture-plan.md`.

## The claim

**233 `Unknown` stamps on the wire is a FRONTEND defect, not a fact of life.**
B::SoN walks a real optree with real SV types in hand. Nothing chalk's backend
does with those types could not have been determined at the producer. An
`Unknown` on the wire is the producer declining to answer a question it was
holding the evidence for.

## Measured, at chalk HEAD `5a1f1e27`, 231 corpus cases

| where | absent | Unknown |
|---|---|---|
| on the wire (producer output) | 0 | **233** |
| after `from_json` | 23 | 0 |

The producer is internally consistent — it never emits an absence, always a
stamp. The `233 → 0` collapse is a CHALK-side defect (plan §5.0): the loader's
`%LOWERABLE_STAMP` omits `Unknown`, so every wire `Unknown` is written into the
graph as an ABSENCE. **That is being fixed separately and does not block this.**

Reusable measurement script, already written and working:
`scratchpad/t1-measure/absent-and-unknown.pl` (chalk worktree). It classifies
Value-ness from the loaded node and asserts op→Value-ness is a function before
counting, so wire-side and post-load counts use the same population.

## The work

1. **Census the 233 by op and by CAUSE.** Not just which ops — *why* each
   declined. Distinguish:
   - the optree genuinely does not know (runtime-polymorphic, `eval "$str"`,
     `$obj->$name()`) — legitimately `Unknown`, and spec §4 says an
     un-typeable construct is an un-lowerable one;
   - the optree knows and the producer did not ask — **the target**;
   - the producer asked and the answer was dropped by a bare `eval` or a
     silent-skip path (this has happened three times already; see chalk
     `docs/specs/2026-08-26-t1-derivation.md` "Producer bugs found by accident").
2. **Close the second category.** Each fix is a producer change with a
   producer-side test.
3. **Re-measure.** The number that matters is wire-`Unknown` count over the same
   231 cases.

## Do NOT

- Do not touch chalk's loader from that session — §5.0 owns it, and concurrent
  edits to `Serialize/JSON.pm` will collide.
- **Do not run chalk's corpus gate.** It reads the producer as a LIVE filesystem
  path with NO version pin, so a producer edit mid-run contaminates it. Chalk's
  coordinator runs the gate; producer work must be serialized against it.
- Do not `git zhi` or touch `refs/zhi/*` (chalk memory: a fetch-prune wiped a
  chain once).

## Why both halves are needed

They fail in different directions. **Producer only:** chalk still TRUSTS its
input, so the next producer regression silently drops stamps again — the exact
defect class that produced this phase. **Boundary only (§5.0):** the 233 real
`Unknown`s become loud GAPs — honest, but not compiling.

Together: the producer answers what it can, the boundary refuses what it cannot
rather than guessing. And §5.0's GAP-shaped refusal is what makes this
workstream's remaining cases VISIBLE — today they are dropped silently.

## Environment

- perl5-son at `~/dev/perl5-son`, branch `pu`. ASCII-only source.
- Perl 5.42.0 at `$HOME/.local/share/pvm/versions/5.42.0/bin/perl` (pvm, NOT plenv).
- Suites need `prove -Ilib -Iblib/lib -j1` on a CLEAN build (stale `blib` masks
  deletions); a SINGLE test is fine with just `-Ilib`.
- `ag` has NO `-q` flag.

---

## RESULT, round 1 (bson session, producer `bf2b039`, 2026-08-27)

**Wire `Unknown` 233 -> 195.** Chalk gate re-run by the coordinator against that
producer: **215/215/215/215, 241/241, 0 failures** — chalk-neutral, no movement
in either direction. The pin is now `bf2b039`, not `714ec0e`.

**The premise HELD, and by a wide margin.** The brief said explicitly that if
most of the 233 landed in bucket one, the premise was wrong and that was the
finding. It did not:

| bucket | count | share |
|---|---|---|
| one — optree genuinely cannot know | ~15 | ~6% |
| two — optree knows, producer never asked | ~200 | ~86% |
| three — asked, then dropped | 0 confirmed | — |

**Two structural findings worth more than the headline:**

1. **87 of 233 (37%) are pure CASCADES** — Unknown fully explained by an Unknown
   input (Assign 28, Add 18, Subscript 17, Phi 16, Multiply 4, Call 2,
   Subtract 1, TernaryExpr 1). The corpus never had 233 independent decisions;
   it had **146 roots**. Fixing a root collapses its cascade for free — which is
   why closing FieldAccess 21->6 also bought Call 60->37.
2. **ZERO runtime-polymorphic dispatch in the whole corpus** — no
   `$obj->$name()`, no `eval "$str"`. That was the premise's biggest risk and it
   did not materialise. Bucket one is the `Array[Scalar]` element-type wall
   (`my ($a,$b) = @_` binds a whole list, so element types need the callsite —
   the producer's own comment at `FromOptree.pm:4771` already said so).

**The sharpest instance, and why §5.0 is its twin:** `return_type: "Int"` sits on
the sub record while the Call node **in the same JSON document** reads stamp
`"Unknown"`. The producer computed the answer and discarded it at the last step.
That is the same defect shape as §5.0 one layer down — chalk's
`%LOWERABLE_STAMP` omits `Unknown`, so every `Unknown` the producer *does* send
arrives at the graph as an ABSENCE. **Two independent throw-aways of the same
information, at two different levels**, which is precisely why the belt-and-
suspenders framing was right.

**Landed in `bf2b039`:** items 1 and 3 (Call return type, FieldAccess), which
interlock through a dependency chain — field type -> FieldAccess stamp -> method
return type -> Call stamp — so method return types are re-derived between the two
stamping passes. Only propagates, never invents: negative subtests (undetermined
callee, recursive call, field with no default) passed before the fix and still
pass, so a blanket stamp could not have satisfied them.

**Still open:** Subscript (27 + 17 cascade), Phi join (19 + 16), PadAccess (10),
self-typed leftovers (11).

**Chalk-side note recorded here because it changes what §5.0 must do:**
`Target/LLVM.pm:80` `_require_repr` refuses **only `undef`** — it would pass
`'Unknown'` straight through to lowering. So §5.0 has two halves: the loader
stops filtering AND the boundary learns to refuse `Unknown`. Removing the filter
alone converts a silent DROP into a silent GARBAGE ENCODE, which is strictly
worse.
