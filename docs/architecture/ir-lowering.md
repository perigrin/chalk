<!-- ABOUTME: Architecture of Chalk's IR lowering and code generation targets. -->
<!-- ABOUTME: Covers Perl, XS, and C target backends, emission patterns, and the codegen pipeline. -->

# IR Lowering and Code Generation

This document describes Chalk's intermediate representation (IR) lowering pipeline and
its code generation targets: Perl (primary), XS (performance), and C (native
table compilation). An LLVM IR target is planned but deferred pending C/XS
completion; see [`../llvm-target.md`](../llvm-target.md) for the rationale. This
document covers the full pipeline from grammar and parse results through IR
construction, IR fixups, and final source emission.

---

## Overview

Chalk has two distinct codegen pipelines that share IR infrastructure but serve
different purposes:

1. **BNF pipeline**: BNF grammar source is parsed into a list of `Chalk::Grammar::Rule`
   objects, which are then lowered by a target into Perl, XS, or C. This pipeline
   produces grammar modules (recognizers).

2. **Perl pipeline**: Perl source files are parsed by the Earley parser into a
   `Chalk::IR::Program` node, which is then lowered by `Chalk::Bootstrap::Perl::Target::Perl`
   back into Perl source. This pipeline supports self-hosting validation: if the
   generated source compiles and behaves identically to the original, the compiler
   is correct.

Both pipelines use the same base class, `Chalk::Bootstrap::Target`. The target
interface is `generate($ir) -> HashRef[Str]` — a map of output path to source
content. Single-file targets return a one-entry hash; multi-file targets return
the full file set. Distribution packaging (`Build.PL`, `MANIFEST`, `.pm` stubs,
`XSLoader` shims) is a separate layer that consumes `generate()` output and
produces a CPAN-shaped distribution; it does not belong on the target interface.

The current code does not yet conform to this target shape. The base class
still has `die`-stubs for both `generate($ir)` and `generate_distribution($ir)`,
and individual targets diverge:

- **BNF targets** (`BNF/Target/Perl.pm`, `BNF/Target/XS.pm`, `BNF/Target/C.pm`)
  implement both `generate` and `generate_distribution`. `generate` sometimes
  returns a string and sometimes a hashref (e.g., `BNF/Target/C::generate`
  returns `{'dfa_tables.c' => ..., 'dfa_tables.h' => ...}`), so the return
  shape is already leaky.
- **`Perl/Target/Perl.pm`** implements both methods, plus a CFG-aware
  `generate_with_cfg($ir, $sa, $ctx)` that walks the parse-time Context tree
  to recover `cfg_state` annotations the IR graph does not yet carry.
- **`Perl/Target/C.pm`** implements neither `generate` nor
  `generate_distribution`. Its entry points are `generate_c_files($ir, $sa, $ctx)`
  and `generate_xs_wrapper($ir, $exported_functions, $anon_sub_registrations)`,
  which also require parse-time context.

Two distinct migrations are needed to reach the target shape:

1. **Remove the parse-time backchannel.** The context-aware methods
   (`generate_with_cfg`, `generate_c_files`, `generate_xs_wrapper`) exist
   because codegen reaches back into the SemanticAction semiring and the
   parse-time Context to recover `cfg_state` annotations that should live on
   IR nodes. Once `_build_method_graph` performs full SSA construction (Phi
   insertion, dominator analysis, data-flow rewriting) and codegen walks the
   per-method `MOP::Method->graph` instead of `MethodInfo->body`, the
   backchannel becomes unnecessary. The MOP migration plan at
   `docs/plans/2026-04-21-chalk-mop-migration-plan.md` tracks this work.
2. **Collapse the interface to `generate($ir) -> HashRef[Str]`.** Remove
   `generate_distribution` from the target interface; hoist distribution
   packaging into a separate layer. The design for this lives in task D1
   (`docs/plans/` once the design doc lands).

---

## Codegen Pipeline

### BNF to Grammar Module

```
docs/chalk-bootstrap.bnf
         |
    BNF Earley parser
         |
    Grammar IR (arrayref of Chalk::Grammar::Rule objects)
         |
    BNF::Target::Perl  --->  lib/Chalk/Grammar/BNF/Generated.pm
    BNF::Target::XS    --->  lib/Chalk/Grammar/BNF/Rules.xs + .pm + Build.PL
    BNF::Target::C     --->  dfa_tables.c + dfa_tables.h
```

