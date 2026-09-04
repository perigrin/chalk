# Narrowing reaches 85%, and the third constraint source was the missing one

**Date:** 2026-09-04
**Status:** MEASURED. Reproduce: `scratchpad/reach.pl`.
**Producer pin:** perl5-son `b96087c`. Gate: 224.

## The number

Across all 255 loadable corpus programs, over the 54 `Num`-stamped nodes:

| | pinned | residue |
|---|---|---|
| direct observation only | 36 (67%) | 18 |
| + propagation to a fixpoint | **46 (85%)** | **8** |

The 8 that stay unreached: `Coerce` 5, `Subscript` 2, `Constant` 1.

## Three constraint sources, not one

The narrowing design named observations at use sites. Measuring found three,
and the third is the largest single contributor:

**(a) A consumer states a requirement.** `observed_operand_repr` (commit
`5d200154`) — `Divide`/`Add`/`Subtract`/`Multiply`/`Power` want `Num`, `Modulo`
wants `Int`. 11 nodes.

**(b) A literal is its own constraint.** A fractional `Constant` — `0.1`,
`1.5`, `2.5`, `0.75` — can only be a `double`. Nothing needs to observe it. 15
nodes.

**(c) EVERY value input is already `Int`.** 16 nodes, and this one was missed
entirely in the first pass. It is also the STRONGEST of the three: the inputs
*prove* `i64` rather than merely failing to contradict it.

Source (c) was found by looking at what the residue actually contained rather
than assuming it needed more propagation. BEFORE source (c) the residue was 18,
and its largest group was 8 `Assign` nodes, all of the shape:

    Assign inputs=[FieldAccess:Int, Add:Int] consumers=[Return]

Stamped `Num`, with every input `Int`. Propagation could never reach them
because it walks `Num`-to-`Num` edges and their neighbours are not `Num` at
all. The answer was never propagation — `i64` is directly derivable from the
inputs.

**That is the 2^53 miscompile's own shape**, incidentally: a node stamped `Num`
whose inputs are integral, where `%_REPR_LLVM_TYPE` forces `double` and the
mantissa cannot hold the value.

## Why 85% is the number that justifies the pass

Earlier readings and why they were wrong:

- **0%** — before any observation existed.
- **7%** — after publishing `Divide` through the coercion authority. Real but
  tiny.
- **13%** — after publishing the whole arithmetic family there. CONFOUNDED:
  publishing changed the population (54 -> 215 nodes) because that table mints
  `Coerce` nodes. Reverted; it took the gate 224 -> 184.
- **48%** — via the read-only `observed_operand_repr`, population back to 54.
  Honest, but direct observations only.
- **85%** — all three sources plus propagation. Population still 54.

The population holding at 54 across the last two is what makes them
comparable. The 13% reading measured a graph the measurement itself had
changed.

## What the residue is

8 nodes: `Coerce` 5, `Subscript` 2, `Constant` 1.

**The `Coerce` cases were looked at, and they are not all alike:**

    Coerce from=Int to=Num  inputs=[Constant:Int]     <- the 2^53 shape
    Coerce from=Int to=Num  inputs=[Constant:Int]
    Coerce from=Str to=Num  inputs=[Constant:Str]
    Coerce from=Str to=Num  inputs=[Constant:Str]
    ... (Str->Num predominating)

The `Str -> Num` ones are genuinely outside source (c): their input is a `Str`,
so "every value input is Int" is false and SHOULD be. A string numifies to
whatever it parses as, which is not statically an integer — `"3.9x"` is 3.9.
Defaulting is the right answer there.

The `Int -> Num` ones are the interesting pair: **that is precisely the 2^53
miscompile's shape** (`my $n = 9007199254740993; my $s = $n + 0.0` produces
`Coerce(Int -> Num)` and the sitofp loses the value). Source (c) should pin
them — their only value input is an `Int` constant — and this probe did not.
Both `Coerce` and `Constant` are `Chalk::IR::Value`, so the class filter is not
the cause; the probe's reach rule is. NOT diagnosed further, and it is the
first thing to check when building the real pass, because these two nodes are
the bug this whole line of work exists to fix.

`Subscript` reads an aggregate element, where the element type is the
aggregate's business. `Constant` at 1 is an integral literal that nothing
observes — the genuine defaulting case, and `i64` is the honest answer for it
(perl keeps a literal as an IV until something makes it an NV).

## What to build

Confirmed by this measurement, unchanged from
`2026-09-04-t2-narrowing-the-design.md`:

1. collect from all THREE sources
2. propagate to a fixpoint (terminates on set size; sets only shrink)
3. default the residue, as a named rule with its reason recorded

Plus the three fences: a conflict (`{}`) GAPs loudly and never silently picks;
defaulting is a named rule, not `$candidates->[0]`; `_candidates` is the only
place sets are constructed.

## Not established

- Why source (c) does not pin the two `Coerce(Int -> Num)` nodes whose only
  value input is an `Int` constant. Established that the class filter is not
  the cause; the reach rule is the suspect. These are the 2^53 shape, so this
  is the highest-value item in the residue.
- Whether the propagation rule used here (a node is reachable if ANY neighbour
  is pinned) is the right one. It measures REACH, not agreement — a real solver
  must intersect and can find `{}`, which this probe cannot.
- What happens on conflict in practice. No conflicting pair was constructed;
  the probe never intersects.
