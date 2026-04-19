# Chalk::Bootstrap — XS Target Implementation Specification

**Compiled from brainstorming session, February 2026**

| | |
|---|---|
| **Predecessor** | `docs/xs-target.md` (XS Target PRD v0.1) |
| **Language** | Perl 5.42 (feature class) + C (via XS) |
| **Scope** | Implementation spec for `Chalk::Bootstrap::BNF::Target::XS` |

---

## 1. Overview

This spec describes how to implement `Chalk::Bootstrap::BNF::Target::XS`, a second code generation target for the bootstrap compiler. It takes the same optimized Sea of Nodes IR that `Target::Perl` consumes and emits a buildable XS distribution: `.xs`, `.pm`, and `Build.PL` files.

The pipeline is unchanged through optimization:

```
BNF source → desugar → Earley parse → semantic actions → IR → Optimizer(DCE)
                                                                    ↓
                                                        ┌───────────┼───────────┐
                                                        ↓                       ↓
                                                  Target::Perl            Target::XS
                                                        ↓                       ↓
                                                     .pm file          .xs + .pm + Build.PL
```

Both targets consume the same optimized IR independently. They are peers — neither depends on the other.

**Acceptance criterion**: The recognizer built from the XS-compiled Rules class must accept and reject the same inputs as the recognizer built from both the hand-written Rules class and the generated Perl Rules class. Three interchangeable implementations, one recognition result.

## 2. Architecture Decisions

### 2.1 Fresh XS AST Nodes (Not Ported)

The main Chalk codebase has XS AST infrastructure (`Chalk::Target::XS::AST::*`), but those nodes are tightly coupled to main Chalk's richer IR (type system, class defs, field loads, etc.). The bootstrap has a deliberately simpler IR with 4 node types (Start, Return, Constant, Constructor).

**Decision**: Write fresh XS AST nodes in the `Chalk::Bootstrap::BNF::Target::XS::AST::*` namespace, purpose-built for the bootstrap's data-centric code generation. The IR will grow richer over time, and the AST can grow with it.

### 2.2 AST Reflects XS Structure; Walker Handles Semantics

The XS AST models XS-level constructs (modules, XSUBs, C statements, variable declarations). It does NOT have construction-specific nodes for Symbol/Expression/Rule — those semantic distinctions are handled by the `Target::XS` walker, which assembles the appropriate C statement sequences from generic AST primitives.

This is the same separation of concerns as the XS language itself: xsubpp handles the XS structure, the programmer writes the C logic.

### 2.3 Object Construction via `call_method("new")`

Symbol and Rule objects are constructed by calling their Perl constructors via `call_method("new", G_SCALAR)`. Each construction is a `{ dSP; ENTER; SAVETMPS; ... FREETMPS; LEAVE; }` block pushed as a single Statement node.

This is the safe, correct approach — it respects `feature class` constructor semantics, `:param` validation, and any future ADJUST blocks.

```c
// NOTE: Direct SVt_PVOBJ construction (newSV_type + ObjectFIELDS) is possible
// and would avoid Perl stack overhead. Symbol and Rule are simple data classes
// with no ADJUST blocks, so direct construction would be safe. Deferred as a
// future optimization — see docs/xs-target.md §7.1 and the outbreed-fulcrumage
// Binary.xs for a working example of direct ObjectFIELDS manipulation.
```

### 2.4 Proper Graph Visitor (Not Flat Iteration)

`Target::Perl` cuts corners by iterating the IR rule list directly, ignoring the Sea of Nodes graph structure. `Target::XS` does it properly:

- **Start node** → begins an XSUB (signature, PREINIT setup)
- **Constant nodes** → emit `newSVpvs()`/`newSVpvn()` string literals
- **Constructor nodes** → dispatch on class (Symbol/Expression/Rule) to emit appropriate C patterns
- **Return node** → closes the XSUB (RETVAL assignment, OUTPUT section)

Walk the graph from Start, follow edges, let the graph traversal order drive emission sequence. Sea of Nodes has a defined traversal order — the XS target respects it.

### 2.5 Single-Pass Accumulator for PREINIT

XS requires C variable declarations in a PREINIT section before the CODE body (C89 requirement). Rather than walking the IR twice (once for declarations, once for code), the walker does a single pass:

1. Walk the IR graph for each method
2. Accumulate VarDecl nodes into a side list as CODE statements are generated
3. The XSUB AST node partitions accumulated nodes at emit time — VarDecls go to PREINIT, everything else goes to CODE