The BNF pipeline reads the bootstrap grammar, constructs `Rule` and `Symbol` objects
from parse results, and emits them using the chosen target. The Perl target produces
`feature class` source equivalent to the hand-written `Chalk::Grammar::BNF`. The XS
target produces a `.xs` file with one XSUB per rule. The C target builds an LR0 DFA
from the grammar and serializes the automaton tables as static C arrays.

### Perl Source Round-Trip

```
lib/SomeClass.pm  (original source)
         |
    Earley parser (5-ary FilterComposite semiring)
         |
    Chalk::IR::Program
         |
    Perl::Actions fixups (_fixup_stmts, _fix_postfix_chain, etc.)
         |
    Chalk::Bootstrap::Perl::Target::Perl (generate_with_cfg)
         |
    Generated Perl source
```

The round-trip is valid when the generated source compiles without errors and the
resulting module is behaviorally equivalent to the original. This is the basis for
Tier validation testing.

---

## BNF Target: Perl

**File**: `lib/Chalk/Bootstrap/BNF/Target/Perl.pm`

The BNF Perl target takes an arrayref of `Chalk::Grammar::Rule` objects and emits a
`feature class` Perl module. Each `Rule` becomes a `push @rules, Chalk::Grammar::Rule->new(...)`
call, and each `Symbol` inside a rule is emitted as `Chalk::Grammar::Symbol->new(...)`.

Key behaviors:

- Terminal symbol values have their `/…/` regex delimiters stripped before embedding
  in single-quoted strings.
- Single-quoted string content is escaped via `_escape_single_quote` (backslash and
  apostrophe escaping only).
- The preamble hardcodes the output class name `Chalk::Grammar::BNF::Generated` and
  the required `use` declarations. The postamble closes the `grammar` sub and class body.
- `generate_distribution` returns a single-entry hashref:
  `lib/Chalk/Grammar/BNF/Generated.pm` mapped to the generated source.

---

## BNF Target: XS

**File**: `lib/Chalk/Bootstrap/BNF/Target/XS.pm`

The XS target generates one XSUB per grammar rule. Each XSUB constructs the rule's
`Chalk::Grammar::Symbol` and `Chalk::Grammar::Rule` objects using the Perl C API
(`call_method("new", G_SCALAR)` with `dSP`/`PUSHMARK`/`XPUSHs`/`PUTBACK` scaffolding).

Key behaviors:

- Per-rule counters (`$sym_counter`, `$expr_counter`) reset at the start of each
  `_emit_rule` call. This ensures generated C variable names (`sym_0`, `expr_0`) are
  stable and unique within each XSUB.
- Terminal values use `newSVpvn` with explicit byte-length when C escape sequences
  change the string length, and `newSVpvs` otherwise.
- Non-printable bytes in all string values are emitted as `\xHH` hex escapes.
- The distribution includes three files: the `.xs` source, a `.pm` stub that loads the
  compiled extension via `XSLoader`, and a `Build.PL` that configures `Module::Build`
  for compilation.

The XS target uses an internal AST (`BNF::Target::XS::AST::*`) to represent the
generated XS structure before final string emission via `CompositeNode->emit()`.

---

## BNF Target: C

**File**: `lib/Chalk/Bootstrap/BNF/Target/C.pm`

The C target does not directly emit grammar construction code. Instead, it builds a
complete `LR0DFA` from the grammar rules and serializes the automaton's state tables
as static C arrays. This approach precomputes the recognizer at compile time, eliminating
all runtime grammar construction cost.

### Pipeline

1. Normalize rules: strip `/…/` delimiters from terminal symbol values.
2. Build `CoreItemIndex` (maps core item IDs to rule/alt/dot positions).
3. Build `LR0DFA` (states, transitions, terminal maps, completion maps, goto tables,
   prediction items, nullable set).
4. Emit the tables as static C arrays into `dfa_tables.c`.
5. Emit struct typedefs and extern declarations into `dfa_tables.h`.

### Generated Files

