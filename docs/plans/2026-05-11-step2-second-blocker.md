# Step 2 (Option B1): second blocker — named-unary level needs to be between current Chalk levels 4 and 5

**Status:** Investigation 2026-05-11. `d6d5a195` reverted to `662d169c`.
The "named-unary cannot be a Subscript target" half of `d6d5a195`
worked correctly. The "named-unary slurps tighter-than-L10 operators
in its argument" half had a numeric-level mismatch with Chalk's
PrecedenceTable that caused active regressions.

## What the audit re-run surfaced

Subagent ran `script/chalk-fixup-audit lib/Chalk/IR lib/Chalk/MOP
lib/Chalk/Grammar` after `d6d5a195`. Three files that previously
parsed (105/105 PARSE_OK in the 2026-05-10 baseline) now PARSE_FAIL:

- `lib/Chalk/Grammar/BNF/Actions.pm`
- `lib/Chalk/Grammar/Perl/TypeLibrary.pm`
- `lib/Chalk/IR/Serialize/JSON.pm`

These files contain patterns like:
- `value => defined $node->value ? "x" : undef` (ternary after defined)
- `grep { defined $_ && blessed($_) } @arr` (`&&` after defined)
- Hash-literal entries with `defined ARG_EXPR` in the value position

The new precedence rule greedy-slurped `&&`/`||`/`==`/`?:` into the
named-unary argument, where it should have left them outside.

## Empirical evidence

Probed `defined $a && $b` against perl's optree via B::Concise:

```
=== defined $a && $b ===
3  <#> gvsv[*a] s
4  <1> defined sK/1
5  <|> and(other->6) vK/1
6      <#> gvsv[*b] s
```

Perl parses as `And(Defined($a), $b)`. Chalk before `d6d5a195`:
same shape. Chalk after `d6d5a195`: `Call(defined, [And($a, $b)])`.
Wrong.

Probed `defined $a + 1`:

```
=== defined $a + 1 ===
3  <#> gvsv[*a] s
4  <$> const[IV 1] s
5  <2> add[t2] sK/2
6  <1> defined vK/1
```

Perl parses as `Defined(Add($a, 1))`. Chalk before `d6d5a195`:
`Add(Call(defined, [$a]), 1)` — wrong (this was the pre-existing
bug `d6d5a195` was trying to fix). Chalk after `d6d5a195`:
`Call(defined, [Add($a, 1)])` — correct.

So `d6d5a195` fixed `+`/`*`-after-defined but broke `&&`/`||`/`==`-
after-defined. The two cases differ by operator precedence:
arithmetic (perlop L7-L8) is tighter than named-unary (L10);
comparison and logical (L11-L17) are looser.

## Root cause

Per perlop, named-unary at L10 slurps operands using only operators
tighter than L10. In Chalk's PrecedenceTable:

```
level 0  **           perlop L4   (tighter than L10)
level 1  =~ !~         perlop L6   (tighter than L10)
level 2  * / % x       perlop L7   (tighter than L10)
level 3  + - .         perlop L8   (tighter than L10)
level 4  << >>         perlop L9   (tighter than L10)
                                   <--- named-unary belongs here, perlop L10
level 5  isa           perlop L11  (looser than L10)
level 6  < > <= >= ... perlop L12  (looser than L10)
level 7  == != ...     perlop L13  (looser than L10)
level 8  &             perlop L14  (looser than L10)
level 9  | ^           perlop L15  (looser than L10)
level 10 &&            perlop L16  (looser than L10)
level 11 || // ^^      perlop L17  (looser than L10)
```

`d6d5a195` assigned `named_unary_level() = 50`. That value is
LOOSER than `&&` (10), `||` (11), `==` (7), etc. So when
`_prec_multiply` saw `defined` (level=50) on the left of `&&`
(level=10), it computed `left_level=50 > op_level=10` and rejected
the (correct) parse. The DEBUG_PRECEDENCE trace from a probe
confirmed this directly:

```
PREC_NAMED_UNARY: defined level=50 assoc=nonassoc
PREC_SCAN: left_level=undef op=&& op_level=10
PREC_REJECT_MUL: left_level=50 > op_level=10 (&&)
```

The correct parse — `&&` with named-unary on the left — was the
one rejected.

## Why the wrong number was chosen

The original plan (`docs/plans/2026-05-11-precedence-named-unary-plan.md`)
proposed `named_unary_level = 50` because the existing semiring
treats levels 0-14 as binary operators and levels 100/101 as
ternary/assignment. 50 sat in the gap.

But the gap was a misread: levels 0-14 ARE the binary operators,
and named-unary is among them per perlop. Named-unary is L10,
between perlop L9 (`<<`/`>>` = Chalk level 4) and perlop L11
(`isa` = Chalk level 5). Chalk's numbering is dense in the binary
range; there's no integer slot for L10. 50 was put OUTSIDE the
binary range, which made it looser than every binary op — exactly
the opposite of what perlop requires.

