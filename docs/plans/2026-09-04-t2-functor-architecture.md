# T2 as a functor: architecture of the class

**Date:** 2026-09-04
**Status:** DESIGN. Clean slate. Nothing in `lib/` is described, defended, or
patched by this document; the existing `Chalk::IR::Transform::T2` and the
LLVM target's coercion sites are deliberately not consulted as designs. Their
disposition is recorded in section 7.
**Input:** the handoff in `2026-09-04-t2-the-solver-a-handoff.md`, the
constraint design in `2026-09-04-t2-narrowing-the-design.md`, the arrow-map
finding in `2026-09-04-t2-is-a-functor-objects-and-arrows.md`, and the lattice
measurements in `2026-09-04-the-lattice-is-non-distributive-m3.md`.
**Supersedes, in two places:** the handoff's "`%CANDIDATES` sets have at most
4 members" (version one's largest set has two, section 5.1) and its "phases
2-4 behind a flag" (only stage 4 is flagged, section 6).
**Chain:** no `git zhi` issue owns T2; `lib/Chalk/IR/Transform/T2.pm` and
`t/bootstrap/ir/t2-*.t` landed off-chain. This document is the first owner.
**Producer pin:** perl5-son `b96087c`. Corpus gate: the PINNED floor is
220 (`t/bootstrap/corpus/son-corpus-wide.t:548`, `cmp_ok($tally{gate_green},
q{>=}, 220`); 223 is the MEASURED value at the pin (`paad/worklist.json`),
and a stage landing at 221 or 222 passes the suite. Where this document
says "223" it means the measured value; the floor is what the suite
enforces, and stage 1's first commit raises it to 223 so that the two agree.

## 1. The problem T2 solves

T1 is the producer's job: B::SoN walks the optree with real SV types in hand
and stamps every value node with a member of the Chalk type lattice. T2 is
Chalk's job: turn that Chalk-typed graph into a graph in which every value
has one concrete machine representation (`i64`, `double`, `%Str`, `%Slot`,
...) and every place two representations meet carries an explicit
conversion. The lattice type `Num` denotes a SET of legal representations
(`{i64, double}`), a stamp is not a representation, and nothing today
chooses a representation for a node while looking at what its neighbours
chose. A table maps `Num |-> double` before any constraint is seen, so
`9007199254740993 + 0.0` loses its low bits through a `sitofp` (a red
worklist case, `t/corpus/mdtest/arithmetic.md:236-260`; every corpus `.md`
cited below lives under `t/corpus/mdtest/`); `Add` can be handed one `i64`
and one `double` operand with nothing positioned to notice; and every
conversion the backend emits is a hand-written arm of `_emit_coercion`
rather than one rule. T2 is a functor guided by a constraint solver, not a lookup table
and not a subtype argument.

## 2. The functor

T2 maps one graph to another. Its objects are the nodes whose stamp is a
member of the Chalk lattice -- `defined $node->stamp &&
TypeLibrary::is_lattice_type($node->stamp)`, never a class test (section 3)
-- and one more per graph, RETURN, the value the graph hands back, stamped
with the sub's `return_type` where the MOP records one, else the join of
the `Return` inputs' stamps (Q3). Pure control and memory nodes (`Start`,
`Region`, `If`, `Loop`, `MemStart`, `Return`) carry no stamp and are not
objects.

- **On objects:** `F(n) = repr(n)`, one representation per object, chosen
  by the solver (section 5) per node from constraints, never per type from
  a table.
- **On data edges** `p -> (c, i)`: the conversion `repr(p) -> required(c,
  i)`. Equal: a plain edge. Different: a `Coerce(from_repr => repr(p),
  to_repr => required(c, i))` node on that edge. A consumer need not be an
  object (`If`'s condition, `Return`'s value); its demand is its row in
  section 5.2. A source `Coerce` is an object whose image is the same rule
  applied to its input edge, ELIDED when the rule yields the identity.