`dfa_tables.h` provides:
- `#define` constants for all array sizes (`NUM_CORE_ITEMS`, `NUM_DFA_STATES`, etc.)
- Four struct typedefs: `TMapSlice`, `CMapSlice`, `GotoEntry`, `PredictionEntry`
- `extern const` declarations for every array in `dfa_tables.c`

`dfa_tables.c` provides:
- 8 `CoreItemIndex` parallel arrays indexed by core item ID
- Terminal map arrays (deduplicated pattern table + per-state slice index)
- Completion map arrays (same encoding, keyed by nonterminal name)
- Goto table arrays (flat entries + per-state offset/count)
- Prediction table arrays (per-nonterminal prediction items with skip-count)
- Nullable nonterminal string array

All hash iteration is sorted (`sort keys %{...}`) to guarantee deterministic output
across runs.

---

## Perl Target: Perl

**File**: `lib/Chalk/Bootstrap/Perl/Target/Perl.pm`

This is the primary target for the self-hosting pipeline. It walks a `Chalk::IR::Program`
tree and emits `feature class` Perl source.

### Entry Points

- `generate($ir)`: Takes a `Chalk::IR::Program`, returns a string of Perl source.
  Does not apply CFG-state dispatch; emits nodes using type-based dispatch only.
- `generate_with_cfg($ir, $sa, $ctx)`: The main entry point when a `SemanticAction`
  semiring and its `Context` tree are available. Builds the `%_cfg_lookup` side-table
  and `%_aggregate_vars` set before calling `_emit_program`. Clears both tables after
  emission.
- `emit_expr($node)`: Public wrapper around `_emit_expr`, used by tests and external
  callers.

### Statement vs. Expression Context

The emitter has two distinct modes:

- `_emit_node($node)`: Emits a statement. Adds semicolons where needed. Dispatches
  to CFG-state emission first, then to typed handlers for each IR node class.
  Every IR node type must have an explicit handler; hitting the catch-all `die` is a bug.
- `_emit_expr($node)`: Emits an expression. No trailing semicolons. When called on
  an expression node, it produces only the expression text; semicolons are added by
  the `_emit_node` wrapper when those same nodes appear in statement position.

The distinction matters for compound constructs. For example, a `BinOp` appearing
as a standalone statement is emitted by `_emit_node` as `$self->_emit_expr($node) . ";"`,
while the same `BinOp` inside a method argument list is emitted by `_emit_expr` without
punctuation.

### IR Node Dispatch

`_emit_node` checks CFG-state first, then dispatches by type:

| Node type | Handler |
|---|---|
| `Constant` (loop control) | bare keyword (`next;`, `last;`, `redo;`) |
| `Constant` (other) | `_emit_constant` (single-quoted string) |
| `BinOp`, `UnaryOp`, `Call`, `Subscript`, `PostfixDeref`, `HashRef`, `ArrayRef`, `AnonSub`, `RegexMatch`, `RegexSubst`, `BacktickExpr`, `Interpolate`, `TernaryExpr`, `StructRef`, `StructFieldAccess` | `_emit_expr($node) . ";"` |
| `VarDecl` | `_emit_var_decl` |
| `CompoundAssign` | `_emit_compound_assign($node) . ";"` |
| `UseInfo` | `_emit_use_decl` (uses `keyword()` field to emit `use` or `no`) |
| `FieldInfo` | `_emit_field_decl` |
| `MethodInfo` | `_emit_method_decl` |
| `SubInfo` | `_emit_sub_decl` |
| `ClassInfo` | `_emit_class_decl` |
| `Return` | `_emit_return_stmt` |
| `Unwind` | `_emit_die_call` |
| `TryCatch` | `_emit_expr($node) . ";"` |

`_emit_expr` dispatches to the appropriate `_emit_*_expr` method for each node type.
For `Call` nodes, dispatch additionally checks `dispatch_kind()`: `'method'` goes to
`_emit_method_call_expr` and `'builtin'` goes to `_emit_builtin_call`.

### CFG State Dispatch

When a `SemanticAction` semiring result is available, control-flow nodes (if/loop/try)
are emitted via CFG state rather than by inspecting IR node structure directly. The
`%_cfg_lookup` table maps `refaddr($ir_node)` to a `cfg_state` hashref populated by
`_build_cfg_lookup`.

