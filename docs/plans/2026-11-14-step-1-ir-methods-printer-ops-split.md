# Step 1 of retiring Context.pm: IR-node methods, printer ops, the T2.pm split

**Origin:** perigrin, 2026-11-14 -- retire Context.pm in three steps: (1) move
what T2 borrows and split T2.pm, (2) build T2's four missing slices, (3) drop
the fallback and delete Context.pm. For step 1: "do that move *and* do the
printer polymorphism cleanup too; that will reduce the scope of both T2 and
Context.pm". Also: "T2" names the design (the lowering functor), not a file;
T2.pm is entirely LLVM-specific and is named for what it is.

Every sub-step here is **behaviour-preserving**. Its test is the existing
suite plus the verify gates: census ROUNDTRIP/DIFFERS/LLI_FAIL unchanged,
corpus gate-green and t2-gate-green unchanged, no new wrong probe, no new
suite failure. Each sub-step is its own commit (or a short series), verified
before it lands.

## Where things stand (measured 2026-11-14)

T2.pm (8.5k lines) holds four packages:

| Lines | Package | What it is |
|---|---|---|
| 25-33 | `T2::Node` | an LLVM instruction: op, type, inputs, attr, name |
| 34-107 | `T2` (`lower_program`) | the entry |
| 108-3702 | `T2::Builder` | the functor: chalk IR graph -> T2::Nodes |
| 3703-end | `T2::Printer` | T2::Nodes -> `.ll` text; `_line` is a ~120-branch switch on `op`; ~4.5k lines are the LLVM runtime as heredocs |

Of its 121 top-level subs: 83 are Builder methods; **30 are questions about
a chalk IR node** (none take a T2::Node). T2 and LLVM.pm also borrow from
Context.pm: `_graph_component` (17 uses), `_program_nodes` (11),
`_is_memory_phi` (9), `_cell_variable`, the Slot helpers (`_slot_idx`,
`_slot_tag_value`, `_slot_tag_for_repr`), and three tables (`RX_CODE_FN`,
`EVAL_BY_ENTRY`, `CLOSURE_DEFINES`).

## 1a. IR-node questions become IR methods

The 30 helpers read only an IR node, its inputs and consumers. Several are
switches on `operation` (`_is_version`: eight branches by op), the sign they
want to be polymorphic. They move onto chalk's IR classes, where both
backends -- and the Perl functor to come -- can ask them:

- **Node methods** (`lib/Chalk/IR/Node/*.pm`): `_is_version` ->
  `is_memory_version` (each class answers); `_in_place` -> RegexSubst;
  `_goes_on`, `_region_outs`, `successors`, `successors_by_input` -> Region
  and control nodes; `_hash_var`, `_array_var`, `_named_hash`, `_pkg_agg`,
  `_pkg_agg_name`, `_pkg_literal_of`, `_aderef`, `_argv`, `_arg_subscript`,
  `_isa_var` -> PadAccess / EntryDef / Subscript; `_alias_ref`,
  `_alias_elem`, `_alias_guard` -> Ref / Subscript; `_const_choices`,
  `_const_pattern`, `_made_a_string` -> the value nodes.
- **From Context:** `_is_memory_phi` -> `Phi::is_memory`;
  `_graph_component`, `_program_nodes` -> `Chalk::IR::Graph` methods.
- **Perl facts belong on T1's side, in the IR** (perigrin). T2 holds two
  named tables (`%LIST_BUILTIN`, `%PERLS_OWN`) and ~15 builtin-name sets
  inline in regexes (`shift|pop|push|unshift|splice`: mutates its array;
  `keys|values|sort|reverse|caller`: returns a list; `join|sprintf|lc|uc|...`:
  returns a string; the tie family; ...). Most restate the per-builtin
  signatures `Chalk::Grammar::Perl::TypeLibrary` already holds
  (`push => { arg_types => ['Array', 'List'], return_type => 'Int' }`) and can
  drift from them. They become questions a builtin `Call` answers from its
  signature (`returns_list`, `mutates_array`, `result_type`, ...), with any
  fact the signatures lack added there or to a sibling table beside
  KeywordTable; `EntryDef` answers `is_perls_own`. No target keeps a list of
  builtins.
- **What stays in the LLVM target:** what is LLVM's -- `%CONVERT`, the
  `sitofp|zext|fptosi` set, and the LLVM spellings in `%SCALAR`, `%ARITH`,
  `%CMP`, `%SCMP`. Which family an op is in (arithmetic, numeric or string
  compare) is the IR's (`cmp_kind`); the target maps it to a spelling.
- **Not moved in 1a:** `_match_in_list`, `_list_use`, `_is_list` (list-use
  analysis that refuses from inside). They are T1's job -- Analysis should
  stamp the answer once -- and change design, so they are a separate step.

Context.pm keeps calling its own copies only where they differ; where they
are the same function, Context calls the IR method too, and its copy goes.
Order: the methods with no callers' state first; one family per commit.

## 1b. Printer polymorphism: one class per LLVM op

`_line` (`T2::Printer`) becomes a method per op: a `T2::Node` subclass for
each LLVM op (Const, ConstStr, Arith, Cmp, ...), each with its own `to_ll`;
`T2::Node` keeps the shared fields. The builder's `_n(op => ...)` constructs
the op's class. The printed `.ll` must be **byte-identical** before and
after: checked by diffing the `.ll` of every census and corpus program, not
only by their run results. The `@fmt_*`/runtime constants the printer emits
stay where they are until 1c.

## 1c. Rename and split T2.pm

| From | To |
|---|---|
| `T2::Node` and the op classes | `Chalk::Target::LLVM::Node`, `Chalk::Target::LLVM::Node::<Op>` |
| `T2::lower_program` | `Chalk::Target::LLVM::Lower` |
| `T2::Builder` | `Chalk::Target::LLVM::Builder`, then split by concern (control, values, calls, regex, containers) |
| `T2::Printer` | `Chalk::Target::LLVM::Printer` |
| the runtime heredocs | `Chalk::Target::LLVM::Runtime` |

Six files refer to the `T2` packages; they follow. `$T2::PATH` (which path a
program took) keeps its meaning under the new name. Docs and memory keep
saying "T2" for the design.

## What this sets up

Step 2 (T2's four missing slices: a computed field default, an if whose arm
leaves the loop, `//` over a non-Slot, a named hash's element through `->%*`)
lands in the smaller Builder. Step 3 drops the fallback in `LLVM.pm` and
deletes Context.pm, ElaboratedContext.pm and the Context-only tests.
`perl-recognize-phase5.t` then sweeps files of a size the recognizer can
finish, and the grammar additions (`$@`/`$!`, `@Pkg::x`, list and hash
slices, double-quoted heredocs) follow from what the split files still use.