Three statements carry the enforceable content, each a test: `_arrow`
(section 5.5) is the only place in `lib/` that constructs a `Coerce` whose
`from_repr` and `to_repr` are REPR names (`Repr::is_repr` true) -- a grep
for `make('Coerce'` finds exactly two other sites, `Analysis.pm:1427`
(`_insert_str_coercions`) and `:1592` (`_narrow_unknown_coercions`), both
in the loader's T1-side pipeline and both writing LATTICE names (clause 9:
a different namespace), so the test is that every constructor call outside
`_arrow` passes lattice names and `_arrow` alone passes reprs; the arrow
table is COHERENT -- for INCLUSION rows `a=>b`, `b=>c`,
`a=>c` the direct and composed arrows agree on every probe value under
`lli` (`t/bootstrap/ir/coercion-composition-law.t`, stage 1), and a
disagreement names either the object map (the 2^53 kind) or one arrow's
implementation, while operation rows are outside the law and stage 1's
negative control asserts each DISAGREES with its direct row; and the
solver never asks `is_subtype` of two representations, because the
target has none (LLVM's type relation is equality) -- `Int <: Num <: Str <:
Scalar` is the source's vocabulary, not the target's. `F` is defined PER
GRAPH; call boundaries (worklist F18/F22) are section 7.

## 3. Input contract

What a graph must satisfy to be a legal input to T2, stated without
reference to any producer: the same clauses bind a graph that
`Chalk::IR::Serialize::JSON::from_json` loads from B::SoN output, one the
corpus harness builds from an `ir` fence
(`MdtestCorpus::build_graph_from_ir`), one a test builds by hand, and any
producer that does not exist yet. Ten of the clauses are T1's
POSTCONDITION, properties a producer owes every consumer -- eight about
the graph, and clauses 11 and 12 about the form it arrives in, which is
the same obligation one step earlier. Clauses 2 and 3
are T2 declining to guess: legal T1 output for which T2 picks no
representation, held on the same footing so the refusal is counted, and
never a defect in the producer. Section 3.1 states the clauses, each a
property of the graph on its own, each with the check that decides it.
Section 3.2 maps the refusal kinds onto the clauses. Section 3.3 records how the
producers that exist measure against the contract -- the gap, which is not
the contract. Whether a violated clause is REFUSED or REPAIRED with the
debt recorded is one decision applied across every clause, and it is open:
Q1. Nothing here is settled by what the wire happens to carry.

Two definitions the clauses use. A node is CONTROL when its operation is
`Start`, `Region`, `Loop`, `MemStart` or `Proj` (`%CONTROL_OP`, section
5.2), whatever stamp it carries: a `Proj :Int` is control, and both walks of
section 5 test `%CONTROL_OP` before the object predicate. An OBJECT POSITION
is a data operand of a non-control node -- a defined member of `inputs`
that is not itself control, excluding `If.inputs[0]` (a control edge that
may hold a stamped statement node) and `VarDecl.inputs[0]` (the name) -- and
the value of a `Return`. A memory operand (`Subscript.inputs[2]`, the arm of
a memory `Phi`) is an object position under this definition; whether it
should be is Q2 and Q6, and the count is in 3.3.

### 3.1 The clauses

Each clause is a property of the graph, checkable on its own; `check` names
what decides it.

1. **Stamped.** Every node in an object position carries a stamp that is a
   member of the Chalk lattice: `defined $node->stamp &&
   TypeLibrary::is_lattice_type($node->stamp)`. The node's CLASS is not the
   test: `stamp` is declared on the base class (`Node.pm:64`),
   `Chalk::IR::Value` (`Value.pm:51`) is an empty marker subclass, and
   `Print`, `Proj`, `VarDecl`, `ListAssign` and `TryCatch` are
   `:isa(Chalk::IR::Node)` directly while yielding values.
   `t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm:262-290` records the class
   test silently dropping a declared repr on the first four. Nor is
   `defined stamp` the test: a control node may carry a non-lattice string
   (`Control`, 3.3) and is exempt whatever it carries.
   *Check:* walk `nodes()`; for every non-control node, every object
   position satisfies the predicate.

2. **Constrained.** No object is stamped `Unknown`. This is T2 declining
   to guess, not T1's obligation. `Unknown` is the lattice's top -- its
   sole root (`TypeLibrary.pm:16`; the spine runs `Int => Num => Str =>
   Scalar => List => Unknown`, `:42-47`, `:95`; `is_lattice_type` admits
   it, `:328`) -- and the honest stamp for a value nothing constrains: a
   memory Phi or a subscript-after-store carries it on purpose. T2 picks
   no representation for an unconstrained value (`%CANDIDATES` has no row
   for the top), and the reason is ahead-of-time compilation: the layer
   that chooses a machine representation gets one shot, and that layer is
   T2. A narrow repr it cannot justify is the fabricated-`Num` miscompile
   (an `i64` read as a `double`,
   `2026-08-31-t2-is-a-narrowing-analysis.md:589`); a `%Slot` chosen
   silently is a choice no gate counts. Boxing is right where the stamp
   admits it (`Scalar => %Slot` is a row); for the top there is nothing to
   justify either, so an `Unknown` at an object position is legal input
   T2 refuses, as kind 2, exactly as clause 3 refuses `List`.

3. **Representable.** Every object's stamp is a key of `%CANDIDATES`
   (section 5.1): `Int Num Str Boolean Undef Scalar Array ArrayRef Hash
   HashRef Object CodeRef`. A lattice member outside that set (`List`,
   `Code`, `ScalarRef`, `Regex`, ...) has no representation in version one
   and does not reach a representation-demanding consumer.

4. **Constants are sound.** A `Constant` carries its literal `value`, and
   its stamp admits that value: an `Int` constant is integral and within
   i64 (the `_is_integral` boundary of section 5.1); a `Num` constant may be
   either, so a `Num` stamp says nothing about integrality (`0.0` and `1.5`
   are both `Num`) and the candidate rule reads the value; a `Str` constant
   holds its string.

5. **Tied operands are uniform.** For an operator whose operands are its
   own machine value -- `Add`, `Subtract`, `Multiply`, `Negate`, `Power` --
   every data operand carries the node's own stamp, or is a `Coerce` whose
   `to_repr` is that stamp; and a load carries its cell's stamp
   (`PadAccess.stamp eq VarDecl.stamp`). This is `%OP_REQUIRES_OWN_REPR`
   (`TypedInvariant.pm:67`) stated for the whole tie set of section 5.2.
   *Check:* `TypedInvariant->check($graph)` for `Add`, `Subtract`,
   `Multiply`; the same comparison by hand for `Negate`, `Power` and the
   load/cell pair, which TypedInvariant does not list.

6. **Converting positions are declared.** An operand at a position whose
   operator converts it as part of its semantics carries the operator's
   operand type, or is a `Coerce` to it: `Divide` `Num`, `Modulo` `Int`,
   `Concat` `Str`, `Print` `Str`, `StrEq`/`StrNe` `Str`, `Not` `Boolean`,
   the condition of `If` and of `TernaryExpr` `Boolean`. The first three
   are `%OP_REQUIRED_REPR` (`TypedInvariant.pm:21-44`); the rest are the
   fixed rows of section 5.2 that TypedInvariant does not list.
   *Check:* `TypedInvariant->check` for the three; the same test by hand
   for the rest.

7. **Pass-through edges are declared.** A value that passes through a node
   unchanged -- a `Phi` arm, a `TernaryExpr` arm, an `And`/`Or`/`DefinedOr`
   arm, a `VarDecl` initialiser, the value of an `Assign` or
   `CompoundAssign`, the value of a `Return` against the sub's return type
   -- carries the consumer's stamp, or is a `Coerce` to it. EQUALITY, not
   subtyping: `Int <: Num` does not make `Phi :Num` over an `Int` arm
   conform, exactly as it does not make `Add :Num` over an `Int` operand
   conform under clause 5, where T1 writes `Coerce(Int->Num)`. A widening
   on a merge arm is a conversion, and T1 declares it.
   *Check:* per consumer, per pass-through position, `stamp(p) eq
   stamp(c)` or `p` is a `Coerce` with `to_repr eq stamp(c)`; the `Return`
   position against the MOP's `return_type` (Q3).

8. **Compared operands are uniform.** The two operands of `NumEq NumNe
   NumLt NumLe NumGt NumGe NumCmp` carry one stamp, or the one that differs
   is a `Coerce` to the other's.

9. **A `Coerce` is well-formed.** It has one data input; its stamp is the
   type it converts TO (`to_repr eq stamp`); `from_repr` and `to_repr` are
   lattice names (section 5.1's reprs are a different namespace); and it is
   not the identity (`from_repr ne to_repr`).

10. **Shape.** (a) Every member of `inputs` is a node or `undef`; there are
    no arrayref inputs. (b) A `Return` has ONE input, its value, and its
    control predecessor rides `control_in`; an `Unwind`'s one input is its
    message, not a returned value, though `Graph::returns`
    (`Graph.pm:129-140`) lists both. (c) `If.inputs` is `[control,
    condition]` (`NodeFactory.pm:141`) and the control may be a stamped
    statement node -- perl5-son passes the arm's CURRENT control
    (`Phi.pm:14-31`); no other row-bearing op holds a control node in a
    data position. `Loop.inputs` is `[entry, backedge]` (`Loop.pm:30`,
    `set_backedge_ctrl`), its post-loop `region` set after construction
    (`Loop.pm:16,40`). A `Phi` names its merge point in `region` and may
    carry `predecessors`, an arrayref of NODES (`Phi.pm:37`), and its arms
    pair positionally with its Region's control inputs (TypedInvariant's
    arity check). (d) A load names its cell: `PadAccess.inputs[0]` is the
    `VarDecl` (`PadAccess.pm:22`); a store's target is a `PadAccess` of the
    same cell (`%lhs = PadAccess(%vx, "$x")`, `%as = Assign(%lhs, %one)`,
    `variables.md:83-86`; `CompoundAssign` the same, `increment.md:42-43`);
    `VarDecl.inputs[0]` is the name `Constant` (`:Str`), `inputs[1]` the
    initialiser or `undef`. (e) Two edge kinds live OUTSIDE `inputs`:
    statement-position effects ride `control_in` (`Node.pm:75`) and a
    `Phi`'s merge point rides `region`; neither is in `content_hash`, and
    `Graph::nodes()` follows NEITHER as an edge: its membership pass
    (`Graph.pm:200-226`) starts from the graph's cache and expands over
    `inputs` and cache-filtered `consumers` only, so a node reachable
    solely through a `control_in` edge is a member exactly when the
    producer `merge`d it (the loader merges each `Return`'s `control_in`
    chain, `JSON.pm:839-846`; the fence harness merges each body
    statement, `MdtestCorpus.pm:693`). Membership is a producer obligation,
    not a property of the edge: a graph built by `Graph->new(start,
    returns)` alone has those two members plus their `inputs` closure, and
    `print 7; return 1` seeded that way has 3 of its 6 nodes (measured,
    section 5.5). (f) Node ids are unique within the graph.
    *Check:* a structural walk for (a), (b), (d), (f); TypedInvariant for
    (c)'s arity; for (e), `Graph::nodes()` against a reach that follows
    `control_in` and `region` -- every node the reach finds is a member,
    or the producer failed to merge it.

11. **Decodable.** The serialized form decodes to the structure the
    producer meant, under a decoder that is not perl's. This is the one
    clause that binds the WIRE rather than the graph, and it is stated
    because T2's input arrives through a decode step that can silently
    disagree: perl's JSON decoder accepts raw high bytes in a string, and
    other decoders refuse the same document. A producer that emits its
    strings with neither `->utf8` nor `->ascii` therefore has no single
    answer to "what does this document say".
    The fix is `->utf8`, at the producer's single encode site. What the
    serializer receives is a CHARACTER string -- perl has already decoded
    the literal -- so `->utf8` encodes those characters to bytes exactly
    once, which is what a byte-oriented wire needs. `->ascii` is equally
    correct and is the wrong trade: it escapes every non-ASCII character,
    so ordinary Unicode text pays for the pathological case (measured on
    `"café ☺ naïve"`: 20 bytes plain, 24 under `->utf8`, 35 under
    `->ascii`).
    THE TEST IS VALUE EQUALITY AFTER DECODE, NEVER BYTE EQUALITY ON THE
    WIRE. "These bytes changed" and "this value changed" are different
    findings and only the second is corruption: `->utf8` turning `ff` into
    `c3 bf` is the correct encoding of U+00FF, not a mangling of it, and a
    round trip returns the original string. Reading the hex without the
    round trip is how the remedy first came out inverted here. The utf8
    flag settles nothing either -- a high-byte literal and an ordinary
    accented one can both report it off -- so only what the producer hands
    the serializer answers the question.
    `docs/plans/2026-09-13-the-wire-is-not-valid-utf8.md` (perl5-son)
    carries the measurement; 4 of 34 files in that corpus are affected.
    *Check:* round-trip each string value through a non-perl decoder and
    compare the VALUE; a divergence is the producer's, not T2's.

12. **Named by sigil and symbol.** A node that names a variable carries the
    sigil and the bare symbol SEPARATELY, and the symbol is bare: `x`, not
    `$x`. The symbol table is sigil-free and the sigil selects a slot
    within the glob, so `sigil` is not decoration on the name -- it is what
    distinguishes the scalar `$_`, the array `@_`, and the `-f _` filetest
    handle, three different variables sharing one symbol. A producer that
    supplies the symbol without the sigil has not named a variable, and the
    loader refuses rather than defaulting one (`JSON.pm`, PadAccess and
    EntryDef): an invented sigil hash-conses unrelated variables into one
    node, which is a silent merge rather than an error.
    This is also why the halves are composed in exactly one place
    (`PadAccess::name`, `EntryDef::name`) and never at a comparison site: a
    consumer that composes them itself and is later missed stops matching
    SILENTLY, with no error to find it by.
    *Check:* every variable-naming node has a defined sigil; the composed
    `name` round-trips through serialization unchanged.

### 3.2 The refusal kinds

Enumerated once and used by every gate in section 6, each with the clause
it enforces and the method that raises it:

1. `unstamped` -- clause 1 -- `generate`, `_key_of`: an object position
   holding a node with no lattice stamp whose operation is not in
   `%CONTROL_OP`. A `Return` with its control in `inputs` (clause 10 (b))
   is refused only when that control is outside `%CONTROL_OP` (`If`),
   naming it; a `%CONTROL_OP` member there (`Start`, `Region`, `Proj`) is
   skipped before the object test and the value takes the row, so the
   graph builds;
2. `Unknown` -- clause 2 -- `candidates_of_stamp`: an object nothing
   constrains, for which T2 declines to invent a representation; the
   refusal is T2 keeping its one shot honest, not a defect in T1;
3. `List` -- clause 3 -- `candidates_of_stamp`;
4. `Code` -- clause 3 -- `candidates_of_stamp`; the wire word for `AnonSub`
   (`TypeLibrary.pm:144` parents it to `Unknown`); `%CANDIDATES` has a row
   for `CodeRef`, a different lattice member, and `Code` dies until
   `019f51e7-82c6-7ce4-ba9f-1fa104842f6d` names the spelling it stamps;
5. `ScalarRef` -- clause 3 -- `candidates_of_stamp`;
6. `no arrow from=>to` -- no clause: a pair `%ARROW` lacks, at
   substitution (`_arrow`); a gap in the target's table, not in the input,
   measured to zero at stage 3;
7. `lossy own edge` -- clause 7, the operation half -- `_required`: a
   pass-through edge (relation 2, section 5.2) whose arrow would be an
   operation row. `my $x = 1; $x = 2.5` with the cell stamped `Int` is a
   T1 inconsistency (the cell should be `Num`), and truncating `2.5` into
   an `i64` cell is a miscompile every invariant of section 4 is blind to:
   a minted `Coerce` makes O2 true by construction, so the die is the only
   guard.

8. `no sigil` -- clause 12 -- the loader (`JSON.pm`, the `PadAccess` and
   `EntryDef` arms): a variable-naming node whose wire record carries a
   symbol but no sigil. It is raised at DECODE, before any T2 walk, which
   is why it is the one kind a pure-graph checker cannot reproduce: by the
   time a graph exists the refusal has already happened or the sigil is
   present. Defaulting instead of refusing would hash-cons `$_` and `@_`
   into one node -- a silent merge, which is why this is a die and not a
   repair.

No refusal kind enforces clause 4, 5, 6, 8, 9, 10 or 11. Clause 11 is the
deliberate one: a decode failure is not T2 refusing a graph, it is T2
never receiving one, so it has no kind and belongs to whoever owns the
serializer. Kinds 3-5 are three
names for ONE die (`$CANDIDATES{$stamp} // die`), so a rowless member
outside the three (`Regex`, 3.3) dies the same way and has no column.
Which kinds are tolerated beyond refusal is Q2; the eight are counted
separately.

### 3.3 How the current producers measure against the contract

Three producers exist. Measured with a clause checker (harness, not in the
repo) over the 231 buildable corpus `ir` fences (255 blocks; 24 pure-GAP)
and over live B::SoN output through `from_json` -- at the pin `b96087c`
(a `git archive` of the producer at that commit) and at the checkout head
`b0c5c6d`, which agree on every probe below.

**B::SoN through `from_json`.**

- Clause 1. The loader sets `stamp` from the wire for the
  `%LOWERABLE_STAMP` members (`Int Num Str Boolean Undef Object ArrayRef
  HashRef Array Hash Scalar`, `JSON.pm:88-89`) and for any other stamp that
  `is_lattice_type` (`JSON.pm:766-768`); a node with no stamp on the wire
  arrives with `stamp` undef. A live probe shows `Start`, `Loop`, `Region`,
  `Proj` and `Return` arriving that way -- all control or `Return`, no
  violation. `Print` arrives stamped `Scalar`, an object. `VarDecl` on the
  wire is UNMEASURED; stage 2's kind-1 count is the measurement (Q2). Memory
  Phis and subscript-after-store stay `Unknown` or unstamped by decision
  and are kind 2 or kind 1 under the clauses as written (Q2, Q6).
- Clause 2. NOT met: `Unknown` reaches the wire. The magnitude is a LIVE
  B::SoN wire measurement, dated 2026-08-27
  (`2026-08-27-wire-unknown-audit-brief.md:12`: 233 `Unknown` stamps), not
  a fact of the checked-in corpus -- the `t/corpus/mdtest/*.md` files are
  prose plus `ir` listings, not wire JSON, and no fence writes `:Unknown`
  -- so the count moves with the producer and is re-taken, not quoted,
  when it is needed. Two separate facts stand whatever the count. `Unknown`
  is legal; the memory Phis and subscript-after-store among them carry it
  on purpose (Q2). And, at that measurement, about 86% of the 233 was
  producer QUALITY, not contract: the producer had the answer and
  discarded it -- `return_type: Int` on the sub record while the `Call` in
  the same document reads `Unknown` -- waste worth fixing on its own
  account, and no evidence about the clause either way. Because `Call` is
  in `%UNCHECKED` but its OWN stamp is still seeded through `candidates`
  (section 5.2: the object seed runs before the exemption), a `Call
  :Unknown` at an object position refuses the whole graph as kind 2, and
  stage 2's kind-2 column is dominated by whatever that count is on the
  day it is measured.
- Clause 3. NOT met: `List`, `Code` and `ScalarRef` arrive in practice
  (`JSON.pm:762-768`'s comment names the fixtures that failed on
  `AnonSub`, `Ref`, `ArrayLiteral`).
- Clause 4. Met where measured. Two producer facts sit next to it. The
  producer CONSTANT-FOLDS: `my $x = 7 / 2; print $x % 2` arrives as
  `Modulo(Constant 3.5 :Num, 2 :Int) :Int`, a clause-6 violation reachable
  from a one-liner (Q5). And the loader's hash-consed `Constant` can
  manufacture a violation of clause 5 or 7 out of a legal program: its
  `content_hash` is `const_type` plus `value`, and `const_type` is `number`
  for integer and float alike (`Constant.pm:17-21`), so `Constant(0)` sent
  as `Int` and as `Num` in one graph is ONE node holding whichever stamp
  came last (`JSON.pm:698`, `:724-725`, `:766-768`). The functor never
  shares that node silently between two reprs: the shape refuses (a
  hard-empty class, or kind 7); the dissolution belongs to the loader (Q4).
- Clause 5. Met for `Add`, `Subtract`, `Multiply` -- the TypedInvariant leg
  of the corpus gate; `my $y = $x + 1.5` arrives with `Coerce(Int->Num)` on
  the `Int` operand (probe). The load/cell half is unmeasured.
- Clause 6. Met for `Divide`, `Modulo`, `Concat`, `Print` (`print $n` with
  `$n` an `Int` arrives with `Coerce(Int->Str)`, probe), except the folded
  `Modulo` above and `f() / g()` (operand unstamped at build time,
  `019f8cbd-f5fc-74c1-921d-3ff1afdcbbf8`). NOT met for conditions: `my $x
  = 3; if ($x) {...}` arrives `If(.., Constant 3 :Int)` bare, and so does a
  `TernaryExpr` condition (probes).
- Clause 7. NOT met on the `Num` spine: `my $c = 1; my $x = $c ? 1 : 1.5`
  arrives `TernaryExpr :Num` over `Constant 1 :Int` and `Constant 1.5 :Num`
  with no `Coerce` on the `Int` arm (probe, at both producer commits); the
  same relation on a `Phi` is refused as kind 7 by the shape harness (trace
  A14). NOT met on the `Scalar` spine either: `Phi(%c99, %und) :Scalar`
  over `Int` and `Undef` arms is GREEN at `logical.md:247` with no
  `Coerce`, because the repair there is a box.
- Clause 8. NOT met when the operands differ: `1.5 < 3` arrives `NumLt(Num,
  Int)` bare (probe). Same-typed comparisons (`NumGt(%n, %zero)` over two
  `Int`s, every one in the corpus) are uniform by accident, not by
  declaration; `TypedInvariant.pm:21-66` has no `NumLt` row.
- Clause 9. `to_repr eq stamp` holds where measured. `from_repr` is a
  stale snapshot by the producer's own characterisation (`f3aeb99`); T2
  reads neither field on a source `Coerce` -- the node is its own input
  edge and the arrow comes from the two classes' reprs (section 5.5).
- Clause 10. (a), (b), (c) and (e) met (a live `Return` is
  `{"control_in":0,"inputs":[1],"op":"Return"}`; a bare `Call` or `Print`
  may be reachable only through a `Return`'s `control_in`, and is a member
  of `nodes()` because the loader merges that chain, `JSON.pm:839-846`,
  not because the walk follows the edge). (d) NOT
  always: a loop-carried cell (`my $w = 1; while ($w < 3) { $w = $w + 1
  }`) delivers two `PadAccess` nodes with `inputs[0]` undef -- a load with
  no `VarDecl` (Q6). (f) Met within a graph, not across: per-call ops
  (`Phi#N`, `If#N`, `Call#N`) have counter-based ids.
- Clause 11. NOT met. The producer's serializer sets neither `->utf8` nor
  `->ascii`, so string `Constant`s carrying raw high bytes make a document
  that perl's decoder accepts and a stricter one refuses -- 4 of the 34
  files in the producer's own corpus
  (`docs/plans/2026-09-13-the-wire-is-not-valid-utf8.md`, perl5-son). The
  clause is stated ahead of the fix because the finding does not depend on
  it: what T2 can decode is a property of the input, and a producer-side
  `->utf8` at its single encode site closes it without changing anything
  here.
- Clause 12. Met at producer `2aa5fd7` and NOT before it. The pre-split
  wire carried one `varname` blob with the sigil inside; `2aa5fd7` sends
  `sigil` + `symbol` (and `package` for a stash variable), with the symbol
  bare. The loader requires the sigil and refuses a wire without one, so
  the clause is enforced rather than assumed -- measured across the corpus
  gate, a pre-split wire produces exactly 7 refusals naming the missing
  sigil and a post-split wire produces none.

- Outside the contract, two loader gaps: `EntryWrite` is unknown to the
  loader (independent of T2), and `to_json` drops any non-lattice stamp
  (`JSON.pm:435`).

**The corpus `ir` fence (`MdtestCorpus::build_graph_from_ir`).**

- Clause 1. NOT met on 212 of the 231 graphs: the fence writes `%p =
  Print(%co_p, %nl)` with no stamp and `return %p` (`statements.md:35-36`
  is the first), so the returned value is unstamped -- kind 1 on every one
  of them; a handful stamp it (`logical.md`). Fourteen more, the
  by-decision unstamped memory positions of Q2 among them. The grammar writes
  `:Control` on `If`, `Proj` and `Region` (`logical.md:919-923`) and
  `MdtestCorpus.pm:290-291` sets any `:X` as a stamp unconditionally, so a
  control node can carry the string `Control`, which `is_lattice_type`
  rejects -- the second half of clause 1's predicate.
- Clause 2. Met: no fence writes `:Unknown`.
- Clause 3. One violation: `Match(.., Constant :Regex)` (`regex.md`, block
  2) -- a rowless member beyond the three the refusal kinds name.
- Clause 4. Met. Clause 5. Met: all 35 `VarDecl`s are stamped by the
  harness and every load matches its cell.
- Clause 6. NOT met: 13, conditions and `Print` operands over an `Int`.
- Clause 7. NOT met: eight, all on the `Scalar` spine (`logical.md:247`
  among them); none on the `Num` spine.
- Clause 8. Three: `NumEq(Num, Int)` (`variables.md`, blocks 21-23).
- Clause 9. Met. Clause 10. Seven `Phi`s with no `region`; the rest met.

**Hand-built graphs** (the fixtures of section 5.3 and the stage 1-3
tests). Meet every clause by construction; the ones that violate a clause
do so on purpose and are the NEGATIVE gates (`Int cell = 2.5` violates
clause 7; `Add:Int` over a `double` violates clause 5).

**Not a producer.** The hand frontend (`Chalk::Bootstrap::Perl::Actions`
through `NodeFactory`) builds `Return` as `inputs => [$ctrl, $val]`
(`NodeFactory.pm:145`) and gives `Unwind` and `ListAssign` arrayref inputs:
it fails clause 10 (a) and (b) and is not an input to T2.

## 4. Output contract

The image is a NEW `Chalk::IR::Graph`, built by a fresh `NodeFactory`, using
the same node classes as the source. The one field that changes meaning is
`stamp`: in the image it holds a representation name, never a Chalk type. The
source graph is untouched. Building the image is a graph deep-copy (every
edge kind, both back-edge kinds, node-valued fields, the MOP link), a named
stage-3 deliverable with its own test (section 5.5).

The checker is `Chalk::IR::Graph::ReprInvariant`
(`lib/Chalk/IR/Graph/ReprInvariant.pm`), `ReprInvariant->check($image)`,
pure over the image and `Repr`'s tables, returning `{ ok => 0|1, violations => [ { invariant =>
'O2', node => $id, message => ... }, ... ] }`, the shape of
`TypedInvariant::check` (`TypedInvariant.pm:226,456`). Every invariant is
what makes LLVM lowering a transcription rather than a decision.

| # | invariant | checked how |
|---|---|---|
| O1 | (a) Every stamped image node has a `stamp` that is a member of `Repr`, and so are every `Coerce`'s `from_repr` and `to_repr`; no Chalk type name appears anywhere in the image. (b) Every object position of the image (section 3's definition, `%CONTROL_OP` tested first) holds a stamped node -- clause 1 restated over the image. (c) Every `%CONTROL_OP` node and every `Return` is unstamped. Whether a source node's stamp survived is not the image's to say: stage 3 asserts it in `apply`. | `Repr::is_repr` on every stamped node and both `Coerce` fields; the object-position walk of clause 1 with `defined stamp` as the predicate; `%CONTROL_OP` and `Return` by operation |
| O2 | For every data edge `p -> (c, i)` out of an object into a position that `c`'s row constrains: `repr(p) eq Repr::required_repr(op(c), i, repr(c), [the reprs of c's object operands])` -- the call `_required` makes, so the image is checked against the rows that built it. `required_repr` answers for a stampless consumer too (`If`'s condition is a fixed `%Bool`), and a `Phi`'s arms deliver the Phi's own repr, so a conversion on a merge sits in the arm. `Return` has no repr in the image (RETURN is the functor's object, not the graph's), so its clause is that every `Return` value in the image carries ONE repr. A position the row leaves `undef`, and every edge into an op listed in `%UNCHECKED`, is NOT checked: the edge carries whatever the producer chose. An op with neither a row nor an `%UNCHECKED` entry is refused in `generate`, so there is no silent third state. `Coerce` is the one node whose OUTPUT repr differs from its input's, by an arrow: `from_repr eq repr(input)`; `to_repr eq stamp`; `from_repr ne to_repr` (the identity is never a node); `exists $ARROW{"$from=>$to"}` (every arrow the image needs has a row). Agreement with the table is not correctness: a wrong row (`Divide => { operand => 'i64' }`) passes O2 by construction; the pinned fixtures of section 5.3 and stage 4's `lli` gate are what check a row. | `Repr::required_repr` per edge, section 5.2; `%ARROW` |
| O6 | Every `Constant`'s repr can hold its value: an `i64` constant is integral and within range; a fractional literal is never `i64`. | value check; the guard against `floating point constant invalid for type` |
| O8 | The source graph is unchanged: every source node's `(content_hash, stamp)` pair before `apply` equals the pair after. `content_hash` alone is vacuous, because `stamp` is excluded from it by design (`Node.pm:102`, `:245`). | per-node `(content_hash, stamp)` snapshot |
| O9 | Determinism: `apply` twice on the same source, and `apply` with the constraint lists shuffled, yield images whose nodes, in `nodes()` order, have identical `(content_hash, stamp)` pairs and identical `why` strings -- `why($node)` names the rules from the closed set `pinned`, `default:identity-preserving`, `default:widest`, then every pin and constraint with an end in the node's class, as one sorted set (section 5). `content_hash` alone is vacuous for the same reason as in O8. | run twice, diff the pairs and the `why` strings |
| O10 | Structure preservation: the image is the source with `Coerce` nodes inserted or elided and NOTHING else. (a) The multiset of operations over the image's `nodes()`, `Coerce` removed, equals the same multiset over the source's `nodes()`, `Coerce` removed. (b) Every non-`Coerce` image node has exactly one source preimage: `%image` restricted to non-`Coerce` source nodes is a bijection onto the non-`Coerce` members of the image's `nodes()`. (c) The counts are related exactly: `image->nodes` = `source->nodes` - (source `Coerce`s) + (image `Coerce`s). An image that satisfies O1, O2, O6, O8 and O9 while missing its `Print` -- the dropped-statement program of section 5.5 -- fails (a) and (c). | checked in `apply`, which holds both graphs and `%image`; `check($image)` alone cannot see the source, as with O1's source half |

Given these, lowering a stamped node reads `stamp` and emits; lowering a
`Coerce` looks up `%ARROW` and emits the named instruction sequence; there is
no widening, no repr join, no `is_subtype`, and no site that has to decide.

## 5. The solver core

Four phases, each a method, each with a separate data structure, run once in
order. Nothing writes to the image until phase 4, and nothing ever writes to
the source.

```perl
# ABOUTME: T2 -- a functor from a Chalk-typed IR graph to a representation-typed one.
# ABOUTME: Generate edge constraints, solve by intersection, default what is free, then build the image.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Scalar::Util qw(refaddr);
use Chalk::IR::NodeFactory;
use Chalk::IR::T2::Repr ();     # the target vocabulary, %ARROW and the op rows
use Chalk::Grammar::Perl::TypeLibrary ();   # is_lattice_type, join_types: SOURCE-side questions only

class Chalk::IR::T2::Functor {
    field $source :param :reader;                # Chalk::IR::Graph, read only
    field $factory = Chalk::IR::NodeFactory->new; # builds the image

    # All keyed by refaddr($source_node), plus the one key RETURN for the
    # graph's return object (section 2). Constraints hold KEYS, never
    # nodes. One instance per source graph, discarded after apply. No
    # package-level state anywhere in this class.
    field %candidates;   # key => { repr => true }          seeded in generate
    field %node_of;      # key => source node (RETURN has none)
    field @hard;         # [ 'same', $a, $b, $because ] | [ 'demand', $key, \@reprs, $because ]
    field @soft;         # [ 'same', $a, $b, $because, $input_index ]  own: consumer, producer; shared: first object operand, this one
    field %class;        # union-find parent, key => key
    field %min_id;       # class root => smallest member id  (deterministic root)
    field %set;          # class root => { repr => true }    after solve
    field %repr;         # class root => repr name           phase 2/3 result
    field %why;          # class root => { rule => true }    the rules that decided it (why, O9)
    field %image;        # refaddr => node in the image       phase 4
    field @loop_phis;    # source loop Phis: data back-edge patched last
    field @loops;        # source Loops: control back-edge patched last
    field @regioned;     # source Ifs and Loops: post-construct region (and its Region's head) patched last
    field @phis;         # every source Phi: predecessors patched last

    method apply() {
        $self->generate;
        $self->solve;
        $self->default;
        return $self->substitute;   # a new Chalk::IR::Graph
    }

    # THE ONLY WRITER of %repr and %why. A repr and the rule that chose it
    # are one write, so neither hash can be populated without the other, and
    # an undefined choice dies here rather than reaching the image. A second
    # decision on a decided class must AGREE; it adds its rule to the set.
    method _decide ($root, $choice, $rule) {
        die "T2: no representation chosen for class of " . $self->_members($root)
            unless defined $choice;
        die "T2: class of " . $self->_members($root)
          . " decided twice: $repr{$root} then $choice ($rule)"
            if exists $repr{$root} && $repr{$root} ne $choice;
        $repr{$root} = $choice;
        $why{$root}{$rule} = true;
        return;
    }

    # Union-find. THE ROOT IS THE MEMBER WITH THE SMALLEST NODE ID, so a
    # class root is a property of the graph, not of merge order or of an
    # address. A decision already made on the absorbed root rides along
    # through _decide, which dies if the two roots had decided differently.
    method _find ($k) {
        return $k if $class{$k} eq $k;
        return $class{$k} = $self->_find($class{$k});
    }
    method _union ($a, $b) {
        my ($ra, $rb) = map { $self->_find($_) } $a, $b;
        return $ra if $ra eq $rb;
        ($ra, $rb) = ($rb, $ra) if $min_id{$rb} lt $min_id{$ra};
        $class{$rb} = $ra;
        if (exists $repr{$rb}) {
            my ($choice, $rules) = (delete $repr{$rb}, delete $why{$rb});
            $self->_decide($ra, $choice, $_) for sort keys %$rules;
        }
        return $ra;
    }

    # What O9 compares. CANONICAL: the rules that decided the class, then
    # its pins, as one sorted set. A log of which merges happened is NOT
    # canonical: two runs reach the same partition by different routes, and
    # a pair found already-in-one-class by one route is a merge on the other.
    method why ($node) {
        my $root = $self->_find(refaddr $node);
        return join '; ', (sort keys $why{$root}->%*), $self->_pins_for($root);
    }

    # Helpers, one line each:
    #   _is_object($n)   defined stamp and is_lattice_type (section 2)
    #   _id_of($key)     the source node's id; the string RETURN for RETURN
    #   _members($root)  ids of every key whose _find is $root, sorted
    #   _roots           every key that is its own parent
    #   _pins_for($root) each member's `id:stamp`, then every @hard and
    #                    @soft entry with an end in the class, as text,
    #                    both lists sorted (O9)
    #   _conflict_report($root)  _members plus _pins_for, for the die
    #   _intersect($s, $t)       { k => true } over keys in both
}
```

### 5.1 Vocabulary and the object seed

`Chalk::IR::T2::Repr` owns the object map, the candidate rule, the arrow
table, and the op rows of section 5.2. It is the ONLY module in which a
Chalk type name and a repr name appear in the same expression, and the one
module both the functor and `ReprInvariant` read.

```perl
package Chalk::IR::T2::Repr;
use Chalk::Grammar::Perl::TypeLibrary ();   # operand_repr_for_ir_op, for the rows of section 5.2

# THE object map, F on objects BEFORE solving: the candidate SET a stamp
# admits -- its own repr or that of any subtype (the downward cone). Version
# one collapses only the Num spine; every other stamp is a singleton.
# Widening this table is the one-site change for width, sign and interval
# work later. The tree's other object maps (`%_REPR_LLVM_TYPE`, `T2.pm:86`,
# `%LOWERABLE_STAMP`) are this one in other spellings; section 6 says at
# which stage each is re-keyed onto it or deleted.
#
# `Unknown`, the top, has no row and gets none: its cone is the whole
# lattice, and T2 refuses to guess a representation for a value nothing
# constrains (kind 2, clause 2) -- the row that would end the refusal is
# a stamp on the producer side, never an entry here.
# Rowless lattice members die in `candidates_of_stamp`: refusal kinds 2-5, section 3.2.
our %CANDIDATES = (
    Int      => ['i64'],
    Num      => ['i64', 'double'],
    Str      => ['%Str'],
    # %Bool and %Undef are FINER than the emitter's single `i1`: their box
    # arrows write different tag slots.
    Boolean  => ['%Bool'],
    Undef    => ['%Undef'],
    Scalar   => ['%Slot'],
    # A container and a reference to one are different machine values
    # (`%Array*` against a boxed `i8*`, Target/LLVM/Context.pm:4752-4754;
    # `%Array*` against `%ArrayRef*` in the existing T2.pm:92-95), and
    # `:ArrayRef` is a live corpus stamp distinct from `:Array`
    # (`references.md:229`), so each keeps its own repr; folding them
    # would leave no way back, and no shim downstream can pick one
    # spelling for both.
    Array    => ['%Array'],    ArrayRef => ['%ArrayRef'],
    Hash     => ['%Hash'],     HashRef  => ['%HashRef'],
    Object   => ['%Object'],
    CodeRef  => ['%Code'],   # spelling owned by 019f51e7-82c6
);

# The target objects: every repr some row admits. Spelled so that no member
# can be confused with a lattice member -- `is_lattice_type` is false for
# each, load-bearing for `i64` and `double`, asserted at stage 1.
my %REPR = map { $_ => true } map { $_->@* } values %CANDIDATES;
sub is_repr ($name) { exists $REPR{$name} }

# The one repr of a type whose set is a singleton, else undef: how a row of
# section 5.2 turns a lattice type into an obligation.
sub singleton_repr ($type) {
    my $set = $CANDIDATES{$type // ''} // return undef;
    return $set->@* == 1 ? $set->[0] : undef;
}

# candidates($node) -> arrayref of repr names, or dies.
#
# VALUE-AWARE FOR CONSTANTS. `Constant(0)` stamped Num denotes 0.0, and 0.0
# is an exact integer, so i64 is a legal representation of it; `1.5` is not.
# This is where the 2^53 object-map defect is repaired: the literal's own
# value decides whether i64 is in its set, not the table. An Int-stamped
# Constant keeps its singleton {i64}: seeding it from its value as
# {i64, double} would leave `Coerce(Int->Num) + 0.0` with no pin at all,
# and rule 2 would send the 2^53 case back to double (measured).
sub candidates ($node) {
    my $set = candidates_of_stamp($node->stamp, $node->id);
    if ($node->operation eq 'Constant' && $node->stamp eq 'Num') {
        return [ grep { $_ ne 'i64' } $set->@* ] unless _is_integral($node->value);
    }
    return $set;
}

# The stamp half of the rule, also used for RETURN, which is a stamp with no
# node. The three dies are refusal kinds 1, 2 and 3-5 (section 3).
sub candidates_of_stamp ($stamp, $id) {
    die "T2: unstamped object $id -- the wire carried no stamp" if !defined $stamp;
    die "T2: Unknown stamp on $id -- no representation for an unconstrained value" if $stamp eq 'Unknown';
    my $set = $CANDIDATES{$stamp} // die "T2: no representation for stamp '$stamp' on $id";
    return [ $set->@* ];
}

# Integral AND within i64, because O6 promises both and a literal arrives as
# whatever perl parsed: an IV, an NV, or a string ("1e3", "0.0"). The range
# test is done on int($v) in the INTEGER domain: `abs($v) < 2**63` is wrong
# at IV_MAX, which the IV/NV comparison rounds up to 2**63 and rejects. The
# boundary set is pinned at stage 1.
sub _is_integral ($v) {
    return false if $v != $v || $v != int($v);           # NaN; fractional
    my $i = int($v);
    return false if "$i" !~ /^-?[0-9]+\z/;                # out of integer range (1e300, Inf)
    return $i >= -9223372036854775808 && $i <= 9223372036854775807 ? true : false;
}

# F on morphisms: which conversions exist. Key "from=>to", value the
# lowering strategy and the row's KIND. Identity pairs are deliberately
# ABSENT: the identity is never a node. THE CRITERION decides the kind, not
# a judgment per row: a row is an INCLUSION when its arrow is total on its
# source repr and preserves the perl value -- defined for every value v of
# the source, with a result that agrees with v under `==`, `eq` and
# `defined`. Any other row is an OPERATION. Total plus value-preserving is
# exactly what the two uses of the split need: every composite of
# inclusions denotes what the direct row denotes, so the coherence law
# holds and `_arrow` may collapse through them; and an inclusion never
# refuses at run time and never changes what a value prints or compares
# as, so a pass-through edge may take one, and never an operation (kind 7).
# Each operation row is classified by one probe value, pinned at stage 1.
# The rows printed here are the stage-1 set; stage 3 completes the table
# from the `no arrow` refusals it counts, one executed probe per added row,
# and the probe classifies the row.
our %ARROW = (
    'i64=>%Str'     => [ format_int => 'inclusion' ],
    'i64=>%Slot'    => [ box_int    => 'inclusion' ],
    'double=>%Slot' => [ box_num    => 'inclusion' ],
    '%Str=>%Slot'   => [ box_str    => 'inclusion' ],
    '%Bool=>%Slot'  => [ box_bool   => 'inclusion' ],
    '%Undef=>%Slot' => [ box_undef  => 'inclusion' ],
    # the image of a source Coerce with a non-inclusion label, of a %Bool
    # obligation (If, TernaryExpr) on a non-Boolean value, of an i64
    # obligation (Modulo) on a double, of a double obligation (Divide, a
    # comparison's fallback) on an i64, or of a %Str obligation (Concat,
    # Print) on a number
    'i64=>double'   => [ sitofp            => 'operation' ],
    'double=>%Str'  => [ format_num        => 'operation' ],   # %.15g
    '%Slot=>i64'    => [ unbox_int_checked => 'operation' ],
    '%Slot=>double' => [ unbox_num_checked => 'operation' ],
    '%Slot=>%Str'   => [ unbox_str_checked => 'operation' ],
    'i64=>%Bool'    => [ truthy_int        => 'operation' ],
    'double=>%Bool' => [ truthy_num        => 'operation' ],
    '%Str=>%Bool'   => [ truthy_str        => 'operation' ],
    'double=>i64'   => [ trunc_num         => 'operation' ],   # fptosi; its semantics against pp_modulo are Q5
);

sub arrow_kind   ($key) { $ARROW{$key} ? $ARROW{$key}[1] : '' }
sub is_inclusion ($key) { arrow_kind($key) eq 'inclusion' }
sub is_operation ($key) { arrow_kind($key) eq 'operation' }
```

`%ARROW` is the `(From, To)` coercion registry the slice plan deferred
(`2026-07-22-coercion-architecture-slice-plan.md:73`, `:149-152`) behind
"B-holds AND N>=3". N has moved -- `Int->Num` before `Divide`
(`019f82f1-3318-72bd-be13-2e095f13b8f3`) and `Coerce[Int->Str]`
(`019f6e98-fbc0-7934-8e8a-94ef618e29bc`) landed, `Str->Num`
(`019f8193-dd8f`) pending, and `%ARROW` is the table they would share.
B-holds is NOT met (the loop-store case is parked,
`2026-07-23-slice-b-inliner-effect-ordering.md:140`); stage 1 does not
start until perigrin waives it or rules that a flat table is not the
registry the trigger guards.

### 5.2 GENERATE: every edge is an obligation

`generate` walks every node of `$source->nodes` once, seeds `%candidates`
for each object (and for RETURN), and emits constraints. It writes nothing
to any node. Each op contributes through one row; an op with inputs that
has no row and no `%UNCHECKED` entry is refused, not defaulted.

Constraint kinds, as plain arrays: `['demand', $key, \@reprs, $because]`
intersects the node's OWN set with `@reprs` (HARD); `['same', $a, $b,
$because]` says `$a` and `$b` share one representation, HARD or SOFT as the
relation assigns. A soft `same` says the arrow MAY be the identity, and
should be when nothing forbids it; when the solver declines the merge,
substitution mints the arrow. A soft entry also carries the input index,
for the canonical order of section 5.4.

**The rule.** Every node's own repr comes from its own class. Every operand
edge carries one of three relations to its consumer, a property of the
OPERATION, not of the stamps:

1. **Tie** (hard `same`): the operand IS the node's machine value, one
   instruction at one repr for operands and result alike
   (`%OP_REQUIRES_OWN_REPR`; a load and its cell). A tie can refuse, and
   should: `Add:Int` over a `double` operand is a T1 error. A tie is what
   lets the pin on `Constant(9007199254740993) :Int` travel through
   `Coerce(Int->Num)` into the `Add` and decide it `i64`; an obligation
   there would leave the `Add` free and mint the `sitofp` that is the
   defect.
2. **Own** (soft `same`): the value passes THROUGH the node unchanged -- a
   merge arm, a select arm, a short-circuit arm, a store into a cell, a
   value into RETURN, a source `Coerce`'s input. T1 does not make these
   uniform, so the edge is an obligation to deliver the node's own repr,
   discharged in the ARM by an inclusion arrow when the solver declines
   the identity; an operation row here is refused (kind 7), except on a
   source `Coerce`, whose own edge IS the operation (`Coerce(Int->Boolean)`,
   the F8 shape of `019eb316-8b4e-717f-a0a7-0717a425cac4`).
3. **Fixed** (no constraint): the operator CONVERTS its operand as part of
   its semantics (`Divide` numifies, `Concat` stringifies, `If` tests
   truth), so the edge must deliver a fixed repr and the producer's class
   is not consulted: a demand on it would refuse `f() / g()` whenever the
   producer failed to wrap the operand at build time (`019f8cbd`).
   `_required` reads the obligation at substitution.

Comparisons are `shared`: the operands PREFER one class (a soft `same`
between them) and, when the solver declines it, each edge delivers the
row's fallback. `1.5 < 3` compares as NV; `2**53+1 < 2**53+2` compares as
IV exactly. A hard `same` would refuse the first, a fixed `double` would
break the second.

The memory rule is the same relations read off the shape section 3 records:
a load (`PadAccess`) is TIED to its `VarDecl` through `inputs[0]`; a
store's target names the cell (tied; an lvalue edge carries no value and
never takes an arrow) and its value flows IN (own); a `VarDecl`'s
initialiser flows in (own). A cell has one repr, every store converts into
it and every load reads it at that repr. Cells that are not a `VarDecl`,
and loop-carried cells behind memory Phis, are Q6.

```perl
package Chalk::IR::T2::Repr;   # continued from section 5.1: the rows