`_build_cfg_lookup` walks the `Context` tree (breadth-first, stack-based) and registers
each IR node that has a `cfg_state` entry containing `if_node`, `loop`, or `try_node`.
It explicitly excludes `Program`, `UseInfo`, `ClassInfo`, `FieldInfo`, `MethodInfo`,
and `SubInfo` nodes from registration, because `cfg_state` propagates upward through
the comonad and those structural nodes would otherwise be incorrectly dispatched as
control flow.

The three CFG emission paths:

- `emit_cfg_if($if_node, $true_proj, $false_proj, $then_stmts, $else_stmts)`:
  Emits `if (...) { ... } elsif (...) { ... } else { ... }`. Handles
  `loop_jump` marker to emit `next if/unless $cond` instead of a full if-block.
- `emit_cfg_loop($loop, $loop_if, $body_proj, $exit_proj, $body_stmts, $iterator, $list)`:
  Emits `foreach`/`while`/`until` constructs.
- `emit_cfg_try_catch($try_stmts, $catch_var, $catch_stmts)`:
  Emits `eval { ... }; if ($@) { ... }`.

Per-method CFG schedules (from `MethodInfo->graph()->schedule()`) are merged additively
into `%_cfg_lookup` during `_emit_method_decl` and `_emit_sub_decl`. Method-local
schedules supplement the global lookup for nodes that may have been missed due to
stale-value merges in the parser. (`MethodInfo->graph()` is a delegating accessor
that reads from the parallel `MOP::Method->graph`; see `mop-layer.md`.)

### Aggregate Variable Tracking

`%_aggregate_vars` maps bare variable names (no sigil) to their aggregate sigil
(`%` or `@`). It is populated by `_scan_aggregate_vars`, which walks the entire IR
tree looking for `VarDecl` nodes whose variable name starts with `@` or `%`, and for
`FieldInfo` nodes with aggregate-sigil names.

This table is consulted by `_emit_subscript_expr` and `_format_subscript`. When the
target of a subscript expression is `$name` and `$name` appears in `%_aggregate_vars`
as a hash or array variable, the emitter uses direct subscript syntax (`$hash{key}`,
`$arr[i]`) instead of the arrow dereference syntax (`$hash->{key}`, `$arr->[i]`).

Method and sub bodies are scoped: `_scope_body_vars` removes parameter names from
`%_aggregate_vars` (parameters are always scalars) and adds body-local aggregate
declarations. The saved state is restored when the body finishes.

### VarDecl Initialization

`_emit_init_expr` handles one special case: when a `%hash` variable is initialized
with a `HashRef` node, the initializer is emitted as a parenthesized list `(k, v, ...)`
rather than a brace-delimited hash constructor `{ k, v, ... }`. Similarly, `@array`
initialized with an `ArrayRef` node emits `(elems)` rather than `[elems]`. This ensures
`my %h = (...)` and `my @a = (...)` are emitted instead of `my %h = {...}` and
`my @a = [...]`.

### StructRef and StructFieldAccess

`StructRef` and `StructFieldAccess` are high-level IR nodes that represent struct
construction and field access patterns. The Perl target lowers them back to their
hash-based representations:

- `_emit_struct_ref_expr`: Emits `{ 'field1' => val1, 'field2' => val2, ... }` using
  a schema registered via `set_struct_schemas`. If the schema is not found, emits `{}`.
- `_emit_field_access_expr`: Emits `$target->{'field_name'}`.

---

## IR Fixups in Perl::Actions

**File**: `lib/Chalk/Bootstrap/Perl/Actions.pm`

The Earley parser's `add()` method can merge stale pre-merge values when resolving
ambiguity. This produces IR trees with misparented nodes that cannot be directly
emitted. A set of post-processing fixups corrects these artifacts before the IR is
passed to the target.

### Root Cause

When the parser processes a statement like `return $self->method()->@*`, it may
complete the `return` and the postfix chain separately and then merge them with the
pre-merge value of one component. The result is a tree like
`PostfixDeref(Return(ctrl, MethodCall($self, method, [])), @)` instead of the correct
`Return(ctrl, PostfixDeref(MethodCall($self, method, []), @))`.

The fixups are pure tree transformations on immutable IR nodes. They create new nodes
via `NodeFactory->make(...)` rather than mutating existing ones.