## Design options

### Option A: renumber Chalk's table to leave a gap for L10

Push every level >= 5 up by 1:

```
level 0  **
level 1  =~ !~
level 2  * / % x
level 3  + - .
level 4  << >>
level 5  <-- named-unary
level 6  isa            (was 5)
level 7  < > <= >=      (was 6)
level 8  == != ...      (was 7)
level 9  &              (was 8)
level 10 | ^            (was 9)
level 11 &&             (was 10)
level 12 || // ^^       (was 11)
level 13 .. ...         (was 12)
level 14 and            (was 13)
level 15 or xor         (was 14)
```

Pros: principled, named-unary slots into the right position, all
comparisons work correctly via the existing semiring logic.

Cons: many existing tests and semiring code hard-code level numbers.
Need to grep and update. Higher blast radius:
- `t/bootstrap/semiring-precedence.t` likely asserts specific levels
- `Precedence.pm` has hard-coded checks like `level >= 100` (assignment)
  which still work, and the `EXPR_LEVELS` table is independent of
  binary-op levels, also still works
- Other test files may depend

### Option B: fractional level (`4.5`)

Smallest possible change. `named_unary_level()` returns `4.5`.
Numeric comparisons in Perl handle this natively.

Pros: one-line change, no renumbering. Existing tests untouched.

Cons: hack. "Level 4.5" reads as ad hoc. If we later need another
level slot, more fractions appear. Hash-cons key in `_intern`
includes the level; `4.5` works as a string key, just less pretty.

### Option C: use level=5 and bump `isa`

Assign named-unary to 5, push `isa` to 5.5 or 6. Smaller renumber.

Pros: smaller diff than Option A.

Cons: still requires renumbering, just for fewer ops. Still has the
"4.5 or 5.5" problem.

### Option D: TypeInference approach

Move the named-unary argument constraint into TypeInference. Don't
use a Precedence level at all for the argument-precedence check;
just reject derivations where TI classifies the argument as a
BinaryExpression looser than L10.

Pros: separates concerns — Precedence handles structural-precedence,
TI handles shape-and-semantic constraints. Argument-shape rule
generalizes to other named-token operators if needed.

Cons: TI doesn't currently reject argument shapes by level number;
adding that introduces a new TI rule pattern. The "Precedence
through TypeInference" framing may obscure what's actually a
precedence rule. Also: the "named-unary cannot be a Subscript
target" rule clearly IS Precedence; splitting half of the
named-unary handling across two semirings is awkward.

## Recommendation

**Option B (fractional level=4.5)** as a tactical fix, with a note
that Option A (renumber) is the principled long-term answer. Option B
unblocks Step 2 quickly without ripple effects; Option A can land
as a clean follow-up commit when we have time to update all the
hard-coded level assertions.

Rationale:
- Option B is the smallest reversible change.
- Once Option B is in place and tests pass, Option A becomes a
  mechanical renumbering with the spec tests as the regression
  suite.
- Option D (TypeInference) feels architecturally wrong because the
  rule IS a precedence comparison ("argument level must be < 50"),
  not a shape constraint.

## Implementation sketch for Option B

In `lib/Chalk/Grammar/Perl/PrecedenceTable.pm`:

```perl
sub named_unary_level() { return 4.5; }
```

Re-attempt the full `d6d5a195` change with this. The semiring's
existing operator-level comparisons handle the fractional value
correctly (it's just numeric). The Subscript bracket-boundary
rejection of "level >= 0 named-unary target" works the same.

The four spec tests for L2-vs-L10 should pass without TODO. The
spec tests for L8-vs-L10 (arithmetic) should produce the perlop-
correct shape: `defined $a + 1` → `Defined(Add($a, 1))`. The spec
tests for L13/L16/L17-vs-L10 (comparison/logical) should produce
the perlop-correct shape: `defined $a && $b` →
`And(Defined($a), $b)`.

## Open question

The current `precedence-spec*.t` files have TODOs for the L2 vs
L10 case but no explicit tests for L8 vs L10 or L13 vs L10. Adding
them would make the regression coverage tight enough to catch a
future numbering mistake. Consider adding before re-attempting
`d6d5a195`.

## Cross-references

- Original plan: `docs/plans/2026-05-11-precedence-named-unary-plan.md`
- B1 design (now superseded by Option B above): `docs/plans/2026-05-11-step2-blocker-findings.md`
- `exists` investigation: `docs/plans/2026-05-11-exists-precedence-investigation.md`
- The reverted commit: `d6d5a195` (now followed by `662d169c` revert)
- Audit subagent report and observations: this document supersedes it.