# A row per op, read by generate (constraints), by _required at substitute
# (obligations) and by ReprInvariant (O2), the last two through
# required_repr, so the three cannot disagree -- and cannot catch a wrong
# row either (O2). A row has `result` (the node's own set is intersected
# with it, hard), `shared` (the object operands prefer one class, and each
# edge delivers this repr where they ended apart), and per position, from
# spec: 'tie', 'own', a fixed repr, or undef (unchecked).
#
# A position %DECIDED does not answer is asked of
# `TypeLibrary::operand_repr_for_ir_op` -- the coercion authority the
# loader already reads (`t/bootstrap/ir/typelibrary-is-the-coercion-authority.t`),
# so T2 and `_insert_str_coercions` cannot disagree; it answers `Concat` and
# the string family, and `singleton_repr` turns its type into a repr where
# the set is one. `_insert_str_coercions` (`Analysis.pm:1427`) is one of
# the two loader-side `Coerce` constructors section 2 names; it writes
# lattice names and is gated by `_coercion_exists` (`Analysis.pm:1356`), a
# `(From, To)` table in lattice vocabulary -- the T1-side counterpart of
# `%ARROW`, in a different namespace, and it stays (section 7). %DECIDED
# holds the rest and is pinned by content at stage 2.
our %DECIDED = (
    # Num admits two reprs and float division has one machine form. The
    # result is pinned too: without it `my $x = 7 / 2; $x % 2` lets the
    # Divide's class default to i64 over double operands -- an fdiv with an
    # i64 result that O2 and O6 both accept; with it the Modulo edge takes
    # the double=>i64 row (Q5). Divide=>double deviates from pp_divide,
    # which keeps an exact integer quotient in IV (18014398509481986 / 2 is
    # 9007199254740993 in perl and ...992 through fdiv): a lost-low-bits
    # miscompile of the worklist's own class, in the other direction, named
    # in section 7 and not closed here.
    Divide  => { result => 'double', operand => 'double' },
    Modulo  => { result => 'i64', operand => 'i64' },
    Concat  => { result => '%Str' },
    Print   => { operand => '%Str' },   # `print` takes a List (TypeLibrary); the node stringifies
    # Comparisons: pp_lt compares IV/IV exactly, else NV. NumCmp's result
    # is i64 (probe: `NumCmp stamp=Int`); the frontend types `<=>` as
    # Boolean (TypeLibrary.pm:486), a divergence this follows the producer on.
    (map { $_ => { shared => 'double', result => '%Bool' } }
        qw(NumEq NumNe NumLt NumLe NumGt NumGe)),
    NumCmp  => { shared => 'double', result => 'i64' },
    # Relation 1: %OP_REQUIRES_OWN_REPR (TypedInvariant.pm:67) and the two it does not list.
    (map { $_ => { operand => 'tie' } } qw(Add Subtract Multiply Negate Power)),
    # Relation 2. A source Coerce with an inclusion label merges with its
    # input when nothing forbids it and is elided; one with a non-inclusion
    # label gets the same soft same, which can never merge -- its stamp's
    # set is disjoint from its input's -- so it always becomes the matching
    # operation row. One row serves both. A Return's own repr is RETURN's
    # (section 2), so `own` there reads repr(RETURN).
    (map { $_ => { operand => 'own' } } qw(Phi DefinedOr And Or Coerce Return)),
    TernaryExpr    => { operand => [ '%Bool', 'own', 'own' ] },   # [0] is the condition (Context.pm:3873)
    # Memory, per the rule above. VarDecl [0] is the name Constant.
    VarDecl        => { operand => [ undef, 'own' ] },
    PadAccess      => { operand => 'tie' },
    Assign         => { operand => [ 'tie', 'own' ] },
    CompoundAssign => { operand => [ 'tie', 'own' ] },
    # If [0] is control (NodeFactory %INPUT_SPECS) and may be a STAMPED
    # statement node (section 3); undef there keeps the fixed spec on the
    # condition alone.
    If             => { operand => [ undef, '%Bool' ] },
);