### `_fixup_stmts`

Applied to every statement list (method body, sub body, class body). Merges statement
items that grammar ambiguity splits into consecutive items, including but not limited to:

- `return` (Constant) followed by a value node: merged into a `Return` CFG node.
- Bare `return` with no following value: merged into `Return(ctrl, Constant('undef'))`.
- `die` (Constant) followed by a value node: merged into an `Unwind` CFG node.
- `UseInfo(module, [])` followed by `Constant` nodes: merged into `UseInfo(module, [args])`.
- `BinaryExpr('=', VarDecl(var, undef), expr)`: collapsed into `VarDecl(var, expr)`.
- List-builtin expression restructuring: `BinaryExpr(op, BuiltinCall(list_builtin, [..., last]), right)` merges the binary right operand into the builtin's last arg, producing `BuiltinCall(list_builtin, [..., BinaryExpr(op, last, right)])`.
- Bare VarDecl merging: `VarDecl(var, undef)` followed by a non-boundary expression merges into `VarDecl(var, expr)`. Boundary detection prevents merging across statement-level constructs (Return, Unwind, metadata structs, CFG control flow, bare keywords, method/builtin calls).
- Bare builtin keyword folding: `Constant(builtin_name)` followed by args folds into `BuiltinCall(builtin_name, [args])`. Nested prefix builtins (e.g., `sort keys %$h`) are folded recursively.

### `_push_deref_inward`

Handles `PostfixDeref` whose target is a wrapper node that should be outside the deref:

```
PostfixDeref(Return(ctrl, X), @)
  → Return(ctrl, PostfixDeref(X, @))

PostfixDeref(BuiltinCall(scalar, [X]), @)
  → BuiltinCall(scalar, [PostfixDeref(X, @)])

PostfixDeref(MethodCall(BuiltinCall(push, [A, B]), m, []), @)
  → BuiltinCall(push, [A, PostfixDeref(MethodCall(B, m, []), @)])
```

The function iteratively peels wrapper layers, collects them, creates the deref at the
innermost real target, then rewraps the layers in correct (outside-in) order.

### `_push_methodcall_inward`

Same approach as `_push_deref_inward` but for `MethodCall` nodes whose invocant is a
prefix construct that should wrap the method call:

```
MethodCall(BuiltinCall(push, [A, B]), m, [])
  → BuiltinCall(push, [A, MethodCall(B, m, [])])
```

### `_fix_postfix_chain`

A bottom-up tree walk that corrects two structural misparentings:

1. `MethodCallExpr(PostfixDerefExpr(X, S), M, A)`
   → `PostfixDerefExpr(MethodCallExpr(X, M, A), S)`

2. `SubscriptExpr(BuiltinCall(prefix_builtin, [$var]), $key, style)`
   → `BuiltinCall(prefix_builtin, [SubscriptExpr($var, $key, style)])`
   Also handles the variant where a `Return` or `Unwind` node wraps the `BuiltinCall`.

3. `SubscriptExpr(UnaryExpr(op, X), $key, style)`
   → `UnaryExpr(op, SubscriptExpr(X, $key, style))`

4. `SubscriptExpr(BinaryExpr(op, L, R), $key, style)`
   → `BinaryExpr(op, L, SubscriptExpr(R, $key, style))`

### `$_fix_postfix_chain_deep`

A recursive variant of `_fix_postfix_chain` declared as a coderef to allow recursion
(Perl 5.42 class scope prevents `my sub` recursion). Applies `_fix_postfix_chain` to
the top node; if the transformation changes the node, recurses on the result. Otherwise
descends into `BinaryExpr`, `UnaryExpr`, and `BuiltinCall` children to fix inner
corruption.

### `$_unwrap_stmt_from_expr`

Extracts `Return` or `Unwind` nodes that have been trapped inside expression nodes by
stale-value merge. For each expression container type (`BinaryExpr`, `SubscriptExpr`,
`PostfixDerefExpr`, `TernaryExpr`, `MethodCallExpr`), if the relevant child is a
`Return` or `Unwind`, the function moves the expression construction inside the
statement node:

```
BinaryExpr(op, Return(ctrl, X), R)
  → Return(ctrl, BinaryExpr(op, X, R))
```