### 2.6 Shared Optimized IR

One optimizer run produces one scheduled IR graph. Both targets consume it independently. No target-specific optimization passes for now.

Target-specific passes (e.g., pre-computing string lengths for `newSVpvn()`, hoisting common constructor patterns) are a future optimization.

### 2.7 Determinism

Sea of Nodes defines the graph traversal order. Everything feeding into the XS target is deterministic — same IR graph, same walk order, same output. No special effort needed beyond following the graph structure.

## 3. XS AST Node Set

Six AST nodes, all in `Chalk::Bootstrap::BNF::Target::XS::AST::*`:

| Node | Purpose | `emit()` output |
|---|---|---|
| **Node** | Abstract base class | (subclass responsibility) |
| **Module** | MODULE/PACKAGE declaration | `MODULE = Chalk::Grammar::BNF::Rules  PACKAGE = Chalk::Grammar::BNF::Rules` |
| **Preamble** | C preamble before MODULE line | `#define PERL_NO_GET_CONTEXT` + `#include` directives |
| **XSUB** | Complete XSUB with sections | Signature + PREINIT + CODE + OUTPUT |
| **VarDecl** | C variable declaration | `AV *expressions;` (emitted in PREINIT) |
| **Statement** | Raw C statement | Any C code line (emitted in CODE) |
| **CompositeNode** | Groups children | Sequential emission of children |

### 3.1 XSUB Node Detail

The XSUB node holds:

- `return_type` — C return type (typically `SV*`)
- `name` — XSUB/method name
- `params` — parameter list (e.g., `['SV *self']`)
- `body` — mixed list of VarDecl and Statement nodes

At emit time, XSUB partitions `body`:

```
SV *
Grammar(self)
    SV *self
  PREINIT:
    AV *expressions;      ← VarDecl nodes
    AV *expr_0;
    SV *symbol;
    SV *rule;
  CODE:
    expressions = newAV();  ← Statement nodes
    { dSP; ... }
    av_push(expr_0, symbol);
    ...
    RETVAL = rule;
  OUTPUT:
    RETVAL
```

### 3.2 Statement Node for Constructor Blocks

Each `call_method("new")` block is a single Statement node. The walker formats the complete multi-line block as one text blob:

```c
{
    dSP;
    ENTER; SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSVpvs("Chalk::Grammar::Symbol")));
    XPUSHs(sv_2mortal(newSVpvs("type")));
    XPUSHs(sv_2mortal(newSVpvs("reference")));
    XPUSHs(sv_2mortal(newSVpvs("value")));
    XPUSHs(sv_2mortal(newSVpvs("Rule")));
    PUTBACK;
    call_method("new", G_SCALAR);
    SPAGAIN;
    symbol_0 = SvREFCNT_inc(POPs);
    PUTBACK;
    FREETMPS; LEAVE;
}
```

One logical operation, one Statement node. Variable parts: class name, named argument pairs, target variable name.

## 4. Target Interface

### 4.1 Base Class Extension

Add `generate_distribution($ir)` to `Chalk::Bootstrap::Target`:

```perl
class Chalk::Bootstrap::Target {
    method generate($ir) {
        die "Subclass must implement generate()";
    }

    method generate_distribution($ir) {
        die "Subclass must implement generate_distribution()";
    }
}
```

### 4.2 Target::Perl Implementation

`Target::Perl` returns a single-file distribution:

```perl
method generate_distribution($ir) {
    return {
        'lib/Chalk/Grammar/BNF/Generated.pm' => $self->generate($ir),
    };
}
```

### 4.3 Target::XS Implementation

`Target::XS` returns a multi-file distribution:

```perl
method generate_distribution($ir) {
    return {
        'lib/Chalk/Grammar/BNF/Rules.xs'  => $self->generate($ir),
        'lib/Chalk/Grammar/BNF/Rules.pm'  => $self->_generate_pm_stub(),
        'Build.PL'                         => $self->_generate_build_pl(),
    };
}
```

`generate($ir)` returns just the `.xs` content (the interesting part). PMC and Build.PL are boilerplate generated by private methods.

## 5. IR-to-XS Lowering

### 5.1 Graph Walk

The walker starts at the IR's Start node and follows edges:

```
Start → [method entry]
  ↓
Constant(name) → string value for rule name
  ↓
Constructor(Symbol) → call_method block for each symbol
  ↓
Constructor(Expression) → newAV + av_push sequence
  ↓
Constructor(Rule) → call_method block with name + expressions
  ↓
Return → RETVAL assignment
```