# Ops the corpus produces whose edges are deliberately NOT checked, each
# with its reason. An op with inputs that has no row and no entry here dies
# in generate: "unlisted" is never a way to pass O2. Membership is pinned by
# name at stage 2.
our %UNCHECKED = (
    Call         => 'call boundary, section 7 (F18/F22): arguments pass at the producer repr',
    Unwind       => 'exception value; no repr contract yet',
    # every container stamp is a singleton in %CANDIDATES, so a container
    # position is a check, not a choice, and TypedInvariant makes it on the
    # source (%OP_PER_POSITION_REPR, and the list rows of %OP_REQUIRED_REPR
    # for Length and Count); the key and the memory operand are Q2/Q6
    Subscript    => 'container operand checked by TypedInvariant on the source',
    PostfixDeref => 'container operand checked by TypedInvariant on the source',
    Length       => 'Str or aggregate operand checked by TypedInvariant on the source',
    Count        => 'aggregate operand checked by TypedInvariant on the source',
);

# The relation at position $i of $op: 'tie', 'own', a fixed repr, or undef
# for an unchecked position -- and undef for every position of an %UNCHECKED
# op, whatever its signature says (`Length` is `Str` to TypeLibrary, an
# aggregate in fact).
sub spec ($op, $i) {
    return undef if $UNCHECKED{$op};
    my $d = $DECIDED{$op} ? $DECIDED{$op}{operand} : undef;
    return ref $d ? $d->[$i] : $d if defined $d;
    return singleton_repr(Chalk::Grammar::Perl::TypeLibrary::operand_repr_for_ir_op($op, $i));
}
sub has_row ($op) {
    return exists $DECIDED{$op}
        || defined Chalk::Grammar::Perl::TypeLibrary::operand_repr_for_ir_op($op, 0);
}