This ensures the statement-level nodes (`Return`, `Unwind`) appear at the statement
boundary rather than inside expressions, which is where `_emit_node` expects them.

---

## XS Wrappers for Perl Source

**File**: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (method `generate_xs_wrapper`)

The XS path for parsed Perl source is not a standalone target class. `Target/C.pm`
emits C code from the IR and also emits thin per-class XS wrappers that bind into
a shared `chalk.so` library via `generate_xs_wrapper()`. This is distinct from the
BNF XS target (`BNF/Target/XS.pm`), which emits grammar recognizer XSUBs; the
wrappers described here instead expose the compiled Perl class's public methods.

A hand-written standalone `Perl/Target/XS.pm` was evaluated and abandoned (GitHub
issue #662) in favor of the unified C-with-XS-wrappers approach above. See
`xs_target_evolution.md` in project memory for the narrative.

Key design decisions:

- **Per-class XS, not multi-class bundles**: Multi-class XS was evaluated and abandoned.
  Bundling all classes into one `.so` provides no speedup because `_run_parse` still
  falls back to `eval_pv`, making it no faster than pure Perl.
- **`_impl_` static helpers**: Methods that are called only within the same class are
  emitted as static C functions prefixed with `_impl_`. This eliminates `call_method`
  overhead for same-class calls, resulting in approximately 92 direct C calls versus
  64 remaining `call_method` calls in the Earley.pm XS.
- **BOOT block field initialization**: Uses the Perl 5.42 class C API
  (`setup_stash`, `prepare_initfield_parse`, `set_field_defop`) for field initialization.
- **CV cache correctness**: Static CV caches are used for non-`:param` fields
  (whose type is stable). `:param` fields are excluded from CV caching because they
  can hold objects of varying type per instance.
- **UTF-8 string handling**: `sv_len_utf8()` is used for character-count length
  rather than `SvCUR()` (which returns byte length). `sv_pos_u2b()` converts character
  offsets to byte offsets for `substr()` operations.

---

## Dependency Resolution

**File**: `lib/Chalk/Bootstrap/DepChaser.pm`

XS-wrapper and `chalk.so` compilation needs to know which Chalk classes a given class depends on — you can't compile `Chalk::Bootstrap::Earley` to XS without also compiling its `use`d Chalk modules. `DepChaser` resolves the transitive closure of Chalk module dependencies starting from a root file.

Mechanism (IR-driven, not source-scanning):

1. Parse the root file through the full Chalk pipeline into a `Chalk::IR::Program`.
2. Call `extract_use_decls($ir)` on the Program to get the list of module names from its `UseInfo` children.
3. Filter to `Chalk::*` names only — core and CPAN modules are assumed available via the runtime Perl environment and don't need Chalk compilation.
4. Map each module name to a `lib/X/Y/Z.pm` path via `module_to_path($name)`.
5. Recurse: for each dependency file, parse its IR, extract its `UseDecl`s, add to the queue.
6. Return the ordered list of transitive Chalk dependencies, excluding the root.

The `chalk.so` build script uses this result to decide which `.c` files to compile and link into the shared library. Because dependency extraction runs against the IR (not a text scan of `use` lines), it inherits the same grammar-level accuracy as the rest of the pipeline — no false positives from commented-out `use` statements or misparsed strings.

---

## C Target: chalk.so Pipeline

The C target produces `dfa_tables.c`/`dfa_tables.h` as part of the `chalk.so` pipeline.
This pipeline compiles the automaton tables into a shared library linked against the
Perl XS extension, allowing the hot path of the Boolean recognizer to execute entirely
in C without crossing the Perl/C bridge on each state transition.

The C target's `generate()` method returns a hashref with two keys rather than a single
string, matching the multi-file distribution shape:

```perl
{
    'dfa_tables.c' => $c_body,
    'dfa_tables.h' => $self->_emit_header(),
}
```

The `.c` file includes `chalk.h` (which sets up the Perl environment) and `dfa_tables.h`
(struct typedefs and extern declarations), followed by the array definitions with
external linkage (`const` arrays, not `static`).

This approach has been validated for the Boolean recognizer (proof of concept, 48 passing
tests in Phase 1 of the chalk.so architecture). The XS Boolean recognizer processes
`XS.pm` (5821 lines) in approximately 1 second; pure Perl takes over 20 minutes on
the same input.

---

## Tier Validation System

The Tier system provides progressive validation of the Perl pipeline against the actual
source files in `lib/`. Each tier covers a set of files with increasing complexity.
Tests parse each file, generate output, compile or evaluate it, and run behavioral
checks.

### Tier A: Simple Classes and Methods

Files with straightforward class structure: simple fields, readers, basic method bodies
with no complex control flow. The Perl target Tier A tests (`perl-target-perl-tier-a.t`)
parse each file, generate Perl, `eval` the output, and verify the resulting class
behaves identically to the original for a representative operation.

### Tier B: Moderate Complexity

Files with intermediate constructs: multiple method dispatch, simple hash/array
operations, conditional expressions. XS Tier B tests (`perl-target-xs-tier-b.t`)
additionally compile and load the generated XS module.

### Tier C: Complex Constructs

Files with advanced patterns: postfix deref chains, complex method calls, AnonSub
arguments to builtins, regex substitutions, try/catch blocks. The Perl IR Tier C
tests (`perl-ir-tier-c.t`) and Perl target Tier C tests validate the full pipeline.

### Tier D: Full Codebase

Tier D tests scan `lib/` dynamically and attempt to parse and compile every `.pm`
file. Tests are split across multiple files (`perl-target-xs-tier-d.t`,
`perl-target-xs-tier-d2.t`, `perl-target-xs-tier-d3.t`, `perl-target-xs-tier-d5.t`)
to manage test runtime. Individual tests use `skip_build` (marks a test as TODO for
XS compilation failures) and `todo_parse` (marks a test as TODO for parse failures)
to track known issues without failing the suite.

Current status as of the most recent commits: 16 of 29 files in the original Tier D
batch eval cleanly; the full Tier D population across all split files is tracked in
GitHub issues #691-#696.

---

## Known Issues and Remaining Blockers

### map BLOCK LIST with Bare Expressions

`map { $_->method() } @arr` where the block contains a bare method call expression
(not an `AnonSubExpr`) is emitted incorrectly by the XS target. The IR has the block
as a plain `MethodCallExpr` rather than an `AnonSubExpr`, so the block emission path
is not triggered. GitHub issue #691.

### Stale-Value Merge Variants

Several patterns in the Earley stale-value merge produce IR that the current fixup
passes do not handle. These include certain multi-level deref chains and specific
combinations of hash initialization with keys/values builtins. GitHub issues #692
and #693.

### C-style For Loops

`for (my $i = 0; $i < 10; $i++) { }` is not parsed by the current grammar. The
grammar covers `foreach` and postfix `for` but not C-style three-clause `for`. This
affects a small number of files that use numeric loop patterns. Tracked in
`docs/chalk-parse-perl-plan.md`.

### Punctuation Variables

`$!`, `$@`, `$_`, `$1`, `$2` and similar punctuation variables require special handling
in both the grammar (scan-time recognition) and the emitter (correct sigil/name
separation). Coverage is partial; several files with heavy use of `$@` in eval-based
error handling are marked TODO in Tier D.

### XS Reader Emission

Field `:reader` attributes do not currently emit named XSUBs. The structural checks in
Tier D tests for `type(self)`, `value(self)`, `name(self)`, and `id(self)` are marked
TODO pending this feature.

---

## Design Constraints

### Determinism

All code generation must produce byte-identical output across runs:

- Hash keys are always iterated in sorted order (`sort keys %{...}`).
- Node IDs are content-based (hash-consed), not creation-order-based.
- Per-rule counters (XS target) reset at rule boundaries, not globally.
- The DFA state ID assignment is deterministic from the grammar structure.

### Immutability

All IR nodes are immutable after construction. Fixup passes create new nodes via
`NodeFactory->make(...)` and return the new tree; they never modify nodes in place.
The `NodeFactory` uses hash-consing so structurally identical nodes share a single
object.

### No Catch-All in `_emit_node`

The `_emit_node` dispatch in `Perl::Target::Perl` ends with an unconditional `die`
rather than a default fallback. This is intentional: if a new IR node type is added
without a corresponding emitter, the failure is immediate and unambiguous rather than
silently producing incorrect output.
