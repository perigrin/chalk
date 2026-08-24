# Two-IR architecture: how close is the code, and what is the gap?

**Date:** 2026-08-24
**Status:** AUDIT. Read-only. Nothing changed. No migration plan proposed
(deliberately — sequencing is perigrin's call).
**Target architecture audited against** (perigrin, as refined mid-audit):

> "Not really two IRs … it's a graph transformation of the Chalk IR to
> *another* SoN IR that is more specialized for lowering."

So: ONE IR machinery (the same `Chalk::IR::Node`/`Graph`/`NodeFactory`
infrastructure, the same Sea-of-Nodes model), TWO GRAPH POPULATIONS, and a
transformation pass that consumes the Chalk-typed graph and RETURNS a new graph
whose nodes are specialized for the lowering target — replacing Chalk types with
lowered types, setting representation, plausibly replacing high-level nodes with
lower-level ones. Graal's "lowering" in shape.

---

## VERDICT: ~35% aligned

The **vocabulary** and the **data model** are largely right; the **pass** does
not exist. Chalk has one IR machinery (correct), a `representation` field
holding the lowered vocabulary (correct slot), a `stamp` field holding the Chalk
type (correct slot), a per-graph hash-cons scope that would permit a second
graph (correct foundation), and a `Pass` base class whose contract is literally
`run($Graph) -> $Graph` (correct contract). What is missing is any code that
uses it: **zero passes anywhere in `lib/Chalk/Bootstrap/Optimizer/`,
`lib/Chalk/Target/`, or `lib/Chalk/IR/Schedule/` construct a `Chalk::IR::Graph`**
(measured: `grep -rn "Graph->new"` over those three trees returns nothing). The
graph→new-graph idiom does not exist in the back half of the pipeline at all.

**The single biggest divergence is not the missing pass — it is that the type
axis is DESTROYED at the load boundary, so the transformation has no input.**
The transformation is defined as "replace the Chalk types with lowered types."
On a loaded graph there are no Chalk types to replace: `set_stamp` is defined
(`lib/Chalk/IR/Node.pm:212`) and called **zero times in all of `lib/`**, so every
loaded node has `stamp = UNDEF`. Measured directly (probe below): 14 loaded
nodes, **0 with a stamp**, 9 with a representation. The loader reads the wire
stamp only to derive a representation (`lib/Chalk/IR/Serialize/JSON.pm:548-549`)
and discards the type. What exists today is not "an IR before lowering and an IR
after" — it is a single graph that arrives already half-lowered and never
carried a type at all. The transformation's *source population does not exist*.

Second-largest: the LLVM target is a **direct graph-to-text emitter**, 418
`_emit()` calls in `Context.pm`, with representation decisions made *during*
emission and stored in 33 emission-scoped side tables. There is a seam to insert
at (`lower()` at `Target/LLVM.pm:53` is three lines), but the target would not
become smaller by receiving a pre-lowered graph unless the side tables move too.

---

## 1. Is there one IR or two? Does anything transform a graph into a graph?

### One IR machinery — correct by the refined architecture

`ls lib/Chalk/IR/Node/` gives **87 node classes**; `lib/Chalk/IR/Graph.pm` is the
only graph class; `lib/Chalk/IR/Graph/` contains only `TypedInvariant.pm`. There
is no second node hierarchy and no `Lowered`/`Machine`/`MIR` namespace
(`find lib -iname "*Lower*" -o -iname "*Machine*" -o -iname "*MIR*"` returns only
`lib/Chalk/Bootstrap/Semiring`, an unrelated match). Under the refined
architecture **this is what we want** — one machinery, two populations.

### The graph→graph idiom: the CONTRACT exists, the USE does not

`lib/Chalk/Bootstrap/Optimizer/Pass.pm:2` states the contract in its own ABOUTME:

    # ABOUTME: Subclasses implement name(), scope(), and run($X) -> $X for their scope level.

and :13-14 spells out the graph scope:

    #   - 'graph': pass takes a Chalk::IR::Graph and returns one.

That is *exactly* the shape the target architecture needs. But both concrete
subclasses decline to use it as a transformation:

| pass | file:line | scope | what it returns |
|---|---|---|---|
| DCE | `Optimizer/DCE.pm:22-25` | graph | **"returns the same graph after pruning"** — its own words |
| StructPromotion | `Optimizer/StructPromotion.pm:43,53,65` | `'mop'` | `return $mop` — analyze-only; `rewrite_mop` is "a follow-up" (:48) |

And nothing invokes them in the lowering path:

    grep -rn "Optimizer::" lib/ script/ bin/ | grep -v "^lib/Chalk/Bootstrap/Optimizer/"
    lib/Chalk/Bootstrap/Optimizer.pm:17,18       (the registry's own isa check)
    script/build-chalk-so-generated:25,103        (StructPromotion, the C/XS path)

Zero optimizer passes run on the LLVM path.

### What DOES exist is in-place mutation of a shared graph

The loader's repr passes mutate node input arrays directly. `Serialize/JSON.pm:1123-1130`:

    my $new = $factory->make('Coerce', inputs => [$operand], ...);
    $new->set_representation($c->to_repr);
    $inputs->[$i] = $new;

`$inputs->[$i] = $new` writes through the reader-returned arrayref of an
existing node. This is the anti-pattern of the target architecture: the
"lowering" it performs (minting a Coerce, assigning a representation) happens
by *editing the source graph in place*, so there is no before-and-after to
compare, validate, or re-run.

**Verdict on Q1:** one IR machinery (right), zero graph→graph transformations
(the whole gap). The idiom is contractually specified in `Pass.pm` and used
nowhere.

---

## 2. Where is representation set?

`grep -rn "set_representation" lib/ | grep -v "sub set_representation"` — **22
lines, of which 3 in `Node.pm` are comments/the method definition**, leaving
**19 real call sites**:

| layer | file | count | lines |
|---|---|---|---|
| **LOADER** | `lib/Chalk/IR/Serialize/JSON.pm` | **18** | 549, 557, 699, 761, 805, 1056, 1128, 1438, 1442, 1547, 1553, 1567, 1574, 1605, 1626, 1863, 1877, 1939 |
| **TARGET** | `lib/Chalk/Target/LLVM/Context.pm` | **1** | 5197 (`$array->set_representation('ArrayRef')`) |
| elsewhere | — | 0 | — |

**Representation assignment is 18:1 in the LOADER, not the target.** It is not a
single identifiable pass; it is scattered across at least nine distinct loader
functions, several of which run to a fixpoint. From `Serialize/JSON.pm:871`:

    while (_stamp_method_call_reprs($data->{classes} // {}, \%graphs) > 0) {

and :866-870 documents why the iteration is needed (a callee's `return_repr`
is not known until its internal call is stamped, so a caller can only be
stamped on a later pass). So the assignment is not merely scattered — it is an
iterate-to-fixpoint dataflow analysis smeared across a deserializer.

Named repr-assigning loader functions found: `_seed_direct_call_arg_reprs`
(:708), `_stamp_field_access_reprs` (:1832), `_stamp_method_call_reprs` (:1886),
`_seed_and_propagate_reprs`, `_insert_str_coercions` (:996),
`_narrow_unknown_coercions` (:1089), `_resolve_direct_calls`, plus the inline
site at :549.

Each of the last three mints its **own `NodeFactory`** (:366, :1001, :1091),
with the comment at :998-1000 explaining that this is safe because "a node's
identity is its content hash". That reasoning is measured false below (§7).

**This is arguably the strongest positive signal in the audit**: the repr
assignment *already is* a multi-pass dataflow analysis over a whole graph
population. It is the lowering pass — it is just living inside the deserializer
and mutating in place instead of producing a new graph.

---

## 3. Does the producer leak representation?

**Mostly no, and the wire is clean. One nominal leak on the class.**

| question | answer | evidence |
|---|---|---|
| Does `SoN::IR::Node` carry a `representation` field? | **YES** | `perl5-son lib/SoN/IR/Node.pm:56` `field $representation :reader = undef;` (setter at :136) |
| Does the producer's graph builder ever set it? | **NO** | `grep -c "set_representation" lib/SoN/FromOptree.pm` → **0** |
| Does the wire format carry representation? | **NO** | `grep -c "representation" /tmp/pcase.json` → **0** on a real produced graph |
| Does the wire carry stamps? | **YES** | `SoN/Serialize/JSON.pm:375-376`: `if (defined $node->stamp) { $entry{stamp} = $node->stamp->type; }` |

Probe (a real B::SoN run over `my $x=5; my $s="hi"; my $n=$x/2; my @a=(1,2,3); my $e=$a[0]; return $e+$x;`):

    $ grep -o '"stamp" : "[A-Za-z]*"' /tmp/pcase.json | sort | uniq -c
          1 "stamp" : "ArrayRef"
          5 "stamp" : "Int"
          3 "stamp" : "Num"
          1 "stamp" : "Undef"
          2 "stamp" : "Unknown"
    $ grep -c representation /tmp/pcase.json
    0

**The wire format is exactly what the target architecture asks for**: types only,
no representation.

The `representation` field on `SoN::IR::Node` is a leak of the *class shape*,
not of *data*. Its 15 `set_representation` call sites in the producer repo are
all in `lib/SoN/IR/Serialize/JSON.pm` (:499, 507, 580, 654, 856, 860, 965, 971,
985, 992, 1005, 1011, 1250, 1264, 1327) — a **vendored copy of chalk's loader**
living in the producer tree, not producer code. The real wire writer is
`SoN::Serialize::JSON` (the one `lib/B/SoN.pm:13` imports), and it has zero
representation references.

One asymmetry worth naming: `Coerce` — the representation-bridging node — is
minted on **both** sides. Producer: `FromOptree.pm:115,135`. Chalk loader:
`Serialize/JSON.pm:1051,1123`. A node whose entire content is
`(from_repr, to_repr)` is created by a producer that has no representations.
`Serialize/JSON.pm:509` acknowledges this: "from_repr/to_repr are
REPRESENTATIONS named in the producer's stamp [vocabulary]". The two
vocabularies overlap by name, so this works, and it is precisely the overlap
`2026-08-14` warns produces wrong answers.

---

## 4. Is the type axis preserved? — CONFIRMED, it is not

The claim to verify: the chalk loader never calls `set_stamp`, so every loaded
node has `stamp = UNDEF` and only representation is populated.

**Confirmed, independently, two ways.**

Static:

    $ grep -c "set_stamp" lib/Chalk/IR/Serialize/JSON.pm
    0
    $ grep -rn "set_stamp" lib/
    lib/Chalk/IR/Node.pm:212:    method set_stamp($new_stamp) {

`set_stamp` is defined once and **called from nowhere in all of `lib/`**. Also
`grep -rn -- "->stamp" lib/` returns exactly one hit, and it is inside a comment
(`Serialize/JSON.pm:1588`). The type axis has neither a writer nor a reader in
chalk production code.

Dynamic (real B::SoN output through `Chalk::IR::Serialize::JSON::from_json`):

    GRAPH main::__PROGRAM__: 3 nodes, 0 with stamp, 1 with repr
      Start          stamp=UNDEF      repr=UNDEF
      Constant       stamp=UNDEF      repr=Undef
      Return         stamp=UNDEF      repr=UNDEF
    GRAPH main::corpus_case: 11 nodes, 0 with stamp, 8 with repr
      Constant       stamp=UNDEF      repr=Int
      Constant       stamp=UNDEF      repr=Int
      Constant       stamp=UNDEF      repr=Int
      ArrayRef       stamp=UNDEF      repr=ArrayRef
      Constant       stamp=UNDEF      repr=Int
      MemStart       stamp=UNDEF      repr=UNDEF
      Subscript      stamp=UNDEF      repr=Int
      Start          stamp=UNDEF      repr=UNDEF
      Constant       stamp=UNDEF      repr=Int
      Add            stamp=UNDEF      repr=Int
      Return         stamp=UNDEF      repr=UNDEF

**0 of 14 loaded nodes carry a stamp.** Note the wire for this same program
carried 12 stamps (§3). Every one was consumed and discarded. This reproduces
`docs/plans/2026-08-24-how-well-typed-is-the-ir.md:115` ("Every node in every
loaded graph has `stamp` = UNDEF") on an independently constructed case.

The mechanism is the one that doc names, at `Serialize/JSON.pm:548-549`:

    if (defined $nd->{stamp} && $LOWERABLE_STAMP{ $nd->{stamp} }) {
        $node->set_representation($nd->{stamp});
    }

Read the whitelist at :30: `qw(Int Num Str Boolean Undef Object)`. A stamp
**outside** that set — `Scalar`, `List`, `DualVar`, a ref type — sets *nothing*.
So for those types the wire stamp is discarded without even producing a
representation: both axes end UNDEF.

### The consequence for the target architecture, stated plainly

The transformation is specified as "replace the Chalk types with lowered types."
On the chalk side there are no Chalk types on any node to replace. The
"target-independent IR carrying types" **does not exist as a live artifact** —
it exists only as the wire JSON, transiently, inside `from_json`. Types survive
as far as the wire and no further.

This is a genuine architectural inversion, not just a missing field: today's
pipeline is `producer types → wire → REPRESENTATIONS`, whereas the target is
`producer types → wire → chalk-typed graph → [lowering pass] → lowered graph`.
The middle term is absent.

### The irony worth recording

`lib/Chalk/IR/Value.pm` exists *entirely* to make the type axis well-defined. It
is 54 lines of design rationale for splitting value-producing nodes into their
own class so that `undef stamp` can only ever mean "inference question" (:20-23),
citing Graal's `ValueNode` (:41). It documents the field's semantics at :25-31
("It is a STAMP in C2's and Graal's sense … Do not 'correct' the name to Type").

The class body is:

    class Chalk::IR::Value :isa(Chalk::IR::Node) {
    }

Empty. And the field it exists to give meaning to is never written. The
scaffolding for the type axis was built; the axis was not connected.

Also note `Node.pm:19`'s field comment still reads *"Optional stamp for
identifying parse-origin or generation context"* — describing a completely
different (pre-type-lattice) purpose than `Value.pm:25-31` and `Node.pm:208-211`
describe for the same field. Three descriptions, one unwritten field.

---

## 5. What would the specialized nodes be?

Accessor reads across `lib/Chalk/Target/LLVM.pm` + `lib/Chalk/Target/LLVM/Context.pm`:

| accessor | reads | axis |
|---|---|---|
| `->id` | 160 | structural (identity — see §7 hazard) |
| `->inputs` | 93 | structural (graph shape) |
| `->operation` | 86 | structural (node kind) |
| `->representation` | 44 | **REPRESENTATION** |
| `->name` | 28 | structural (symbol) |
| `->control_in` | 26 | structural (effect order) |
| `->consumers` | 24 | structural (use-def) |
| `->dispatch_kind` | 9 | structural |
| `->value` | 5 | structural (literal payload) |
| `->class_name` | 3 | structural |
| `->const_type` | 1 | structural |
| **`->stamp`** | **0** | **TYPE — never asked** |
| `->schedule_data` | 0 | — |
| `->is_fixed` | 0 | — |

**The backend asks a type question zero times.** This is why the missing type
axis (§4) has gone unnoticed: nothing downstream wants it. It also means the
lowering pass would be the *first* consumer of the type axis, which makes §4 a
hard prerequisite rather than a nice-to-have.

### What the target branches on — the list a lowered graph would encode structurally

**94 representation comparisons** in `Context.pm`
(`grep -c -E "repr[a-z_]* +(eq|ne) +'"`):

    'Str' 20   'Int' 19   'Num' 16   'Scalar' 14   'Undef' 9   'ArrayRef' 9
    'HashRef' 8   'Boolean' 6   'Array' 4   'Slot' 3   'Hash' 3   'Object' 2
    'CodeRef' 1

**81 operation comparisons** over 53 distinct ops (`Add And ArgsSource ArrayRef
Assign BacktickExpr Call Coerce CompoundAssign Concat Constant Defined DefinedOr
Divide EntryDef EnvRead FieldAccess HashRef If Length Loop Match Modulo Multiply
Not NotMatch NumEq NumGe NumGt NumLe NumLt NumNe Or PadAccess Parameter Phi
PostfixDeref Print Proj RefType RegexCapture RegexMatch RegexSubst Region Start
StrEq StrNe Subscript Subtract TernaryExpr TryCatch Unwind VarDecl`).

**The 94 representation branches are the distinctions a lowered graph would
encode as node kinds.** The cross-product `(op × repr)` is what the emitter
currently re-derives at every site. Concretely: a generic `Subscript` would
become a typed element-load kind, since `_lower_binop_int` (`Context.pm:1086`)
already branches internally on `$repr eq 'Num'` (:1104) to pick `fadd`-vs-`add`
— that branch IS a node-kind distinction being made at emission time.

### The 14 `Scalar` refusals are the clearest evidence a pass is missing

`grep -n -E "repr[a-z_]* +eq +'Scalar'" Context.pm` → **14 sites**: 932, 955,
1095, 1155, 1180, 1709, 1777, 1835, 2202, 2285, 2350, 2524, 2602, 2730.

Fourteen scattered copies of the same guard, e.g. `Context.pm:1095`:

    die "$op with repr=Scalar reached LLVM backend" if $repr eq 'Scalar';

A single well-formedness precondition, asserted fourteen times at fourteen
emission sites, is the signature of a missing prior pass. In a two-population
design this is one validation on the lowered graph's construction — `Scalar` is
simply not a member of the lowered vocabulary, so the guard becomes a
constructor precondition asserted once.

Compare the same shape in `_require_repr` (`Target/LLVM.pm:80`), called **30
times** in `Context.pm`: "Assert that `$node` has a defined representation …
Dies loudly (GAP) if representation is undef." Thirty assertions that the
lowering already happened. In the target architecture, the lowered graph's type
makes those unrepresentable.

---

## 6. Prior art in the repo — extensive, and the code does NOT match it

This design is **already established in four documents**. I re-derived nothing;
below is what they concluded and whether the code matches.

### `docs/plans/2026-08-21-type-vs-representation-seams.md` — the closest match to the target architecture

Section "THE ARCHITECTURAL FINDING: representation is the TYPE FIELD AFTER A
REWRITE" (:399+) records perigrin saying:

> Representation is really just changing the type from a Chalk type to a
> Backend (LLVM) type ... so Node(Int) becomes Node(i64) or Node(u64) or
> whatever the LLVM lowering algorithm decides.

and the doc's own conclusion (:410-412):

> This is not a second attribute alongside the type -- it is THE SAME SLOT,
> after a transformation. One type field, two vocabularies, lowering is the
> rewrite between them.

It then states the gap explicitly (:515-519):

> **THE ACTUAL GAP.** There is no rewrite PHASE. `_repr_to_llvm_type` is
> consulted ad hoc during emission, so the transformation exists but is smeared
> across the emitter rather than being a pass with a before and an after. That
> is precisely why it cannot consider value facts: a per-node table lookup at
> emission time has no view of the graph.

**Status: still true, verbatim, three days later.** Measured: 418 `_emit()`,
zero `Graph->new` in the target. Nothing has changed.

The doc also anticipates the mint-defs requirement (:472-478) — the pass "must
be able to MINT DEFS, not just rewrite fields" — and pins two safety conditions
(:485-500): machine-vocabulary coercions are not all lossless, and *choosing
representations and inserting conversions are ONE decision*, because splitting
select-then-repair reintroduces the 0a overflow miscompile.

And it identifies `Node.pm:41-56` as "the layering violation at its source"
(:508) — the field documented as "Machine-level representation" with an inline
LLVM map, over a field that holds Chalk types. **Verified unchanged**:
`Node.pm:41-56` still carries `'Int' (i64)`, `'Num' (double/f64)`,
`'Str' ({ptr,len,encoding})` in its docstring.

### `docs/plans/2026-08-14-representation-is-the-targets-type-system.md`

Establishes that **representation is not a lattice** — LLVM's type relation is
equality, verified against `lli`/`llvm-as` with three probes (:39-53) — and
gives the two-check rule:

    skip the Coerce  iff  is_subtype(A, B)              # SEMANTICS (IR-level)
                     AND  type_for(A) == type_for(B)    # ENCODING  (target-level)

**Code match: PARTIAL, and blocked by §4.** The target *knows* the rule —
`Context.pm:3020-3026` states it in a comment and cites this doc by name. But
the semantics leg `is_subtype(A,B)` cannot be evaluated on a loaded graph,
because there are no stamps to ask about. `grep -rn "is_subtype\|TypeLibrary"
lib/Chalk/Target/` returns **two hits, both inside that comment block** (:3017,
:3021). The rule is documented in the target and applied nowhere in it.

### `docs/plans/2026-07-22-representation-is-a-codegen-concern.md`

Proposed exactly the target architecture (its "The clean architecture this
implies" section: "NO `representation` field on the shared IR … a
repr-ASSIGNMENT pass"), and was **RESOLVED as verdict (b): naming problem, not
architecture** by PAAD pushback (:113-166).

The pushback's three load-bearing claims, re-measured today:

| pushback claim | :line | 2026-08-24 status |
|---|---|---|
| "Types-in-IR / repr-mapping-in-Codegen is the IMPLEMENTED architecture" | :126-128 | **FALSE for the chalk side.** There are no types in the chalk IR (§4). True only of the producer + wire. |
| "The 18:1 ratio was wrong" | :138-142 | **The ratio is right; the count was off by three.** 19 real sites, 18 loader : 1 target. `Node.pm`'s three are comments + the definition, as the pushback said — but that leaves 18:1, not a corrected balance. |
| "Wire format is ALREADY repr-free" | :140-142 | **TRUE, verified** (§3). |
| "The Coerce subsystem is DORMANT — zero production creation sites in either repo" | :144 | **FALSE as of today.** Four production sites: `FromOptree.pm:115,135` and `Serialize/JSON.pm:1051,1123`. |
| deferred: "if a SECOND backend ever needs different lattice GRANULARITY … the single semantic-tag-doubles-as-repr WILL pinch" | :157-162 | This is the deferral the current architecture direction cashes in. It was filed as "a decision to make WHEN a second target exists". |

So the July resolution's core factual premise — that the chalk IR carries types
— does not hold on measurement. That resolution should be considered
superseded by `2026-08-21-type-vs-representation-seams.md`, which reaches the
opposite conclusion (a rewrite phase is genuinely missing) with measurement.

### `docs/plans/2026-08-24-how-well-typed-is-the-ir.md` (today)

Already found the §4 result and filed it deliberately unfixed (:149-151):

> Filed as its own finding rather than fixed here: setting `stamp` on load is a
> small change, but deciding whether the type axis is meant to survive the wire
> is a design question, not a bug fix.

**That design question is exactly what the target architecture answers: yes, it
must survive, because it is the lowering pass's input.** This audit's §4 is a
confirmation of that finding, not a new one.

Its :192-193 is the key caveat for gap-sizing: "The lowering path is unaffected,
because the backend asks for a representation. The cost is that no pass after
the loader can ask a type-lattice question." Measured true (§5: `->stamp` read 0
times in the target).

### `docs/plans/2026-08-22-two-lattices-one-ir.md` — RESOLVED, and it is load-bearing good news

The producer's `SoN/IR/Stamp.pm` and chalk's `TypeLibrary.pm` lattices were
diffed and found to have **zero divergence** across 25 shared members
(:22-27), with the only two differences being encoding of the extremal elements
`None`/`Unknown`. `TypeLibrary` is now canonical.

**This is a genuine prerequisite already satisfied.** The lowering pass needs
one agreed source lattice to translate *from*; it exists and is verified.

### `docs/research/2026-08-24-typed-memory-prior-art.md` + `docs/plans/2026-08-24-thread-use-information-to-lowering.md` (today)

The thread-use doc scopes TurboFan's PROPAGATE phase in isolation — backward
use-propagation so "the lowering pass can make an intelligent decision"
(:6-8) — and measures both prerequisites present (bidirectional consumers).

Note this doc **presupposes a lowering pass exists to be threaded to**. Per this
audit, it does not. That is a sequencing dependency worth naming: use-information
threading is an input to a pass that has no implementation.

---

## 7. How big is the gap?

### The seam exists and is small

`Target/LLVM.pm:53-59`:

    sub lower {
        my ($class, $return_node, %opts) = @_;
        my $dom  = Chalk::IR::Schedule::Dominators->from_return_node($return_node);
        my $elab = Chalk::IR::Schedule::Elaborate->from_return_node($return_node, $dom);
        return $class->lower_with_elaboration($return_node, $elab, %opts);
    }

A pass would insert between line 54 and 56. Structurally there is somewhere to
put it. The problem is not the seam.

### Is the LLVM target a pass over a graph, or a direct-to-text emitter? — DIRECT-TO-TEXT

`Context.pm:1-2` says so in its own ABOUTME:

    # ABOUTME: Internal LLVM lowering context — accumulates basic blocks and SSA state during SoN->LLVM emission.
    # ABOUTME: Provides lower_value dispatch and the per-node emitters that build LLVM IR text for one method/function body.

Measured: **418 `_emit`-family calls** (`416 $self->_emit(` + `_emit_entry`,
`_emit_coercion`, etc. — coordinator's 418 figure **verified**). The emit
primitive appends a **string** (`Context.pm:453-456`):

    sub _emit {
        my ($self, $inst) = @_;
        push $self->{blocks}[ $self->{current_idx} ]{insts}->@*, $inst;
    }

and `lower_value` returns a **string** SSA ref (`_fresh`, :501-505, returns
`'%tmp_' . $counter`). There is an intermediate structure —
`{blocks}[i]{insts}` — but it holds formatted text lines, not nodes. It is an
output buffer, not an IR.

### Emission is INTERLEAVED with analysis, not separable — measured three ways

**(a) Representation decisions are made mid-emission.** `_lower_binop_int`
(`Context.pm:1086-1122`) reads `$node->representation` (:1089), asserts it is
not `Scalar` (:1095), branches on `Num` (:1104), calls `_lower_as_double` to
*insert a `sitofp` conversion* (:1107-1108) — a graph-level lowering decision —
and emits text (:1110) in the same 36 lines. Select-and-emit are one step, which
is precisely what `2026-08-21-type-vs-representation-seams.md:496-500` warns
must NOT be split carelessly *and* must not stay fused.

**(b) State flows between emitters through 33 emission-scoped side tables.**
`grep -o "\$self->{_[a-z_]*}"` yields 33 distinct tables, including
`_undef_defined_bit`, `_undef_payload`, `_slot_payload`, `_vd_repr`,
`_regex_captures`, `_str_globals`, `_phi_to_vd`, `_arg_bind`, plus `{cache}`
(94 uses) and 11 `_need_*` flags. `str_len`-related lines: 49. These hold the
*encoding* half of each representation — `2026-08-14`'s point that a
representation is `(machine type, value encoding)` and the encoding lives in
side tables, not on the node.

**A lowered graph could not by itself eliminate these**, because they are keyed
to emission order, not to nodes. That is the honest gap-sizing answer: moving
representation onto a lowered graph moves ~44 `->representation` reads and 94
branches, but leaves the encoding side tables where they are unless they are
separately designed onto the lowered node kinds.

**(c) A concrete measured consequence of the interleaving.** `Context.pm:3484`:

    my $var_repr  = $self->{_vd_repr}{$vd_id} // 'Int';

The merge phi's LLVM type is looked up from a side table populated during a
*previous* emission (`Context.pm:1739`, inside the VarDecl emitter), with a
silent `'Int'` default when it was not. And the structure that *should* carry it
does not: `Chalk::IR::Schedule::Elaborate` documents a `repr` key on each phi
record (`Elaborate.pm:34`) and provides `emit_phi($block_id,$vd_id,$incoming,$repr)`
(:40) — but **`emit_phi` is dead code**. `grep -rn "emit_phi" lib/ t/` outside
Elaborate.pm returns one hit: `t/bootstrap/ir/elaborate.t:32`, a `can()` check.
The three real push sites (:234, :294, :322) set `block_id`, `vd_id`, `incoming`
— and **never `repr`**. So the phi's representation must be recovered from
emission-order state, which is why the `// 'Int'` fallback exists at all.

### Does the Elaborate precedent generalize? — PARTIALLY. It is the right shape and the wrong axis.

`Chalk::IR::Schedule::Elaborate::from_return_node($ret, $dom)` (:54-79) does
consume a graph and return a new object (`blocks`, `emitted_phis`,
`dominators`), and the target consumes it (`Target/LLVM.pm:57-58`, `:1158`;
`Context.pm:74, 138, 152`). **This proves the graph→new-structure pattern works
in this codebase for CONTROL FLOW.**

Three reasons it is a weaker precedent than it looks:

1. **It produces a different KIND of thing, not a graph.** Blocks and phi
   records, not `Chalk::IR::Node`s. It builds no nodes and creates no graph
   (`grep -rn "Graph->new" lib/Chalk/IR/Schedule/` → nothing). The hard parts of
   a lowering pass — minting defs, hash-consing them, preserving use-def
   chains — are exactly what it never has to do.
2. **It does not carry the representation axis**, per (c) above. Its
   `repr` field is declared and never populated. So on the one axis where it
   overlaps the lowering pass's job, it fails and the target falls back to a
   side table.
3. **It is placement-only by design** — `Elaborate.pm:17-18`: "This module does
   NOT perform front-half optimization (no GVN/LICM/rewrite). Placement only."
   A lowering pass is definitionally a rewrite.

Verdict: precedent for the *plumbing* (a pass between load and emit whose output
the target consumes), not for the *transformation*.

### The second-graph feasibility: one real foundation, one real obstacle

**Foundation — hash-consing IS graph-scoped, and deliberately.** `Graph.pm:1-2`:

    # ABOUTME: Container for a complete Chalk computation graph with hash-cons scope.
    # ABOUTME: Owns %cache and $cfg_counter; merge() hash-conses nodes into this graph.

and :15-19: "Per-graph hash-cons cache … **Scoped to this graph so consumer
lists cannot leak across graphs.**" Both `field %cache` (:20) and
`field $cfg_counter` (:24) are per-instance. `NodeFactory` likewise has
per-instance `field %cache` / `field $cfg_counter` (`NodeFactory.pm:179-180`),
and factories are already minted per-graph (10 `NodeFactory->new` sites; the
loader mints one per `_deserialize_graph` at :366). **A second graph population
is architecturally supported.** This is a real positive.

**Obstacle — node IDs are NOT unique across factories, and `merge` dedupes
across them.** Probe:

    same factory identical?  SAME OBJECT
    cross factory identical? distinct
    ids: a=Constant|const_type=integer|value=42  c=Constant|const_type=integer|value=42
    id collision across factories: YES
    percall ids: f1=Assign#1 f2=Assign#1  collide=YES
    g1->merge(c) returned THE g1 NODE a (content-deduped across factories)

Three measured facts:

1. Two distinct objects from two factories carry **byte-identical content-hash
   IDs**.
2. Per-call IDs (`Assign#1`) **collide** — the counter restarts per factory.
3. **`Graph::merge` content-dedupes across factory boundaries**: handing graph
   G1 a node built by factory F2 returns G1's *own* content-equal node, not the
   one passed in.

Fact 3 is the sharp one for a lowering pass. If the pass builds a lowered node
whose content hash equals a source node's — which is the *common* case, since
`representation` is excluded from `content_hash` by design (`Node.pm:50-55`,
justified there to keep two identical literals hash-consing to one) — then
`merge` returns the SOURCE node instead. **The very field the lowering pass
exists to set is the field excluded from identity**, so lowered and unlowered
nodes are indistinguishable to the identity system.

That collision then meets the known systemic hazard. The target's caches are
string-id keyed — `$self->{cache}{$node->id}` and friends, 94 `{cache}` uses,
plus `_undef_defined_bit`/`_undef_payload`/`_vd_repr` all keyed by `$node->id`
(`Context.pm:1064, 1068, 1739`). `refaddr` appears 9 times as the point
workaround, documented at `Context.pm:698-702`: keyed by refaddr "because its
string id can collide with a caller node's id — both graphs number `Call#N` from
their own factory". `2026-08-21-type-vs-representation-seams.md:435-440` records
the miscompile this already caused: `f(1)+f(2)` emitted one `mul` and printed 4.

So the loader comment at `Serialize/JSON.pm:998-1000` — "a node's identity is
its content hash, so nodes minted here are consistent with the ones already in
the graph" — is measurably not a sufficient safety argument across factory
boundaries.

### Concrete gap sizing

| item | measured | what it means for the transformation |
|---|---|---|
| Graph→new-Graph passes today | **0** | The idiom does not exist in the back half |
| `Graph->new` in Optimizer/Target/Schedule | **0** | — |
| `set_stamp` calls in `lib/` | **0** | The pass's INPUT does not exist |
| `->stamp` reads in `lib/` | **0** (1 comment) | Nothing consumes types today |
| `set_representation` sites to relocate | **19** (18 loader, 1 target) | The pass's body already exists, in the loader |
| Loader repr functions to relocate | **≥9** named, iterate-to-fixpoint | Not a mechanical move; it is a dataflow analysis |
| `->representation` reads in target | **44** | Would read a lowered node's type instead |
| repr branches in target | **94** | Candidate node-kind distinctions |
| `repr eq 'Scalar'` refusals | **14** | Collapse to one construction precondition |
| `_require_repr` assertions | **30** | Become unrepresentable-by-construction |
| `_emit()` calls | **418** | Unchanged by the pass; text emission stays |
| target side tables | **33** | **NOT addressed by a lowered graph** — separate design |
| producer `set_representation` in `FromOptree` | **0** | Producer is clean |
| `representation` keys on the wire | **0** | Wire is clean |
| lattice divergence producer↔chalk | **0** of 25 members | Prerequisite satisfied |

**Would the target get smaller?** Partially. The 30 `_require_repr` assertions
and 14 `Scalar` refusals become unnecessary (a lowered graph cannot carry
`Scalar` or an unset repr). The 94 repr branches would shrink to the extent the
distinctions become node kinds. But the 418 `_emit` calls and the 33 side tables
are emission concerns that a lowered graph does not by itself remove.

---

## What is already right

Six things, and they are not small.

1. **The wire format is exactly correct.** Types only, zero representation keys,
   verified on a live B::SoN run (§3). The producer/consumer boundary is already
   the target-independent boundary the architecture asks for.

2. **The producer does not leak representation into its graphs.** Zero
   `set_representation` in `FromOptree.pm`. The `representation` field on
   `SoN::IR::Node.pm:56` is class-shape residue from the vendored loader copy,
   carrying no data.

3. **One IR machinery, correctly.** 87 node classes, one `Graph`, one
   `NodeFactory`, no competing hierarchy. Under the refined architecture this
   is the right foundation, and it needs no change.

4. **Hash-consing is graph-scoped by explicit design**, documented in
   `Graph.pm:1-2, 15-19`, with per-instance `%cache`/`$cfg_counter` on both
   `Graph` and `NodeFactory`, and per-parse factories already the norm (10
   `->new` sites). A second graph population is architecturally supported today.

5. **The two lattices are one**, verified zero-divergence over 25 members
   (`2026-08-22-two-lattices-one-ir.md`, RESOLVED 2026-08-23). The pass has a
   single unambiguous source vocabulary to translate from.

6. **The pass contract is already written down.**
   `Optimizer/Pass.pm:2, 13-14` specifies `run($Graph) -> $Graph` with a
   `scope()` of `'graph'` or `'mop'`. A lowering pass is a conforming subclass
   of a base class that exists.

Two more, weaker but real:

7. **The repr-assignment logic already exists as multi-pass dataflow** (§2) —
   iterate-to-fixpoint, whole-graph-population, cross-graph call resolution. It
   is the lowering pass's body, currently resident in the deserializer.

8. **The two-axis rule is understood and documented in the target itself**
   (`Context.pm:3020-3026`), citing the plan by name. The knowledge is in place;
   only the type axis it needs (§4) is absent.

---

## COULD NOT DETERMINE

1. **Whether the 87 node classes would split, merge, or stay 1:1 in a lowered
   population.** I measured what the target *branches on* (94 repr comparisons ×
   53 ops) but that is the space of distinctions, not a design. Deciding which
   become node kinds is a design question this audit does not answer. Looked at:
   `lower_value`'s dispatch (`Context.pm:692-1085`), `_lower_binop_int`
   (:1086-1122), `_emit_coercion` (:1507+), `_repr_to_llvm_type` (:3000+).

2. **Whether the 33 emission side tables could be carried on lowered nodes.**
   Each would need individual analysis of whether its key is a node or a
   program point. `_undef_defined_bit`/`_undef_payload`/`_vd_repr` are node-id
   keyed and look node-carryable; `_need_*` flags are module-global; `_arg_bind`
   is a call-frame stack. I did not analyze all 33.

3. **Whether the loader's iterate-to-fixpoint repr passes would terminate
   unchanged if they ran over two graph populations.** The fixpoint loop at
   `Serialize/JSON.pm:871` is bounded by "a pass stamps nothing new" (:868-870).
   Whether that argument survives a source population plus a lowered population
   in flight, I did not analyze.

4. **Whether any node reaches the backend still `Unknown`.** Carried over from
   `2026-08-24-how-well-typed-is-the-ir.md:201-202`, unresolved there and not
   measured here. My probe measured the loader's output, not `_require_repr`'s
   input after all passes.

5. **The `Coerce` dual-minting asymmetry's practical impact.** Producer mints
   `Coerce` at `FromOptree.pm:115,135` with no representations in scope; chalk
   mints it at `Serialize/JSON.pm:1051,1123`. Whether producer-minted
   `from_repr`/`to_repr` values are always in `%LOWERABLE_STAMP` I did not
   check exhaustively.

6. **What the `'Bool'` vs `'Boolean'` mismatch does.**
   `Serialize/JSON.pm:557` sets `'Boolean'`; the producer's vendored copy sets
   `'Bool'` at `SoN/IR/Serialize/JSON.pm:507`.
   `2026-08-22-two-lattices-one-ir.md:44` says the rename to `Boolean` landed
   in chalk `c38fed6e`. Whether the producer copy is stale-but-unused or live on
   some path, I did not trace.

---

## Owner's direction on reading this audit (2026-08-24)

Recorded because it settles two of the audit's open points and changes what
counts as a gap.

**1. "We can definitely use a second factory."** §7's identity hazard — two
factories producing byte-identical content-hash IDs, `Graph::merge`
content-deduping across them — is accepted as a cost to be designed against,
not a blocker. A lowered graph gets its own factory. The aggravating factor
§7 identifies (`representation` excluded from `content_hash`, `Node.pm:50-55`)
is the specific thing that design has to answer: a lowered node and its source
are currently indistinguishable to the identity system, so either the lowered
population must never be merged with the unlowered one, or identity must
include the axis that distinguishes them.

**2. "Elaborate and Schedule I think are significant chunks of this new
layer."** This reframes §1's finding. The audit reports Elaborate as a
*partial precedent* that fails on the one axis overlapping the lowering job;
the owner reads it as *already being part of the layer under construction*,
not merely a precedent for it.

Both readings are consistent with the measurements, and the difference is
scope, not fact. Under the owner's reading:

- `Schedule`, `Schedule::Elaborate`, `Schedule::Dominators` and
  `Schedule::Item` are not "a pattern to imitate" — they are the CONTROL-FLOW
  portion of the target-specialized layer, already built and already consumed
  by the LLVM target.
- What is missing is therefore narrower than "a lowering pass": it is the
  TYPE/REPRESENTATION portion of a layer whose control-flow portion exists.
- The dead `emit_phi` (§1: accepts and stores a `repr`, called from nowhere,
  target falls back to `$self->{_vd_repr}{$vd_id} // 'Int'` at
  `Context.pm:3484`) is then not a defect in a precedent. It is an
  **unfinished seam in the layer itself** — the exact point where the
  control-flow half was built to accept representation information and the
  representation half was never built to supply it. Verified independently by
  the coordinator: zero `emit_phi(` call sites in all of `lib/`.

That makes `emit_phi` the smallest concrete instance of the whole gap, and a
plausible first target: a place where the layer already asks for the
information the missing pass would produce.

## Cross-references

- **Supersedes the resolution of** `docs/plans/2026-07-22-representation-is-a-codegen-concern.md`.
  Its verdict (b) — "the clean architecture MOSTLY ALREADY EXISTS" (:115-116) —
  rests on "Types-in-IR / repr-mapping-in-Codegen is the IMPLEMENTED
  architecture" (:126-128), which §4 measures false for the chalk side. Its
  "Coerce subsystem is DORMANT — zero production creation sites" (:144) is also
  false today (4 sites). Its deferred structural point (:157-162) is the live
  one.
- **Confirms and extends** `docs/plans/2026-08-24-how-well-typed-is-the-ir.md:115-151`.
  Its "design question, not a bug fix" deferral (:149-151) is answered by the
  target architecture: the type axis must survive the wire, because it is the
  lowering pass's input.
- **Confirms unchanged** `docs/plans/2026-08-21-type-vs-representation-seams.md:515-519`
  ("THE ACTUAL GAP. There is no rewrite PHASE"). Still exactly true.
- **Depends on** `docs/plans/2026-08-22-two-lattices-one-ir.md` (RESOLVED) — the
  single source lattice is a satisfied prerequisite.
- **Sequencing note for** `docs/plans/2026-08-24-thread-use-information-to-lowering.md`:
  it threads use-information *to a lowering pass*. Per §1 and §7 that pass does
  not exist. Naming this dependency rather than leaving it implicit.
- **Relevant to** the known cross-graph id-collision family (memory:
  `cross_graph_id_keyed_cache_collisions`). §7's probe shows content-hash IDs
  and per-call IDs both collide across factories, and `Graph::merge`
  content-dedupes across them — a second graph population would enter this
  hazard family directly, with `representation` excluded from `content_hash`
  (`Node.pm:50-55`) as the aggravating factor.

---

## Reproduction

    # §3/§4 probe — produce, then load, then compare axes
    PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl
    cat > /tmp/pcase.pl <<'EOF'
    sub corpus_case { my $x = 5; my $s = "hi"; my $n = $x / 2;
                      my @a = (1,2,3); my $e = $a[0]; return $e + $x; }
    EOF
    $PERL -I/home/perigrin/dev/perl5-son/lib -MO=SoN,json,package=main \
        /tmp/pcase.pl 2>/dev/null > /tmp/pcase.json
    grep -c representation /tmp/pcase.json            # -> 0
    grep -o '"stamp" : "[A-Za-z]*"' /tmp/pcase.json | sort | uniq -c

    # then from_json() the result and print ->stamp / ->representation per node
    # (0 of 14 nodes carry a stamp; 9 carry a representation)

    # §7 probe — identity across factories
    # two NodeFactory instances, same Constant content:
    #   distinct objects, IDENTICAL ids, and g1->merge(f2_node) returns g1's node