# The repr the edge into $op at position $i must deliver, given the
# consumer's own repr and each operand's ($operand_reprs->[$j], undef where
# position $j holds no object): `shared` is the operand's own repr when
# every object operand ended at one repr and the row's fallback otherwise;
# 'tie' and 'own' are $mine; a fixed repr is itself; undef is an unchecked
# edge. The functor's _required and ReprInvariant's O2 both ask here, so
# the image is checked by the rows that built it.
sub required_repr ($op, $i, $mine, $operand_reprs) {
    if (my $fallback = $DECIDED{$op} && $DECIDED{$op}{shared}) {
        my %at = map { $_ => true } grep { defined } $operand_reprs->@*;
        return keys %at == 1 ? $operand_reprs->[$i] : $fallback;
    }
    my $spec = spec($op, $i) // return undef;
    return $spec eq 'tie' || $spec eq 'own' ? $mine : $spec;
}

# Nodes whose inputs are control edges only: skipped by generate, copied
# verbatim by substitute, and the only operations an unstamped node may have
# in an object position (kind 1 otherwise). A member is control whatever
# stamp it carries (`Proj :Int`, section 3); generate and _edge_image test
# this table before the object predicate. `Unwind` is not here -- its input
# is its message, an object -- and neither are `If` and `Return`, which
# have rows.
our %CONTROL_OP = map { $_ => true } qw(Start Region Loop MemStart Proj);
```

```perl
method generate() {
    for my $node ($source->nodes->@*) {
        my $op = $node->operation;
        next if $Chalk::IR::T2::Repr::CONTROL_OP{$op};
        if ($self->_is_object($node)) {
            my $key = refaddr $node;
            $candidates{$key} = { map { $_ => true } Chalk::IR::T2::Repr::candidates($node)->@* };
            $node_of{$key}    = $node;
        }
        next if exists $Chalk::IR::T2::Repr::UNCHECKED{$op};   # exempt before the die below
        if (!Chalk::IR::T2::Repr::has_row($op)) {
            next if !$node->inputs->@*;
            die "T2: no row and no %UNCHECKED entry for $op (" . $node->id . ")";
        }
        my $row = $Chalk::IR::T2::Repr::DECIDED{$op} // {};
        push @hard, [ 'demand', $self->_key_of($node), [ $row->{result} ], "result of $op" ]
            if $row->{result};

        my $first;   # `shared`: the first object operand, which the rest prefer
        for my $i (0 .. $node->inputs->$#*) {
            my $p = $node->inputs->[$i];
            next if !defined $p;
            next if $Chalk::IR::T2::Repr::CONTROL_OP{ $p->operation };   # control, whatever stamp it carries
            die "T2: unstamped operand " . $p->id . " at $op input[$i] (" . $node->id . ")"
                if !$self->_is_object($p);
            my $pk = refaddr $p;
            if ($row->{shared}) {
                push @soft, [ 'same', $first, $pk, "operands of $op compare at one width", $i ]
                    if defined $first;
                $first //= $pk;
            }
            my $spec = Chalk::IR::T2::Repr::spec($op, $i) // next;
            if ($spec eq 'tie') {
                push @hard, [ 'same', $self->_key_of($node), $pk, "$op input[$i] is its own value" ];
            }
            elsif ($spec eq 'own') {
                push @soft, [ 'same', $self->_key_of($node), $pk, "$op input[$i] passes through", $i ];
            }
            # a fixed repr is an obligation on the edge, read only at substitute
        }
    }
    # Seeded LAST: a refusal on a returned value then names the node, which
    # the loop above reached first in nodes() order, rather than RETURN.
    $self->_seed_return;
    return;
}

# The key a row's `tie`, `own` and `result` refer to: RETURN for a Return,
# the node's own key when it is an object, and a refusal (kind 1) otherwise
# -- a row that needs the node's repr on a node that has none.
method _key_of ($node) {
    return 'RETURN' if $node->operation eq 'Return';
    return refaddr $node if $self->_is_object($node);
    die "T2: unstamped " . $node->operation . " (" . $node->id . ") where its row needs a repr";
}

