# SoN IR Convergence: Chalk Adopts perl5-son IR

## Goal

Replace Chalk's internal IR (`Chalk::Bootstrap::IR::Node` hierarchy) with
`SoN::IR` from perl5-son.  Both Chalk (source parser) and perl5-son (optree
translator) produce the same graph representation, enabling direct structural
comparison via `SoN::Compare`.

## Motivation

Chalk's 16 green files eval correctly as Perl, but "evals cleanly" only proves
syntax — not semantics.  By producing `SoN::IR::Graph` from Chalk's parser and
comparing against `SoN::FromOptree`'s graph of the same code compiled by perl,
we get a structural proof that Chalk's frontend produces correct IR.

This also eliminates the B::Concise comparison layer (ConciseTree, Oracle,
ConciseOp) which is fragile, text-based, and lossy.

## Architecture

```
Perl source ──→ Chalk parser ──→ SoN::IR::Graph ──┐
                                                    ├──→ SoN::Compare::diff
Perl source ──→ perl -c ──→ SoN::FromOptree ──────┘
```

Both paths produce `SoN::IR::Graph` objects.  `SoN::Compare` does structural
graph diff — matching data nodes by content hash and CFG nodes by topology.

## IR Mapping

### Direct Mappings (no change needed)

| Chalk | SoN | Notes |
|-------|-----|-------|
| `IR::Node::Constant` | `SoN::IR::Node::Constant` | value, stamp |
| `IR::Node::If` | `SoN::IR::Node::If` | control, condition |
| `IR::Node::Proj` | `SoN::IR::Node::Proj` | input, index |
| `IR::Node::Region` | `SoN::IR::Node::Region` | inputs |
| `IR::Node::Loop` | `SoN::IR::Node::Loop` | inputs |
| `IR::Node::Phi` | `SoN::IR::Node::Phi` | inputs |
| `IR::Node::Start` | `SoN::IR::Node::Start` | — |
| `IR::Node::Return` | `SoN::IR::Node::Return` | control, value |

### Constructor Class → SoN Node Type

| `Constructor:X` | SoN Node | Input mapping |
|------------------|----------|---------------|
| `BinaryExpr(op="+")` | `Add` | [left, right] |
| `BinaryExpr(op="-")` | `Subtract` | [left, right] |
| `BinaryExpr(op="*")` | `Multiply` | [left, right] |
| `BinaryExpr(op="/")` | `Divide` | [left, right] |
| `BinaryExpr(op=".")` | `Concat` | [left, right] |
| `BinaryExpr(op="==")` | `NumEq` | [left, right] |
| `BinaryExpr(op="eq")` | `StrEq` | [left, right] |
| `BinaryExpr(op="&&")` | `And` | [left, right] |
| `BinaryExpr(op="\|\|")` | `Or` | [left, right] |
| `BinaryExpr(op="=")` | `Assign` | [target, value] |
| `UnaryExpr(op="!")` | `Not` | [operand] |
| `UnaryExpr(op="-")` | `Negate` | [operand] |
| `MethodCallExpr` | `Call` | [invocant, method, args] |
| `BuiltinCall` | `Call` | [name, args] |
| `SubscriptExpr` | `Subscript` | [target, index] |
| `PostfixDerefExpr` | TBD | May need new SoN node |
| `TernaryExpr` | `If` + `Proj` + `Region` + `Phi` | Lowered to CFG |

### Chalk-only IR types (no SoN equivalent yet)

These represent Perl-specific constructs that perl5-son may not have
encountered yet (or handles differently via the optree):

- `Program`, `ClassDecl`, `MethodDecl`, `SubDecl` — structural wrappers
- `FieldDecl`, `UseDecl` — declarations
- `VarDecl` — variable declaration + init
- `ReturnStmt`, `DieCall` — statement-level constructs
- `HashRefExpr`, `ArrayRefExpr` — aggregate constructors
- `AnonSubExpr` — closure construction
- `RegexMatch`, `RegexSubst` — regex operations
- `InterpolatedString` — string interpolation
- `CompoundAssign` — `+=`, `.=`, etc.

These either need new SoN node types or need to be lowered to existing
SoN primitives during emission.

## NodeFactory Differences

| Aspect | Chalk | SoN |
|--------|-------|-----|
| Pattern | Singleton (`->instance()`) | Instance (per-graph) |
| Hash consing | Data nodes by content hash | Same |
| CFG nodes | Unique IDs, not consed | Same |
| Registration | Static `%INPUT_SPECS` hash | `register`/`register_cfg` class methods |
| Creation API | `$f->make('Constructor', class => 'BinaryExpr', ...)` | `$f->make('Add', inputs => [...])` |

## Migration Strategy

### Phase 0: Install perl5-son
- Clone `perigrin/perl5-son` locally
- `perl Makefile.PL && make && make install` into pvm 5.42.0
- Verify: `perl -MSoN::IR::NodeFactory -e 'print "ok\n"'`

### Phase 1: Proof of Concept (this session)
- Write a test that:
  1. Parses Symbol.pm through Chalk's pipeline → Chalk IR
  2. Compiles Symbol.pm with perl → optree → `SoN::FromOptree` → SoN graph
  3. Writes a manual adapter for Symbol.pm's simple methods
  4. Compares the two graphs with `SoN::Compare`
- Validates that the approach works before committing to full migration

### Phase 2: Adapter Layer (future)
- Write `Chalk::Bootstrap::IR::ToSoN` that walks Chalk IR and produces
  `SoN::IR::Graph`
- This enables comparison without changing Chalk's internal IR yet
- Run comparison on all 16 green files

### Phase 3: Native SoN IR (future)
- Change Chalk's semantic actions to produce SoN nodes directly
- Replace `Constructor:BinaryExpr(op="+")` with `$factory->make('Add', ...)`
- Remove `Chalk::Bootstrap::IR::Node::Constructor`
- Add Perl-specific node types to SoN as needed

## Dependencies

- perl5-son installed to pvm 5.42.0
- Test2::V0 (used by perl5-son tests, may need installing)

## Open Questions

1. Should Perl-specific IR types (ClassDecl, FieldDecl, etc.) live in
   SoN or in a Chalk-specific extension package?
2. How does `SoN::FromOptree` handle `feature class` fields/methods?
   Does it produce the same graph structure Chalk would?
3. TernaryExpr lowers to If+Proj+Region+Phi in SoN — should Chalk
   do this lowering in the parser or in a separate pass?
