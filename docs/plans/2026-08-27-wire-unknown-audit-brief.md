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