# RETURN's candidate set, from join_types over the stamps of the Return
# values (a SOURCE-side join, legal there). The sub's return_type on the MOP
# is the preferred seed; how the functor reaches it from $source->mop is Q3,
# and until that is answered the join is the seed. A graph whose Returns
# carry no value has no RETURN object, and no row then refers to it.
# `returns` lists Unwind nodes too (section 3); an Unwind's input is its
# message, not a returned value, and does not seed RETURN.
method _seed_return() {
    my $stamp;
    for my $r (grep { $_->operation eq 'Return' } $source->returns->@*) {
        my ($v) = grep { defined && $self->_is_object($_) } $r->inputs->@*;
        $stamp = Chalk::Grammar::Perl::TypeLibrary::join_types($stamp, $v->stamp) if $v;
    }
    return if !defined $stamp;
    $candidates{RETURN} = { map { $_ => true }
        Chalk::IR::T2::Repr::candidates_of_stamp($stamp, 'RETURN')->@* };
    return;
}
```

The corpus produces 49 distinct ops (`grep -oE "= [A-Z][A-Za-z]+\(" t/corpus/mdtest/*.md`;
`ir` fence syntax, re-measured on wire-loaded graphs at stage 2). Those with
inputs and no row today -- `ArrayLiteral`, `FieldAccess`, `RegexMatch`,
`HashLiteral`, `Not`, `RegexCapture`, `ListAppend`, `RegexSubst`, `RefType`,
`Ref`, `Match`, `Defined` -- are stage-2 work under the same relations
(`Not` is relation 3 at `%Bool`), or an `%UNCHECKED` entry with a reason;
`StrEq` and `StrNe` already have rows through `operand_repr_for_ir_op`.

### 5.3 SOLVE: union-find, then intersect

The carrier is the powerset of each node's candidates ordered by inclusion;
meet is intersection. With `same` as equivalence and `demand` as a unary
restriction, the fixpoint is not iterative: union the hard `same`
constraints, then fold intersection over each class.

```perl
method solve() {
    # Constraints already hold keys (generate), so there is nothing to
    # translate here. %set is the field; it outlives solve for default.
    for my $key (keys %candidates) {
        $class{$key}  = $key;
        $min_id{$key} = $self->_id_of($key);
    }
    $self->_union($_->[1], $_->[2]) for grep { $_->[0] eq 'same' } @hard;

    for my $addr (keys %candidates) {
        my $root = $self->_find($addr);
        $set{$root} //= { map { $_ => true } keys $candidates{$addr}->%* };
        $set{$root} = _intersect($set{$root}, $candidates{$addr});
    }
    for my $d (grep { $_->[0] eq 'demand' } @hard) {
        my $root = $self->_find($d->[1]);
        $set{$root} = _intersect($set{$root}, { map { $_ => true } $d->[2]->@* });
    }
    # Report order by smallest member id, never by address (roots are refaddrs).
    for my $root (sort { $min_id{$a} cmp $min_id{$b} } keys %set) {
        my @left = sort keys $set{$root}->%*;
        die $self->_conflict_report($root) if !@left;   # loud, names the constraints
        $self->_decide($root, $left[0], 'pinned') if @left == 1;
    }
    # classes with @left > 1 remain free for phase 3
}
```

Properties, each a test: ORDER-INDEPENDENT (union and intersection are
commutative and associative; the test shuffles the node list and the
constraint lists and compares `repr(find(n))` and `why(n)` per source node,
keyed by `n->id` -- `%repr` is keyed by class-root refaddr and must not be
the thing compared); TERMINATES TRIVIALLY (no iteration); A HARD EMPTY SET
IS LOUD (it names the class members and every constraint that touched the
class, and is never resolved by picking a survivor).

The fixtures, with RETURN present (every gate in section 6 counts against
these). Every fixture is SEEDED THE LOADER'S WAY: each node is `merge`d
into its `Chalk::IR::Graph` (`JSON.pm:839-846` merges the `control_in`
chain behind each `Return`; `MdtestCorpus.pm:679,693` merges each body
statement), because `nodes()` membership is the cache and follows no
`control_in` edge (clause 10 (e)). A fixture built by `Graph->new(start,
returns)` alone is a different graph: a statement-position node behind
`control_in` is not a member, `generate` never seeds its key, and `_find`
on that key recurses into `undef` -- the failure surfaces as a wrong
message from a later phase, never as the refusal the fixture was written
to show. The `Int cell = 2.5` fixture below reaches kind 7 only when
seeded this way:

    2^53:
    %3 = Constant(9007199254740993) [Int]   {i64}
    %4 = Coerce(%3)                 [Num]   {i64,double}
    %5 = Constant(0)                [Num]   {i64,double}  -- 0.0 is integral
    %6 = Add(%4, %5)                [Num]   {i64,double}
    hard same(%4,%5,%6)              -> class A = {i64,double}, free   (Add: tie)
    soft same(%4,%3), soft same(RETURN,%6)   -> phase 3
    result: everything i64, the Coerce elided; 4 objects in, 3 out

    1 + 1.5:
    %1 = Constant(1)   [Int]  {i64}
    %2 = Coerce(%1)    [Num]  {i64,double}
    %3 = Constant(1.5) [Num]  {double}          -- fractional, i64 removed
    %4 = Add(%2, %3)   [Num]  {i64,double}
    hard same(%2,%3,%4)              -> {double}, pinned
    soft same(%2,%1), soft same(RETURN,%4)
    result: %2's merge declined, %2 becomes sitofp; 4 in, 4 out

    logical.md:247 (`my $x = $a // return 99`, GREEN today):
    %c99 = Constant(99)    [Int]    {i64}
    %und = Constant(undef) [Undef]  {%Undef}
    %phi = Phi(%c99, %und) [Scalar] {%Slot}
    soft same(%phi,%c99), soft same(%phi,%und), soft same(RETURN,%phi)
    result: no merge; Phi(Coerce(box_int, %c99), Coerce(box_undef, %und)) :%Slot
            (O2, in the arms); 3 in, 5 out

    cell (`my $x = 7 / 2; $x + 1`):
    %div = Divide(7, 2)          [Num]  {double}       pinned by its result row
    %vx  = VarDecl("$x", %div)   [Num]  {i64,double}   init edge: own
    %rx  = PadAccess(%vx)        [Num]                 tie -> class C = {%vx,%rx}
    %one = Constant(1)           [Int]  {i64}
    %co  = Coerce(%one)          [Num]                 Add tie -> C = {%vx,%rx,%co,%add}
    %add = Add(%rx, %co)         [Num]
    soft same(%vx,%div), soft same(%co,%one), soft same(RETURN,%add)
            -> phase 3, where the first two COMPETE for C
    result: C double, %co's merge declined (sitofp on the Constant), the two
            Divide operands take sitofp; 9 in, 11 out

    1.5 < 3:
    %a  = Constant(1.5) [Num]     {double}
    %b  = Constant(3)   [Int]     {i64}
    %lt = NumLt(%a, %b) [Boolean] {%Bool}   result row
    soft same(%a,%b) (shared), soft same(RETURN,%lt)
    result: shared declined, both edges deliver double: sitofp on %b;
            3 in, 4 out.  NumGt(%n :Int, %zero :Int): shared merges, icmp i64

    Int cell = 2.5 (`my $x = 1; $x = 2.5; return $x`, cell stamped Int):
    class {%vx,%lhs,%as,%rx} pinned i64; %h = Constant(2.5) {double}
    soft same(%as,%h) declined; substitute: own edge, double=>i64 is an
    operation row, consumer is Assign -> REFUSED, kind 7

Three more fixtures are PERL-LEGAL programs whose T1 is consistent, and the
printed code refuses all three as kind 7. They are the shapes section 3.3
records the wire delivering bare on the `Num` spine, and their verdict is
not this document's to fix: it is Q1 (section 8), perigrin's decision,
and each branch of Q1 gives them a different verdict, costed here so the
decision can be taken against it:

    Num merge (`my $x = $c ? 1 : 2.5`, as a Phi; the same as TernaryExpr):
    %c1  = Constant(1)    [Int] {i64}
    %c25 = Constant(2.5)  [Num] {double}
    %phi = Phi(%c1, %c25) [Num] {i64,double}
    soft same(%phi,%c1), soft same(%phi,%c25), soft same(RETURN,%phi)
    default pass (a): joint(%phi,%c25) = {double}, merged, %phi double;
    joint(%phi,%c1) = {} -> declined; substitute: own edge %c1 -> %phi
    asks i64=>double, an operation row (sitofp) -> REFUSED, kind 7

    Two returns (`return 1 if $c; return 1.5`): RETURN seeded from the join
    `Num` {i64,double}; soft same(RETURN, Constant 1 :Int), soft
    same(RETURN, Constant 1.5 :Num); the same passes -> RETURN double, the
    `Int` arm asks i64=>double on a Return's own edge -> REFUSED, kind 7

    Under Q1 (a) REFUSE: all three stay refusals, the kind-7 count over
    perl-accepted programs is the measure of T1's clause-7 debt, and the
    count falls only when the producer writes `Coerce(Int->Num)` on the
    arm -- a change to T1, which section 7 scopes out of this document.
    Under Q1 (b) REPAIR: the arm takes the `i64=>double` row, the functor
    records the repair as debt against clause 7, and the minted `sitofp`
    is exactly the widening kind 7 exists to refuse -- exact below 2^53,
    lossy above it (the worklist case, section 1) -- so (b) accepts these
    programs at the price of a silent-until-2^53 conversion that only the
    debt list makes visible. Neither branch is taken here; stage 3's
    gate reports the kind-7 count on perl-accepted programs so that Q1 is
    decided against a number.

### 5.4 DEFAULT: named rules, canonical order

Whatever `solve` left free has no principal representation: `i64` and
`double` are incomparable and the emitter needs one. Defaulting is forced,
done LAST, by named rules, in a canonical order.

```perl
method default() {
    # Rule 1, identity-preserving, in two passes. A soft pair is merged when
    # the merge keeps the class non-empty. Pass (a) merges every pair whose
    # joint set is exactly {double}, repeated until no merge happens; pass
    # (b) merges the rest. The two passes are what make rule 1
    # order-independent: after (a) no class that can still reach `double`
    # through a soft edge is free, so every merge in (b) either joins two
    # free classes or pulls one to `i64`, and a class solve left free ends
    # `i64` exactly when its soft component holds an `i64` pin and no
    # `double` one it can still merge with. The sort fixes only the order
    # in which a conflict would be reported: (id of the entry's first end
    # -- the consumer for an own edge, the FIRST OBJECT OPERAND for a
    # shared pair -- then the input index, then the second end's id),
    # every part a property of the graph.
    my @pending = sort {
           $self->_id_of($a->[1]) cmp $self->_id_of($b->[1])
        || $a->[4] <=> $b->[4]
        || $self->_id_of($a->[2]) cmp $self->_id_of($b->[2])
    } @soft;
    my $merged = true;
    while ($merged) {
        $merged = false;
        for my $s (@pending) {
            my $joint = $self->_joint($s) // next;
            next unless keys %$joint == 1 && exists $joint->{double};
            $self->_merge($s, $joint);
            $merged = true;
        }
    }
    for my $s (@pending) {
        my $joint = $self->_joint($s) // next;
        $self->_merge($s, $joint);
    }
    # Rule 2, the residue: a free class takes the widest supported
    # representation. Iterates ROOTS only, and only the ones still
    # undecided; _decide dies if the set holds nothing the rule knows how
    # to choose from, which is impossible under the version-one table and
    # reachable the moment %CANDIDATES widens.
    for my $root (grep { !exists $repr{$_} } $self->_roots) {
        my ($choice) = grep { exists $set{$root}->{$_} } qw(double i64);
        $self->_decide($root, $choice, 'default:widest');
    }
}

# The joint set of a soft pair, or undef when the pair is already one class
# or the merge would empty it (the arrow must convert).
method _joint ($s) {
    my ($ra, $rb) = map { $self->_find($_) } $s->@[1,2];
    return undef if $ra eq $rb;
    my $joint = _intersect($set{$ra}, $set{$rb});
    return %$joint ? $joint : undef;
}

# Merge a soft pair. A merge that leaves one member DECIDES the class here,
# with rule 1 as its provenance; a class solve had already pinned keeps that
# pin and gains this rule. Rule 2 must not see it again.
method _merge ($s, $joint) {
    my $root = $self->_union($s->@[1,2]);
    $set{$root} = $joint;
    $self->_decide($root, (keys %$joint)[0], 'default:identity-preserving')
        if keys %$joint == 1;
    return;
}
```

Pass (a) is `pp_add`'s own rule: one NV operand makes the operation NV.

### 5.5 SUBSTITUTE: build the image

Only now is anything written, and it is written into a new graph. The walk
is over `$source->nodes`, in that method's order: a topological sort by
producer edges over the MEMBERSHIP set, and membership is the graph's
cache -- pass 1 of `nodes()` (`Graph.pm:200-226`) seeds from every cached
node and expands over `inputs` and cache-filtered `consumers`, never over
`control_in`. A statement-position `Call`, `Print` or `Assign` that hangs
off a `Return`'s `control_in` is visited because the PRODUCER merged it
(`JSON.pm:839-846`, `MdtestCorpus.pm:693`), not because the walk follows
the edge. A post-order over `inputs` from the returns is NOT sufficient
for the same reason: it never reaches that node.

The image is populated under the same rule, so `substitute` MERGES every
image node into the new graph. `Graph->new(start, returns, mop)` seeds
only its two arguments (`Graph.pm:35-44`); an image node reachable only
through `control_in` is then absent from the image's `nodes()`, and the
image passes O1, O2, O6, O8 and O9 while being a different program --
the D8b class (`2026-09-02-d8b-try-catch-drops-every-print.md`). Measured
on an identity copy built exactly as `_image_of` builds it, source seeded
the loader's way: `print 7; return 1` is 6 source nodes (`Start Constant
Return Constant Coerce Print`) and the unmerged image is 3 (`Start
Constant Return` -- the `Print`, its `Coerce` and its `Constant` gone);
`return 1 if $c; return "x"` is 9 source nodes and the unmerged image is 5
(the `If`, both `Proj`s and the condition `Constant` gone). The control:
the SOURCE rebuilt by `Graph->new(start, returns)` alone reads the same 3
and 5, so what is lost is membership, not edges. With every image node
merged the counts are 6 and 9. O10 is the invariant that fails on the
unmerged image, and the stage-3 copy test asserts `nodes()` COUNT
EQUALITY, not only per-node pairs.

Edges are copied by kind. `inputs` are the data edges and take the arrow
rule; `control_in` and `region` are copied as the image of the node they
point at, with no arrow. Two facts shape the walk:

- `nodes()` orders by `inputs` and a Phi's `region` ONLY (`Graph.pm`, pass
  2, `$producers_of`); `control_in` is not a producer edge, and roots sort
  by id, so a `Return#N` can be finalised before the statement-position
  `VarDecl#M` its `control_in` names. `_image_of` images `control_in` and
  `region` targets itself, before the node.
- The back-edge in `inputs[1]` of a loop Phi (`Phi::set_backedge`) and of
  a `Loop` (clause 10 (c)) is reached again through the body before the
  node's image exists; `_image_of` skips slot 1 on both, and `substitute`
  patches it after the walk through the same setters, the Phi's through
  the edge rule.

```perl
method substitute() {
    $self->_image_of($_) for $source->nodes->@*;
    # Back-references, once every image exists.
    for my $phi (@loop_phis) {
        $image{refaddr $phi}->set_backedge($self->_edge_image($phi, 1, $self->_own_repr($phi)));
    }
    for my $loop (@loops) {
        my $back = $loop->inputs->[1];
        $image{refaddr $loop}->set_backedge_ctrl($image{refaddr $back}) if defined $back;
    }
    # set_region on an If or a Loop also installs Region.head (If.pm, Loop.pm:40)
    for my $head (@regioned) {
        $image{refaddr $head}->set_region($image{refaddr $head->region}) if defined $head->region;
    }
    for my $phi (@phis) {
        my $preds = $phi->predecessors // next;
        $image{refaddr $phi}->set_predecessors([ map { $image{refaddr $_} } $preds->@* ]);
    }
    my @returns = map { $image{refaddr $_} } $source->returns->@*;
    my $graph = Chalk::IR::Graph->new(
        start => $image{refaddr $source->start}, returns => \@returns, mop => $source->mop);
    # MEMBERSHIP IS THE CACHE (Graph.pm:200-226): new() seeds only start and
    # returns, and nodes() never follows control_in, so every image node is
    # merged, the way the loader merges the control chain (JSON.pm:839-846).
    # An elided source Coerce maps to its input's image, so %image holds
    # duplicates; merge is idempotent on them. Sorted by id, so the cache is
    # populated in one order (O9).
    $graph->merge($_) for sort { $a->id cmp $b->id } values %image;
    return $graph;
}

method _image_of ($node) {
    my $addr = refaddr $node;
    return $image{$addr} if exists $image{$addr};

    my $op     = $node->operation;
    my $ctrl   = defined $node->control_in ? $self->_image_of($node->control_in) : undef;
    my $region = $op eq 'Phi' && defined $node->region ? $self->_image_of($node->region) : undef;
    my $loop_phi = defined $region && $node->region->operation eq 'Loop';
    my $loop     = $op eq 'Loop';
    push @loop_phis, $node if $loop_phi;
    push @loops,     $node if $loop;
    push @regioned,  $node if $loop || $op eq 'If';
    push @phis,      $node if $op eq 'Phi';

    # $mine is undef for a node that is not an object (If, Region, ...) and
    # repr(RETURN) for a Return. Its inputs still go through the edge rule:
    # _required knows the fixed rows for stampless consumers.
    my $mine = $self->_own_repr($node);
    my @in;
    for my $i (0 .. $node->inputs->$#*) {
        my $p = $node->inputs->[$i];
        push @in, (!defined $p || (($loop_phi || $loop) && $i == 1))
            ? undef                                     # absent, or a back-edge patched by substitute
            : $self->_edge_image($node, $i, $mine);
    }
    # A source Coerce is its own input edge: the edge rule elided it (identity)
    # or minted the arrow. Either way the node itself is not copied.
    return $image{$addr} = $in[0] if $op eq 'Coerce';

    # The copy's stamp is the object's repr; a node that is not an object
    # (a Return, whose $mine is RETURN's repr for the edge rule only) stays
    # unstamped, as O1 requires. constructor_args carries no node-valued
    # field; a Phi's region is imaged above, predecessors and an If's or
    # Loop's region are patched by substitute.
    my $stamp = $self->_is_object($node) ? $mine : undef;
    my %args  = $node->constructor_args;
    $args{region} = $region if defined $region;
    my $copy = $factory->make($op, %args, inputs => \@in, stamp => $stamp);
    # make() hash-conses data ops by content, and content excludes stamp
    # (NodeFactory.pm, the _tmp/content_hash path): on a cache hit the stamp
    # argument is IGNORED and the earlier node returned. Two source objects
    # with equal content and different classes would then share one repr;
    # the last-writer-wins Constant of section 3 is how that can arise.
    die "T2: hash-cons collision on " . $node->id . ": image is "
      . ($copy->stamp // 'unstamped') . ", class says " . ($stamp // 'unstamped')
        if ($copy->stamp // '') ne ($stamp // '');
    $copy->set_control_in($ctrl) if defined $ctrl;
    return $image{$addr} = $copy;
}

# The image of the data edge into $node at position $i: the producer's image,
# converted by an arrow when the row requires a repr the producer did not
# choose. A non-object operand (control) takes no arrow.
method _edge_image ($node, $i, $mine) {
    my $p   = $node->inputs->[$i];
    my $img = $self->_image_of($p);
    return $img if $Chalk::IR::T2::Repr::CONTROL_OP{ $p->operation } || !$self->_is_object($p);
    my $have = $repr{$self->_find(refaddr $p)};
    my $need = $self->_required($node, $i, $mine, $have);
    return $need eq $have ? $img : $self->_arrow($img, $have, $need);
}

# A node's own repr: repr(RETURN) for a Return, its class's repr for an
# object, undef otherwise -- and undef for a %CONTROL_OP member whatever
# stamp it carries (section 3), which is then copied unstamped.
method _own_repr ($node) {
    return undef if $Chalk::IR::T2::Repr::CONTROL_OP{ $node->operation };
    return exists $class{RETURN} ? $repr{$self->_find('RETURN')} : undef
        if $node->operation eq 'Return';
    return $self->_is_object($node) ? $repr{$self->_find(refaddr $node)} : undef;
}

# What the edge into $node at position $i must deliver: Repr::required_repr
# over the same rows generate read, given the consumer's repr and every
# object operand's; undef (an unchecked position, an %UNCHECKED op, a
# control operand) is $have. The two refusals are the functor's, not the
# rows': a tie that ended apart, and an operation row on a pass-through
# edge.
method _required ($node, $i, $mine, $have) {
    my $op   = $node->operation;
    my $spec = Chalk::IR::T2::Repr::spec($op, $i) // '';
    die "T2: tied operand of " . $node->id . " has $have, node has $mine"
        if $spec eq 'tie' && $have ne $mine;
    # Relation 2 delivers the value UNCHANGED. An operation row here is a
    # conversion the source never wrote -- a truncation, a truth test, a
    # checked unbox, a widening that loses bits (refusal kind 7); a source
    # Coerce is the one consumer whose own edge IS the operation.
    die "T2: $op input[$i] (" . $node->id
      . ") would take operation row $have=>$mine on a pass-through edge"
        if $spec eq 'own' && $op ne 'Coerce' && Chalk::IR::T2::Repr::is_operation("$have=>$mine");
    return Chalk::IR::T2::Repr::required_repr($op, $i, $mine, [
        map { defined $_ && !$Chalk::IR::T2::Repr::CONTROL_OP{ $_->operation } && $self->_is_object($_)
                ? $repr{ $self->_find(refaddr $_) } : undef } $node->inputs->@* ]) // $have;
}

# F on one morphism. The one place in lib/ that constructs a Coerce in REPR
# vocabulary; the loader's two constructors (Analysis.pm:1427, :1592) write
# lattice names, and a grep for the constructor call plus a check of which
# namespace each site passes is the test (section 2). Two eliminations,
# each resting on a stated law:
#   - a ROUND TRIP, `X=>%Slot` then `%Slot=>X`, is the identity because a
#     checked unbox undoes the box it checks for (`unbox_X_checked . box_X
#     = id`, pinned per box row at stage 1). It is read only when the
#     INNER arrow is the box; unbox-then-box is a check the source wrote,
#     and it stands.
#   - a chain of two INCLUSION rows collapses onto the direct row when that
#     row is an inclusion (the coherence law makes it sound). A chain
#     through an operation, or whose direct row is one, stands as two
#     nodes: the kind-7 guard is a membership test on the pair `$have=>$to`,
#     and a pair it passed must not become one it would have refused. A
#     pair with no direct row dies here (kind 6).
# The minted node carries its own repr as its stamp (O2: to_repr eq stamp).
method _arrow ($img, $from, $to) {
    if ($img->operation eq 'Coerce') {
        my $direct = $img->from_repr;
        return $img->inputs->[0]
            if $from eq '%Slot' && $direct eq $to
            && Chalk::IR::T2::Repr::is_inclusion("$direct=>$from");
        ($img, $from) = ($img->inputs->[0], $direct)
            if Chalk::IR::T2::Repr::is_inclusion("$direct=>$from")
            && Chalk::IR::T2::Repr::is_inclusion("$from=>$to")
            && !Chalk::IR::T2::Repr::is_operation("$direct=>$to");
    }
    die "T2: no arrow $from => $to" unless exists $Chalk::IR::T2::Repr::ARROW{"$from=>$to"};
    return $factory->make('Coerce', from_repr => $from, to_repr => $to, inputs => [$img], stamp => $to);
}
```

Under the version-one table the only chain of two inclusions is
`i64=>%Str=>%Slot`, so the collapse has exactly one instance --
`Coerce(Int->Str)` of `3` into a `Scalar` merge images as `box_int`, exact
under `==` and `eq` while its slot tag reads int where perl's reads string,
a difference outside the inclusion criterion (if the tag ever joins it,
`i64=>%Str` becomes an operation and the collapse has no instance) -- and
the direct-row test is what keeps a row added at stage 3 honest. The lossy
own edge is refused before `_arrow`
is reached: `Phi :Int` over `Coerce(Constant 2.5 :Num -> Scalar)` asks
`%Slot=>i64`, a checked unbox, an operation, and `_required` names the Phi
(kind 7); T1's `Int` claim over a `Scalar` arm is the same inconsistency as
the `Int` cell of section 5.3. Both are pinned at stage 3.

`constructor_args` is NEW WORK: a method on `Chalk::IR::Node` returning the
per-class non-node `:param` fields as a list (`Constant`: `value`,
`const_type`; `Coerce`: `from_repr`, `to_repr`; `Return`: `synthetic`;
`EnvRead`: `key`; ...). Node-valued fields are excluded: `Phi.region` is
passed by `_image_of`; `Phi.predecessors` and the `region` of an `If` or
`Loop` are set by `substitute` through `set_predecessors` (new, beside
`set_backedge`) and `set_region` (`If.pm`, `Loop.pm:40`), which installs
`Region.head` as well. The base implementation dies, so a class
without an override is loud; overrides are scoped to the 49 ops the corpus
produces (section 5.2), not to the 94 classes under `lib/Chalk/IR/Node/`.
Passing `stamp =>` at construction reaches a `:param` on `Node` that
`Node.pm:52-64` fences off ("INVISIBLE TO INFERENCE": nine loader passes
read a defined repr as "already decided"); it is safe here because the
image is built after inference from a solved `%repr` and never enters those
passes.

`%ARROW` is consulted only in `_arrow`, AFTER solving, for pairs the
solution already decided: an empty HARD set is a refusal, a declined SOFT
merge becomes a conversion.

## 6. Staging

Four stages, a gate each. The corpus gate must read 223 against `b96087c`
after every stage until stage 4 says otherwise -- and 223 is the MEASURED
value, not what the suite pins: `son-corpus-wide.t:548` pins the floor at
220, so a stage landing at 221 passes the suite and violates this sentence
silently. Stage 1's first commit raises the pinned floor to 223 so that
"the gate reads 223" is enforced by the suite and not by this document. The graph copy with
`constructor_args` (stage 3) is its own PR-sized change. Stage 1 does not
start until the registry trigger of section 5.1 is answered.

**Stage 1 -- vocabulary, object seed, arrow table.** `Chalk::IR::T2::Repr`
with `%CANDIDATES`, `is_repr`, `singleton_repr`, `candidates`,
`candidates_of_stamp`, `_is_integral`, `%ARROW`, `is_inclusion`,
`is_operation`; `Serialize::JSON::is_lowerable_stamp` reads `keys
%CANDIDATES` minus `CodeRef` -- `%LOWERABLE_STAMP` (`JSON.pm:88`) has eleven
members and is a contract with the backend, and `%Code` joins it when
019f51e7-82c6 lands the spelling.
Test file: `t/bootstrap/ir/t2-functor-repr.t`. Gate: `%CANDIDATES` pinned
by content, all twelve rows; `is_lowerable_stamp` is true for every key of
`%CANDIDATES` but `CodeRef`; `Constant(1.5)` yields `{double}`,
`Constant(0)` stamped `Num` yields `{i64, double}`, and `Constant(3)`
stamped `Int` yields `{i64}`; `_is_integral` admits IV_MAX, IV_MIN,
9007199254740993, "1e3", "0.0", -0.0 and rejects 2**63,
9223372036854775808, 1e300, 1.5, Inf, NaN; `is_lattice_type` is false for
every member of `%REPR`; `candidates_of_stamp` dies, with a message naming
the kind, on each of refusal kinds 1-5; every row printed in section 5.1's
`%ARROW` exists with its kind, pinned by content. The coherence law:
`coercion-composition-law.t` is re-run with every route expressed as a
composition of `%ARROW` inclusion rows -- the two 2^53 rows in
`Int->Num->Scalar` move from DIFFER to AGREE, and the characterisation
table is UPDATED to say so (the test is built so that a newly fixed row
fails until moved); no previously-agreeing row regresses; the probe set
carries `0.1+0.2` and `9007199254740993`; the NEGATIVE CONTROL runs on the
operation rows, each asserted to DISAGREE with the direct row on its probe
(`format_num` then `box_str` against `box_num` on
`0.1+0.2`; `sitofp` then `box_num` against `box_int` on
`9007199254740993`; each `unbox_*_checked` refuses a slot of another tag)
-- a probe set without those values passes the law vacuously on exactly
those rows, and the control is what keeps the split of section 5.1
measured rather than hand-classified; each box row is asserted against the
retraction law `unbox_X_checked . box_X = id` on the same probes.

**Stage 2 -- the solver: GENERATE, SOLVE, DEFAULT.** Before the stage is
scoped, refusal kind 1 is MEASURED on wire-loaded corpus graphs (not on
`ir`-fence graphs, whose 35 `VarDecl`s are all stamped by the harness): if
`VarDecl` commonly arrives unstamped, the cell's seed becomes the join of
its store values, and that is a Q2 decision, not a silent widening. The
rows of section 5.2 -- `%DECIDED`, `%UNCHECKED`, `%CONTROL_OP`, `spec`,
`has_row`, `required_repr` -- land in `Chalk::IR::T2::Repr` here. Test
file: `t/bootstrap/ir/t2-functor-solve.t`. Gate, `generate`: the constraint
multiset of each fixture of section 5.3, exactly, RETURN included; every
source node's `(content_hash, stamp)` pair is unchanged; an op with
inputs and no row makes `generate` die, shown on a hand-built graph;
`%UNCHECKED`'s membership is pinned by name and `%DECIDED` by content;
RETURN's seed on a graph with `return 1` and a `die "boom"` arm is `Int`,
not the join with the `Unwind`'s `Str` message; over all loadable corpus
programs the list of ops with inputs and no row is EMPTY; the method runs
without dying except on an object it refuses, and the refusals are counted
in five columns -- kinds 1-5 -- each naming its node; the accepted count
`N2` is pinned in the test and may only rise. Gate, `solve` and `default`:
each fixture of section 5.3 solves to its stated result, the cell graph in
BOTH orders of its soft pairs, and the 2^53 graph's `why` names both
`pinned` and `default:identity-preserving`; the `Int cell = 2.5` graph
solves (its refusal is stage 3's); shuffling the node list AND the constraint
lists before `solve` gives identical `repr(find(n))` and identical `why(n)`
for every `n`, keyed by `n->id`, on every fixture above and on a generated
family of random own/tie/shared graphs; `_decide` on a decided class with
a different choice dies; `_union` returns the smaller-id root regardless of
argument order; over all loadable corpus programs the number of hard-empty
classes is measured and reported, and STAGE 3 DOES NOT START while it is
non-zero on a program perl accepts -- that is Q1 going back to perigrin, as
a blocking condition in this gate rather than a note.

**Stage 3 -- SUBSTITUTE, the checker, the fence.** Prerequisite, its own
deliverable with its own test (`t/bootstrap/ir/t2-graph-copy.t`): the
graph deep-copy of section 5.5, shown by copying every loadable corpus
graph with the identity on every edge, asserting that the copy's `nodes()`
COUNT EQUALS the source's (per-node pairs alone pass a copy that dropped
every node behind a `control_in` edge: the 6-to-3 image of section 5.5
pairs its three survivors perfectly), comparing `(content_hash, stamp)`
node by node, and asserting that every node-valued field of every copied
node (the edges and fields section 5.5 names, `head` on `Region` included)
is defined exactly when the source's is and then holds a node of the COPY
by refaddr, never of the source -- `undef` where the source held a node is
a dropped edge, not a pass. The image is made
expressible in the corpus: an `ir-t2` fenced block in
`t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm` and `son-corpus-wide.t`, same
grammar as `ir` but the `:stamp` positions carry repr names and
`Coerce(%x : i64 -> double)` carries reprs. Both stamp captures reject
`%`; each becomes `([%\w]+)`; `ir-t2` is a fourth fence branch. The `ir`
grammar's `:Control` annotation has no place in an
`ir-t2` block. The printer, `MdtestCorpus::print_ir_t2($graph)`, emits a
graph in `ir-t2` syntax in `nodes()` order, so the round-trip is
parse-then-print-then-compare; `logical.md:247`, `arithmetic.md:236-260`
and one `Divide` case carry both blocks. Test files:
`t/bootstrap/ir/t2-functor-image.t`, `t/bootstrap/corpus/ir-t2-fence.t`.
Gate: image node counts are PINNED per fixture of section 5.3; a
graph whose statement-position node's id sorts after its `Return` images
with the `control_in` edge set; a graph with a REAL `Loop` node --
`Loop(Start, body)`, a loop Phi on it, `If(Loop, NumLt(phi, n))`, its
`Proj`s, `set_backedge_ctrl` to the body's control -- images without
recursion, its Phi's back-edge is the arrowed body image, and its Loop's
`inputs[1]` and `region` are image nodes; two source objects with equal
content and different classes make `_image_of` die on the hash-cons
collision; NEGATIVE: `my $x = 1; $x = 2.5; return $x` with the cell
stamped `Int`, and `Int cell += 1.5`, both die with refusal kind 7 naming
the store, and `Coerce(Int->Boolean)` feeding an `And` arm does NOT (its
`i64=>%Bool` is the image of a source `Coerce`); `Phi :Int` over
`Coerce(Constant 2.5 :Num -> Scalar)` and `Constant 1 :Int`, and the same
value stored into an `Int` cell by `Assign`, die with kind 7 naming the
Phi and the store (`%Slot=>i64` is an operation) and no `trunc_num`
anywhere; `Coerce(Scalar->Int)` over that `Coerce(Num->Scalar)` into a
`Scalar` merge images as `box_int` over `unbox_int_checked` over
`box_num`, three nodes, the check standing (the round trip is read
box-then-unbox only); `Coerce(Int->Str)` of `3` into a `Scalar` merge
images as ONE `box_int` node, the `format_int` elided (the inclusion
chain of section 5.5); `Coerce(Num->Str)` of `0.1+0.2` into a `Scalar`
cell, and into a `Scalar` merge, images as `box_str` over `format_num`,
never `box_num` alone (the string the program wrote is what the cell
holds), while the same `Coerce` into `Concat` images as `format_num` on
the fixed `%Str` edge; `Modulo` over `Coerce(Int->Scalar)` of a
`Coerce(Num->Int)` images as `trunc_num` alone on the fixed edge, the
round trip elided; `ReprInvariant` passes on the image of every corpus
program the functor accepts, with the floor `N4 of 223 images built`
pinned (223 being the measured gate at `b96087c`, section 6's opening)
and `N4 >= N2`, and on each such image `apply` asserts that a
non-control source node is an object iff its image is stamped (O1's
source half, which a pure `check` cannot see) and asserts O10 against
the source (the op multiset minus `Coerce`, the preimage bijection, and
the node-count identity); every refusal names its node and kind, now in
seven columns; the kind-7 column is reported SEPARATELY for programs perl
accepts, because that number is what Q1 is decided against (the three
perl-legal fixtures of section 5.3 sit in it); and the kind-6 column is ZERO over the corpus -- that is
how `%ARROW` is "completed by measurement", one executed probe per added
row (`coercion-composition-law.t` for an inclusion row, a hand fixture
under `lli` for an operation row); for each of O1, O2, O6, O8, O9, O10, a
hand-built image violating only that invariant fails on it and nothing
else -- O10's is the unmerged image of section 5.5, which passes the
other five; `build_graph_from_ir` over an `ir-t2` block yields a graph on which
every stamped node satisfies `Repr::is_repr`, `print_ir_t2` of that graph
yields the block's text, a block containing a Chalk type name (`:Int`,
`Coerce(%x : Int -> Num)`) or `:Control` is REJECTED with a message naming
the offending token, the `ir-t2` blocks match `apply`'s image, and
existing `ir` assertions are unaffected; the coherence law's route ends
are read from `apply` on the route's probe graph, not hand-picked (an
`i64->i64->%Slot` picked by hand agrees trivially and says nothing about
the solver); `apply` twice, and `apply` under shuffled constraint lists,
give images identical in `(content_hash, stamp)` and `why`, node by node
(O9); the `sub f{6} sub g{3} f()/g()` shape of `019f8cbd` is a FIXTURE
whose image carries `Coerce(i64 => double)` on both `Divide` edges and
passes `ReprInvariant`. `my $x = 7 / 2; $x % 2` is a fixture marked TODO
until Q5 settles the `double=>i64` row. At the end of this stage the
existing T2 and its four tests are deleted (section 7); the
`t2-functor-*.t` and `t2-graph-copy.t` files of stages 1-3 are not among
them.

**Stage 4 -- lowering consumes the image.** Behind the environment flag
`CHALK_T2_IMAGE`, off by default and read once in
`Chalk::Target::LLVM::Context`, the LLVM target lowers the functor's image
instead of the source. The emitter dispatches on CHALK NAMES; a minted
arrow carries `i64`, `double`, `%Bool`, and falls through every arm
unmatched. The boundary is ONE table at the flag, derived from the object map,
applied in exactly two READS when the flag is on -- a node's `stamp`, and
`from_repr`/`to_repr` at the top of `_emit_coercion`:

```
my %EMITTER_SPELLING = ((map { $CANDIDATES{$_}[0] => $_ } grep { $CANDIDATES{$_}->@* == 1 } keys %CANDIDATES),
    double => 'Num', '%Slot' => 'Slot');
```

`%Slot` spells `Slot`, not `Scalar`: `Analysis::_is_narrowed` counts
`Scalar` as un-narrowed and `Slot` as narrowed, and an image value is
decided; the one emitter read that falls back to a `Coerce`'s `from_repr`
when the operand is un-narrowed reads the operand's stamp in the image,
which O2 makes the same thing, and a `Scalar`-sourced `Coerce` fixture
says so. Two reads is not two textual sites: `->stamp` is read at many
sites in `Context.pm` with no accessor between them and the node, so the
stamp read is one wrapper, `_stamp_of($node)`, and routing every site
through it is the deliverable. `double=>i64` reaches the `Num->Int` arm's
`fptosi`, which is `trunc_num`; the container fixtures at this stage
exercise all four container reprs. Gate: with
the flag on, gate-green >= 223 -- the pinned floor by then, raised from
220 at stage 1 (section 6's opening), so the suite enforces it -- and the
`arithmetic.md` 2^53 case turns green (`paad/worklist.json` count 4 -> 3);
with it off, the measured 223 unchanged;
`grep -c -- '->stamp' Context.pm` outside `_stamp_of` reads 0;
`%EMITTER_SPELLING` is total over `%REPR`. Only after this does the flag
default on, the shim invert -- `%_REPR_LLVM_TYPE`'s keys renamed onto
`Repr`, the shim deleted -- and the pre-solving `Num |-> double` table
become deletable.

## 7. Explicitly out of scope

- Width and sign selection (`Int` stays `i64`), interval analysis,
  promote-on-overflow, and `double -> float` narrowing. The seam is
  `%CANDIDATES`.
- Exact integer division above 2^53. `Divide => double` (section 5.2) loses
  the low bits of an exact quotient `pp_divide` keeps in IV: a known
  miscompile of the same class as the 2^53 worklist case, to be filed as
  its own issue before stage 4 defaults on. This design does not fix it.
- `EntryWrite` in the loader. A producer/consumer gap independent of T2.
- Call boundaries: F18 (sort comparator) and F22 (one sub called with `Int`
  and with `Str`). The functor is per-graph and lists `Call` in
  `%UNCHECKED`, which O2 declares unchecked rather than pretending to check.
- The retirement of the LLVM emitter's existing conversion arms
  (`019f8193-dd36`). The only emitter change in scope is stage 4's flag
  and the spelling shim at its two readers.
- Retiring the `representation` alias on `Node`, `compat_class`, or any
  other migration residue.
- Any change to T1, the producer, or the wire format. The loader changes
  in two named places: `is_lowerable_stamp` reads `%CANDIDATES` less
  `CodeRef` (stage 1), and the hash-consed `Constant` collision (section 3)
  is Q4. The loader's own two `Coerce` constructors --
  `_insert_str_coercions` (`Analysis.pm:1427`) and
  `_narrow_unknown_coercions` (`Analysis.pm:1592`) -- are T1-side repairs
  in lattice vocabulary; they stay, section 5.2 depends on the first
  through `operand_repr_for_ir_op`, and section 2's grep is scoped so
  that they do not fail it.

**Disposition of the existing T2.** `lib/Chalk/IR/Transform/T2.pm` and its
four tests (`t/bootstrap/ir/t2-emits-llvm-types.t`,
`t2-narrows-num-from-observations.t`, `t2-runs-in-the-pipeline.t`,
`t2-is-partial-but-never-silent.t`; by name, not a `t2-*.t` glob) are
deleted at the end of stage 3: they carry a second `%CANDIDATES` with the
opposite default (`T2.pm:312`) and an in-place `set_stamp` rewrite
(`T2.pm:173`) that took the gate from 224 to 0 when wired in (`eff68e5f`)
-- the reason O8 exists. O8 supersedes the "T2 rewrites the graph" contract
of `2026-08-31-t2-is-a-narrowing-analysis.md`.

## 8. Open questions

Q1 and Q2 each block a stage and say which (stage 3; stage 2's
measurement). Q3 and Q6 have working defaults -- the join seed; refuse as
kind 1 or pass unchecked -- and stage 2's measurements decide whether
either needs more.

1. **Q1, refuse or repair.** "Empty means GAP" and "empty means convert"
   are both right, on HARD and SOFT constraints respectively, assigned by
   the relations of section 5.2: TIE refuses on empty; OWN and SHARED
   convert in the arm; FIXED is an obligation, not a demand on the
   producer's class. That every perl-legal mixed-representation site lands
   in one of them is ASSESSED from the fixtures in 5.3, not measured;
   stage 2's hard-empty count is the measurement, and stage 3 is blocked
   on it. The kind-7 count joins it: the wire delivers an `Int` arm bare
   into a merge at `Num` (section 3.3), and the shape refuses it -- the
   three perl-legal fixtures of section 5.3 (the `Num` merge, the
   ternary, the two returns) show the refusal, and cost each branch of
   this question: (a) keeps them refused until T1 writes the arm's
   `Coerce`, (b) mints `sitofp` on the arm as recorded debt. The fork is
   clause 7 of section 3 asked in one direction, and every clause T2 does
   not refuse on asks the same question. Today the answers are
   inconsistent: clauses 6 and 8 are REPAIRED silently (relation 3, the
   `shared` fallback); clause 7 is repaired when the repair is an
   inclusion row and refused when it is an operation row; clause 5 is
   refused only when the candidate sets are disjoint; clauses 4, 9 and 10
   are trusted. The question, asked once so that one answer covers all of
   them: for a clause T1 does not meet, does T2 (a) REFUSE, naming the
   clause and the edge, so that T1 is made to meet it; or (b) REPAIR,
   minting the arrow and recording the repair as DEBT against T1 -- an
   entry the functor can list, naming the clause it stands in for, so the
   count is visible and can be driven to zero? No repair mechanism is
   designed here; (b) is named so that it can be chosen. Whichever is
   chosen applies to every clause; a per-clause exception is a new
   decision, recorded in this list. Clauses 2 and 3 are outside the fork
   and belong to Q2: a stamp T2 has no row for is not T1's to meet, and
   the answer there is neither a refusal T1 clears nor a repair charged
   against it -- for clause 3 a `%CANDIDATES` row; for clause 2 never a
   row (the top has none, 5.1) but a decision about which positions are
   objects, Q2 and Q6.
2. **Which non-representable stamps are tolerated.** Memory Phis and
   subscript-after-store stay `Unknown` by decision; `List`, `Code` and
   `ScalarRef` are carried by the loader with no `%CANDIDATES` row; some
   nodes arrive unstamped. The functor refuses all of kinds 1-5. Kind 1 is
   the one most likely to demand a decision -- an unstamped `VarDecl`
   under a stamped load -- and its count on wire-loaded graphs is
   unmeasured; stage 2 measures it first.
3. **How RETURN is seeded.** From the sub's `return_type` on the MOP where
   recorded, else from the join of the `Return` inputs' stamps; the printed
   `_seed_return` uses the join until the MOP path is named. A hard `same`
   across all `Return` values was declined: `return 1; return "x"` is
   perl-legal. Which seed wins when the two disagree touches the F22
   boundary rule (section 7).
4. **Constant value-awareness and the hash-consed `Constant`.** Whether the
   producer should stamp `0.0` as `Int` instead is a T1 question; the
   consumer-side rule is correct either way. The hash-consed `Constant`
   collision of section 3.3 is dissolved in the loader, `const_type` or
   `content_hash` distinguishing `0` from `0.0`; seeding an `Int`
   `Constant` from its value does not (section 5.1).
5. **The `double=>i64` row.** `trunc_num` (`fptosi`) gives `Modulo`'s
   `i64` obligation on a `double` operand an image. `fptosi` truncates
   toward zero and is poison outside i64 range; `pp_modulo` truncates
   in-range operands the same way (`3.5 % 2`, `-3.5 % 2`, `7.9 % 3` all
   give `1` under 5.42) and falls to `fmod` beyond UV range (`1e300 % 7`
   gives `1`). The backend today refuses `Modulo` at `Num` outright
   (`Context.pm:2097`). Whether the row exists with a range guard, or T1
   emits `Coerce(Num->Int)` before `Modulo` and the row is dropped, is
   perigrin's; the `7 / 2 % 2` fixture is TODO until then. The row is
   reachable through the producer's constant folding (section 3) and from
   no `own` edge (kind 7).
6. **Memory beyond a `VarDecl`.** The memory rule does not cover a load
   whose `inputs[0]` is not a `VarDecl` (a parameter, `@_`, a closure
   cell; `CellRead`/`CellWrite` do not appear in the corpus), element and
   field stores (the cell is a `Subscript` or `FieldAccess`), or
   loop-carried cells behind a memory Phi that is `Unknown` by decision.
   The first refuses as kind 1 or passes unchecked depending on what
   `inputs[0]` holds; stage 2's kind-1 measurement is where the answer
   comes from.