### 5.2 Node-to-XS Mapping

| IR Node | Walker Action |
|---|---|
| **Start** | Begin XSUB: set return type, name, params |
| **Constant(String)** | Emit `newSVpvs("value")` or `newSVpvn("value", len)` |
| **Constructor(Symbol)** | Emit `call_method("new")` block for `Chalk::Grammar::Symbol` with type/value/optional quantifier args. Accumulate VarDecl for result variable. |
| **Constructor(Expression)** | Emit `newAV()` + `av_push()` sequence for each symbol in the expression. Accumulate VarDecl for the AV*. |
| **Constructor(Rule)** | Emit `call_method("new")` block for `Chalk::Grammar::Rule` with name + `newRV_noinc((SV*)expressions)`. Accumulate VarDecl for result. |
| **Return** | Emit `RETVAL = result_var;` |

### 5.3 Variable Naming

Deterministic, derived from graph position:

- `expressions` — the top-level expressions AV for the current rule
- `expr_N` — the Nth expression (alternative) AV
- `sym_N` — the Nth symbol SV across the entire XSUB
- `rule` — the constructed Rule SV (one per XSUB)

### 5.4 String Emission

Use `newSVpvs()` for C string literals (length computed by `sizeof` at compile time). This covers all constant strings in the bootstrap (class names, field names, rule names, symbol values).

