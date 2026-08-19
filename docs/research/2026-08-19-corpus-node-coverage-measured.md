# The corpus covers 46 of 80 node types. The other 34 have never been specified.

**Date:** 2026-08-19
**Status:** MEASURED. No code changed.
**Prompted by:** perigrin, on being told the `ir`-block format "can't express a
whole graph" — *"the fact that the corpus doesn't contain the other nodes is a
sign of an under developed corpus."* That is the correct diagnosis, and the
measurement backs it.

## What I had claimed, and why it was wrong

Arguing against replacing the JSON wire format with the `ir`-block format, I
said the block expresses "one graph's shape, three directives" and is "a subset
assertion, not a serialization."

Both wrong, and wrong the same way: **I counted what the CORPUS uses and
reported it as what the FORMAT supports.**

- `build_graph_from_ir` constructs a REAL graph and returns `($ret, $mop)` with
  a **sealed MOP**. It is a deserializer, not an assertion helper.
  `shape_subset_check` is a different function operating on text; I conflated
  them.
- The directives are `control:`, `branch_control:`, `loop_backedge:`, `return`,
  plus `MOP::Class` / `MOP::Field` / `MOP::Method` / `MOP::Adjust`.

## The measurement

**Directive coverage — the format is fully exercised:**

| directive | uses |
|---|---|
| `return` | 218 |
| `control:` | 198 |
| `branch_control:` | 35 |
| `loop_backedge:` | 29 |
| `MOP::Class` | 19 |
| `MOP::Field` | 13 |
| `MOP::Method` | 12 |
| `MOP::Adjust` | 1 |

**Node coverage — the vocabulary is not:**

- node classes on disk: **86** (80 concrete, 6 abstract bases)
- distinct ops appearing in corpus `ir` blocks: **47**
- **concrete node types with ZERO corpus coverage: 34 — 42%**

```
AnonSub BacktickExpr BitAnd BitOr BitXor Complement ExpressionList
Interpolate IsaOp LeftShift ListAssign Negate NotMatch NumCmp NumGe NumLe
Power Range Repeat Return RightShift Slice StashAccess StrCmp StrGe StrGt
StrLe StrLt StructFieldAccess StructRef TryCatch UnaryPlus Xor Yada
```

## Why this is the interesting finding rather than a tidy-up item

The gap is not in exotic corners. It contains node types that cost real time
THIS WEEK:

- **`StrLt` `StrGt` `StrLe` `StrGe` `StrCmp`** — I wrote a unit assertion for
  `StrLt` in `b5383f9c` *specifically because no corpus case could reach it*.
  Correct given the state, but the state is the defect: five ops of one family,
  all unspecified.
- **`TryCatch`** — `is_fixed`, a member of `%STATEMENT_EFFECT_OPS`, and never
  specified at corpus level.
- **`BitAnd` / `BitOr` / `BitXor`** — the family whose signature ambiguity
  (numeric `&` vs string `&.` sharing one node type) blocked step 2b and forced
  a documented carve-out in `%IR_OP_SOURCE_NAME`. Unspecified, so the carve-out
  is untested.
- **`Return`** — present in every graph, never spec'd as a node line.

Every corpus case is a triple contract (behaviour + shape + invariant), so an
op with no case has none of the three. The gate reads 196/196/196 and says
nothing about 42% of the vocabulary.

## What it does NOT mean

The 34 are not necessarily *unimplemented* — most have lowering code and unit
tests. What they lack is a case pinning behaviour against perl, a shape spec,
and invariant checking. That is exactly the "vacuous coverage" pattern this
project keeps rediscovering: a green gate whose greenness is bounded by what
was thought to ask about.

## On the format question that started this

With the directive counts in hand, the `ir` format is close to complete: it
expresses nodes, control, branch edges, loop back-edges, classes, fields,
methods and ADJUST. The genuine gaps versus JSON are narrow:

1. **multi-graph container** — `from_json` returns a hash of named graphs
   (one per method); `build_graph_from_ir` returns one root plus a MOP.
   A `graph <name>:` header would close it.
2. **no serializer** — the format can be read but not written, so no round-trip.
3. **`version` / `stamp` / `source`** metadata.

None is fundamental. But replacing the wire format is a two-repo change and
should not be undertaken to fix a corpus-coverage problem, which is what the
measurement says the real problem is.

## Suggested order

1. **Close the node-coverage gap** — it is the measured defect, it needs no
   format change, and each case is independently valuable.
2. **Then** revisit the format question, with a corpus that actually exercises
   the vocabulary to judge it against.

The 2383-line parser living in `t/lib/` remains a separate and legitimate
complaint (it has its own lexer, `_split_args_respecting_quotes`); moving it to
`lib/` is orthogonal to both.
