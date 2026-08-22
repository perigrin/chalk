# Two live wrong-output defects in the producer

**Date:** 2026-08-22
**Status:** FILED, both COORDINATOR-VERIFIED. Not fixed.
**Found by:** the B::SoN lattice-coverage audit
(`docs/research/2026-08-22-bson-lattice-coverage.md`), then re-verified
independently by me before filing.

Both produce WRONG OUTPUT with no GAP, which is the one failure class this
project treats as unacceptable. GAP-not-miscompile is the invariant, and these
break it.

---

## Defect 1: a v-string constant decodes as integer 0

**Symptom, measured:**

```perl
my $v = v65.66;
print $v, "\n";        # perl prints "AB"
```

The wire carries `Constant const_type=integer value='0' :Int`. Chalk emits a
zero where the program prints `AB`.

**Mechanism, verified at the SV level:**

    B::class(v1.2.3)  = PVMG
    isa('B::IV')      = TRUE      <- this is the bug
    isa('B::PV')      = true
    ->IV              = 0         <- what the IV arm returns
    ->PV              = 1,2,3     <- what it should return

`SoN::FromOptree::_extract_const` (`lib/SoN/FromOptree.pm:1110`) tests
`$sv->isa('B::IV')` BEFORE `B::PV`. A v-string constant is a **PVMG**, and
`B::PVMG isa B::IV` is true, so the integer arm fires on a POK-only SV and
returns its empty integer slot. The later `B::PVIV`/`B::PVNV` arms do check
flags correctly but are unreachable for PVMG.

**THIS IS A CLASS, NOT ONE MEMBER.** Any PVMG constant takes the same path.
The audit identified regex-capture copies as another instance; there may be
more (dualvars are PVMG, though they arrive by a different route).

**Test-design warning attached to this one.** `print length(v1.2.3)`
ACCIDENTALLY PASSES, because perl constant-folds it before B::SoN sees an SV
at all. A corpus case written that way would report VString GREEN while the
defect is live. Any test must use the v-string's CONTENT.

---

## Defect 2: `write` is silently discarded

**Symptom, measured:**

```perl
format STDOUT =
@<<<
"hi"
.
write;
print "after\n";
```

    perl  : hi\nafter
    chalk : Start, Constant, Constant, Print, Return

One `Print` for `"after\n"`, and NOTHING for `write`. No node, no GAP, no
stderr line. A statement vanishes from the middle of the program while the
statements around it compile normally, so the output looks healthy and is
simply missing a line.

**Mechanism:** `enterwrite` is registered in
`lib/SoN/FromOptree/OpMap.pm:414` as `[0, undef, 0, 0]` — an `undef` node_type
with **no SKIP flag**. So `is_known` returns true, the generic branch at
`FromOptree.pm:2615` runs, `defined $node_type` is false, no node is built, and
the handler returns `'handled'`. Returning 'handled' is what makes the
unknown-op `warn` at `FromOptree.pm:874` unreachable — the op is neither
translated nor reported.

**Blast radius is narrow**, which is why it survived: `warn`, `chdir`, `sleep`,
`syswrite` and `printf` all become `Call` nodes, and `local` GAPs loudly. Only
the Format family elides. But the SHAPE of the bug — a registration whose
`undef` node_type silently means "drop it" — is worth auditing across the whole
OpMap, since any other entry with that shape has the same behaviour.

---

## Why these matter more than the GAP count

The same audit found 13 lowering GAPs, and those are FINE — a GAP is the
compiler correctly refusing what it cannot verify. These two are different in
kind: the compiler proceeds confidently and produces a wrong program.

Defect 2 is the more dangerous of the two, because the failure is INVISIBLE.
Defect 1 at least produces an obviously wrong value; defect 2 produces a
program that runs, exits 0, and is missing a line of output.

## Suggested order

Defect 2 first: the fix is likely a SKIP flag or an explicit GAP on the OpMap
entry, and the audit of other `undef`-node_type entries is the valuable part.

Defect 1 second: reorder the `isa` tests so `B::PV` is checked before `B::IV`,
or better, dispatch on the SV's FLAGS (POK/IOK/NOK) rather than on class
inheritance — the class hierarchy does not mean what the current test assumes.

Both want a corpus case, and per the warning above, the v-string case must
exercise the content rather than a constant-foldable property.