For terminal regex patterns (stored as string values), strip `/` delimiters at code generation time (same as `Target::Perl`), escape for C strings (`\` → `\\`, `"` → `\"`), and emit as `newSVpvn("pattern", len)` with explicit length.

### 5.5 Optional Fields

Symbol's `quantifier` field is optional. When the IR has a quantifier Constant, emit the extra constructor arguments:

```c
XPUSHs(sv_2mortal(newSVpvs("quantifier")));
XPUSHs(sv_2mortal(newSVpvs("+")));
```

When quantifier is undef in the IR, omit these lines entirely (matching `Target::Perl`'s behavior).

## 6. Output Artifacts

### 6.1 XS File Structure

```c
/* Generated by Chalk::Bootstrap compiler — do not edit */
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* NOTE: Direct SVt_PVOBJ construction is possible for Symbol and Rule
 * (simple data classes, no ADJUST blocks). Currently using call_method
 * for correctness. See docs/xs-target.md §7.1 for optimization path. */

MODULE = Chalk::Grammar::BNF::Rules  PACKAGE = Chalk::Grammar::BNF::Rules

SV *
Grammar(self)
    SV *self
  PREINIT:
    ...
  CODE:
    ...
  OUTPUT:
    RETVAL

SV *
Rule(self)
    SV *self
  PREINIT:
    ...
  CODE:
    ...
  OUTPUT:
    RETVAL

# ... one XSUB per rule method, in grammar order ...
```

### 6.2 PMC Stub

```perl
# Generated by Chalk::Bootstrap compiler — do not edit
package Chalk::Grammar::BNF::Rules;
use v5.42;
use XSLoader;
our $VERSION = '0.01';
XSLoader::load(__PACKAGE__, $VERSION);
1;
```

### 6.3 Build.PL

```perl
use Module::Build;

Module::Build->new(
    module_name    => 'Chalk::Grammar::BNF::Rules',
    dist_version   => '0.01',
    needs_compiler => 1,
    xs_files       => { 'lib/Chalk/Grammar/BNF/Rules.xs'
                        => 'lib/Chalk/Grammar/BNF/Rules' },
)->create_build_script;
```

## 7. File Layout

### 7.1 New Files

```
lib/Chalk/Bootstrap/BNF/Target/XS.pm                      # XS emitter (graph visitor)
lib/Chalk/Bootstrap/BNF/Target/XS/AST/Node.pm             # Abstract base AST node
lib/Chalk/Bootstrap/BNF/Target/XS/AST/Module.pm            # MODULE/PACKAGE declaration
lib/Chalk/Bootstrap/BNF/Target/XS/AST/Preamble.pm          # C preamble (#define, #include)
lib/Chalk/Bootstrap/BNF/Target/XS/AST/XSUB.pm              # Complete XSUB with sections
lib/Chalk/Bootstrap/BNF/Target/XS/AST/VarDecl.pm           # C variable declaration
lib/Chalk/Bootstrap/BNF/Target/XS/AST/Statement.pm         # Raw C statement
lib/Chalk/Bootstrap/BNF/Target/XS/AST/CompositeNode.pm     # Groups children
t/bootstrap/xs-ast.t                                    # AST node unit tests
t/bootstrap/xs-target.t                                 # Target::XS unit tests
t/bootstrap/xs-build.t                                  # Full build + equivalence test
```

### 7.2 Modified Files

```
lib/Chalk/Bootstrap/Target.pm                          # Add generate_distribution()
lib/Chalk/Bootstrap/BNF/Target/Perl.pm                     # Implement generate_distribution()
```

## 8. Testing Strategy

### 8.1 AST Node Tests (`xs-ast.t`)

Unit test each AST node's `emit()` method in isolation:

- Preamble emits correct `#define`/`#include` block
- Module emits `MODULE = ... PACKAGE = ...` line
- VarDecl emits `TYPE name;` with correct formatting
- Statement emits raw C code with semicolon/formatting
- XSUB partitions body into PREINIT (VarDecls) and CODE (Statements)
- XSUB emits complete structure: signature, PREINIT, CODE, OUTPUT
- CompositeNode emits children in order

### 8.2 Target Tests (`xs-target.t`)

Test the IR-to-XS lowering without building:

- Single rule → correct XSUB structure
- Symbol with quantifier → constructor args include quantifier
- Symbol without quantifier → constructor args omit quantifier
- Expression with multiple symbols → correct `av_push` sequence
- Full BNF meta-grammar → complete `.xs` file with all XSUBs
- `generate_distribution()` → returns hashref with `.xs`, `.pm`, `Build.PL` keys
- Determinism: generate twice, compare output

### 8.3 Build Integration Tests (`xs-build.t`)

Follows standard CPAN convention — build is test setup:

1. Skip all unless: C compiler available, `xsubpp` available, Module::Build installed
2. Generate distribution via `generate_distribution($ir)` on optimized BNF IR
3. Write files to temp directory
4. Run `perl Build.PL && ./Build` in temp directory
5. Add `blib/` to `@INC`, load XS module
6. Run recognizer equivalence against hand-written Rules (M0) and generated Perl Rules (M4)
7. Validate three-way equivalence: M0 == M4 == M5

### 8.4 Validation Gates

Extend `bootstrap-validation.t` Phase 4 to note XS readiness, but keep XS build validation in `xs-build.t` to avoid toolchain dependencies in the core gate.

## 9. Implementation Milestones

### Milestone 5.0: XS AST Infrastructure

- Implement 6 AST node classes with `emit()` methods
- Full unit test coverage in `xs-ast.t`
- **Acceptance**: All AST nodes emit correct XS text fragments

### Milestone 5.1: Target::XS Graph Visitor

- Implement `Chalk::Bootstrap::BNF::Target::XS` with proper graph walking
- IR node visitors: Start, Return, Constant, Constructor(Symbol/Expression/Rule)
- Single-pass accumulator for PREINIT/CODE partitioning
- Symbol/Rule construction via `call_method("new")` blocks
- Expression construction via `newAV()`/`av_push()` sequences
- Add `generate_distribution()` to base Target and both implementations
- Generate complete `.xs` for BNF meta-grammar
- Full unit test coverage in `xs-target.t`
- **Acceptance**: `xsubpp` translates generated `.xs` to valid C without errors

### Milestone 5.2: Build System and PMC

- PMC stub generation
- Build.PL generation
- Full build cycle validation in temp directory
- **Acceptance**: `perl Build.PL && ./Build` succeeds, XSLoader loads module

### Milestone 5.3: Recognizer Equivalence

- Three-way recognizer comparison (M0 == M4 == M5)
- PMC overlay transparency validation
- Full integration test in `xs-build.t`
- **Acceptance**: All three implementations produce identical accept/reject results

## 10. Future Work

- **Direct SVt_PVOBJ construction**: Bypass `call_method("new")` for Symbol/Rule, constructing objects directly via `newSV_type(SVt_PVOBJ)` + `ObjectFIELDS`. See `outbreed-fulcrumage/Binary.xs` for working example.
- **Target-specific optimizer passes**: Pre-compute string lengths, hoist common constructor patterns, etc.
- **Fix Target::Perl graph walking**: Align `Target::Perl` with the proper visitor pattern used by `Target::XS`.
- **Precompiled regexes**: Use `pregcomp()` in BOOT section for regex terminals (deferred per PRD §3.5).
