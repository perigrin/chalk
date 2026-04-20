# Chalk::Bootstrap — XS Target

> **ARCHIVED.** This PRD described a standalone `Target/XS.pm` class
> emitting XS directly, parallel to `Target/C.pm`. That approach was
> abandoned: Chalk evolved to emit C from the IR and generate thin
> per-class XS wrappers that bind to a shared `chalk.so` library
> (GitHub issue #662). No `Target/XS.pm` exists. See memory note
> `xs_target_evolution.md` and
> [`../../architecture/ir-lowering.md`](../../architecture/ir-lowering.md)
> for the current architecture. Preserved for history.

**Extending the BNF Compiler to Generate XS — Product Requirements Document**

| | |
|---|---|
| **Version** | 0.1 |
| **Date** | February 2026 |
| **Author** | Perigrin |
| **Language** | Perl 5.42 (feature class) + C (via XS) |
| **Type** | Implementation Specification |
| **Predecessor** | Chalk::Bootstrap PRD v0.9 (BNF-to-Perl Grammar Compiler) |

---

## 1. Executive Summary

This PRD extends the Chalk::Bootstrap compiler to emit XS as a second code generation target. The predecessor PRD produced a BNF compiler that generates a Perl Rules class (`Chalk::Target::Perl`). This PRD adds `Chalk::Target::XS`, which takes the same optimized Sea of Nodes IR and emits a buildable XS distribution — a `.xs` file containing C code with Perl API calls, a `.pm` stub for XSLoader bootstrapping, and a `Build.PL` for compilation.

The pipeline is invariant through optimization. Everything from Earley parsing through the composite semiring, IR generation, and the optimizer (IterPeeps → DCE → GCM) is unchanged. Only the final code generation phase differs: where `Chalk::Target::Perl` emits `feature class` source, `Chalk::Target::XS` emits C code wrapped in XS conventions.

**Acceptance criterion:** The recognizer built from the XS-compiled Rules class must accept and reject the same inputs as the recognizer built from both the hand-written Rules class and the generated Perl Rules class. Three interchangeable implementations, one recognition result.

### 1.1 Why XS?

The bootstrap grammar's output is data-centric — each rule method constructs and returns `Chalk::Grammar::Rule` and `Chalk::Grammar::Symbol` instances. This is the gentlest possible introduction to XS code generation: the C code allocates Perl data structures (`AV*`, `HV*`, `SV*`) using the Perl C API, with no complex control flow, no arithmetic, and no dynamic dispatch. It validates the XS code generation infrastructure on a tractable target before the larger compiler needs to emit XS for arbitrary Perl constructs.

The generated `.pm` stub loads the compiled XS module via XSLoader. This follows standard CPAN convention — Module::Build copies `.pm` files to `blib/` and the XS shared object to `blib/arch/`, and XSLoader finds the compiled code at load time.

### 1.2 Scope Boundary

This PRD covers generating XS for the BNF meta-grammar's Rules class only — the same 10 rule methods (plus desugared helpers) that `Chalk::Target::Perl` generates. The Actions class remains hand-written Perl. XS generation for the larger Perl subset compiler is out of scope.

## 2. Prerequisites

This PRD assumes a completed implementation of the Chalk::Bootstrap PRD v0.9:

- Earley parser with Leo optimization and scanless parsing
- Composite semiring (Boolean → SemanticAction)
- Sea of Nodes IR with hash consing and use-def chains
- Optimizer pipeline (IterPeeps → DCE → GCM)
- `Chalk::Target::Perl` producing a generated `Chalk::Grammar::BNF::Rules` class
- Self-referential bootstrap: the generated Perl Rules class is the active implementation
- Recognizer equivalence validated between hand-written and generated Perl Rules classes

The IR graph produced by the optimizer is the input to this PRD. No upstream components change.

## 3. XS Output Specification

### 3.1 Output Artifacts

`Chalk::Target::XS` produces a buildable distribution containing four files:

| File | Purpose |
|---|---|
| `lib/Chalk/Grammar/BNF/Rules.xs` | C code with XS interface — the compiled rule methods |
| `lib/Chalk/Grammar/BNF/Rules.pm` | XSLoader stub — loads the compiled shared object at runtime |
| `Build.PL` | Module::Build configuration for compiling the XS |

File paths are derived from the module name by the same convention as the Perl target: `Chalk::Grammar::BNF::Rules` maps to `lib/Chalk/Grammar/BNF/Rules.*`.

### 3.2 XS File Structure

The generated `.xs` file follows standard XS conventions (see perlxs):

```c
/* ---- C preamble ---- */
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* ---- XS section ---- */
MODULE = Chalk::Grammar::BNF::Rules  PACKAGE = Chalk::Grammar::BNF::Rules

# One XSUB per rule method follows...
```

**C preamble:** Everything before the `MODULE =` line is passed through as C code. The three required includes (`EXTERN.h`, `perl.h`, `XSUB.h`) are always present. `PERL_NO_GET_CONTEXT` enables efficient interpreter context access in threaded builds. Additional `#include` directives or helper function definitions may appear here if needed.

**MODULE/PACKAGE declaration:** A single `MODULE = ... PACKAGE = ...` line establishes the Perl namespace for all subsequent XSUBs. For the bootstrap, both MODULE and PACKAGE are `Chalk::Grammar::BNF::Rules`.

**XSUBs:** One XSUB per rule method. Each XSUB is a C function definition using XS conventions that the `xsubpp` compiler translates into the actual C glue code.

### 3.3 XSUB Structure for Rule Methods

Each rule method in the Rules class returns a `Chalk::Grammar::Rule` instance. In XS, this becomes an XSUB that constructs Perl data structures using constructor calls and the C API, then returns the result. The general pattern:

```c
SV *
Grammar(self)
    SV *self
  PREINIT:
    AV *expressions;
    AV *expr_0;
    SV *symbol;
    SV *rule;
  CODE:
    /* Build expressions array */
    expressions = newAV();

    /* Expression 0: the first alternative */
    expr_0 = newAV();

    /* Each symbol in the expression — constructed via ->new() */
    {
        dSP;
        ENTER; SAVETMPS;
        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSVpvs("Chalk::Grammar::Symbol")));
        /* push named constructor args: type => "reference", value => "Rule" */
        XPUSHs(sv_2mortal(newSVpvs("type")));
        XPUSHs(sv_2mortal(newSVpvs("reference")));
        XPUSHs(sv_2mortal(newSVpvs("value")));
        XPUSHs(sv_2mortal(newSVpvs("Rule")));
        PUTBACK;
        call_method("new", G_SCALAR);
        SPAGAIN;
        symbol = SvREFCNT_inc(POPs);
        PUTBACK;
        FREETMPS; LEAVE;
    }
    av_push(expr_0, symbol);
    /* ... more symbols ... */

    av_push(expressions, newRV_noinc((SV *)expr_0));

    /* Construct and return Rule via ->new() */
    {
        dSP;
        ENTER; SAVETMPS;
        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSVpvs("Chalk::Grammar::Rule")));
        XPUSHs(sv_2mortal(newSVpvs("name")));
        XPUSHs(sv_2mortal(newSVpvs("Grammar")));
        XPUSHs(sv_2mortal(newSVpvs("expressions")));
        XPUSHs(sv_2mortal(newRV_noinc((SV *)expressions)));
        PUTBACK;
        call_method("new", G_SCALAR);
        SPAGAIN;
        RETVAL = SvREFCNT_inc(POPs);
        PUTBACK;
        FREETMPS; LEAVE;
    }
  OUTPUT:
    RETVAL
```

**Key XS features used:**

- **PREINIT section:** Declares C variables before typemap code runs. Required because variable declarations must precede code in C89.
- **CODE section:** Contains the construction logic. RETVAL is declared automatically by xsubpp based on the return type.
- **OUTPUT section:** Declares RETVAL as the return value, triggering xsubpp to place it on the Perl stack.
- **SV\* return type:** Returns a generic Perl scalar (which will be a reference to the constructed Rule object). Using `SV*` avoids the AV*/HV* refcount bug documented in perlxs — RETVAL is automatically mortalized for `SV*`.

### 3.4 Object Construction Strategy

The Rules class methods construct `Chalk::Grammar::Rule` and `Chalk::Grammar::Symbol` instances. Both are `feature class` objects.

**Why constructor calls are the only option:** `feature class` objects are *not* blessed hashrefs. They are a distinct SV type (`SVt_PVOBJ`) — a fixed-size array of SV pointers indexed by field position, where `builtin::reftype` returns `"OBJECT"`, not `"HASH"`. There is no documented C API for constructing `SVt_PVOBJ` instances from XS. The internal field layout is an implementation detail of the Perl interpreter, not a stable interface for extension writers.

This means the XS target **must** call the Perl constructors rather than directly building objects from C. This is not a compromise — it's the correct approach, and the overhead is minimal because `feature class` constructors are themselves XSUBs (see perlclassguts). An XSUB calling another XSUB is essentially C-to-C with Perl stack management, not a full Perl method dispatch.

**Symbol construction from XS:**

```c
/* Construct a Chalk::Grammar::Symbol via ->new() */
{
    dSP;
    ENTER; SAVETMPS;
    PUSHMARK(SP);
    /* Push class name and constructor arguments */
    XPUSHs(sv_2mortal(newSVpvs("Chalk::Grammar::Symbol")));
    XPUSHs(sv_2mortal(newSVpvs("type")));
    XPUSHs(sv_2mortal(newSVpvs("reference")));
    XPUSHs(sv_2mortal(newSVpvs("value")));
    XPUSHs(sv_2mortal(newSVpvn("Grammar", 7)));
    /* Optional: quantifier => "+" */
    PUTBACK;
    call_method("new", G_SCALAR);
    SPAGAIN;
    symbol = SvREFCNT_inc(POPs);
    PUTBACK;
    FREETMPS; LEAVE;
}
```

**Rule construction from XS:**

```c
/* Construct a Chalk::Grammar::Rule via ->new() */
{
    dSP;
    ENTER; SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSVpvs("Chalk::Grammar::Rule")));
    XPUSHs(sv_2mortal(newSVpvs("name")));
    XPUSHs(sv_2mortal(newSVpvn("Grammar", 7)));
    XPUSHs(sv_2mortal(newSVpvs("expressions")));
    XPUSHs(sv_2mortal(newRV_noinc((SV *)expressions)));
    PUTBACK;
    call_method("new", G_SCALAR);
    SPAGAIN;
    RETVAL = SvREFCNT_inc(POPs);
    PUTBACK;
    FREETMPS; LEAVE;
}
```

**Constructor argument convention:** `feature class` constructors accept named parameters matching `:param` field attributes. The XS code pushes key-value pairs onto the Perl stack in the same order as the Perl target's constructor calls. The constructor XSUB handles field initialization and ADJUST blocks internally — the caller provides arguments, not field assignments.

**Performance note:** Each rule method calls `Symbol->new()` once per symbol in the rule and `Rule->new()` once per method. For the BNF meta-grammar (~30-50 symbols across all rules), the total constructor overhead is negligible. The constructor calls happen once at grammar setup time, not per-parse. If profiling reveals constructor overhead matters for the larger compiler, the correct optimization path is to cache constructed Rule objects (they're immutable), not to bypass the constructor.

### 3.5 Regex Terminal Handling

Rule methods that describe terminal rules include regex pattern strings. In the Perl target, these are string literals that the parser compiles at match time. In the XS target, there are two strategies:

**Strategy A: String literals (recommended for bootstrap).** Emit the regex pattern as a C string constant. The parser compiles it to a regex object at match time, exactly as the Perl target does. This is the simplest approach and maintains behavioral equivalence.

```c
hv_store(sym_hash, "value", 5,
    newSVpvn("[A-Za-z_][A-Za-z_0-9]*", 22), 0);
```

**Strategy B: Precompiled regexes (deferred).** Use `pregcomp()` or `re_compile()` to compile the regex at module load time (in the BOOT section), storing compiled `REGEXP*` objects. This amortizes compilation cost across all uses but adds complexity:

- BOOT section must compile all patterns at load time
- Compiled regexes must be stored in package-scoped variables or a static array
- Thread safety considerations for compiled regex objects
- The parser must be aware that some values are pre-compiled `REGEXP*` rather than pattern strings

Precompiled regexes are a performance optimization. For the bootstrap (small grammar, few patterns), the overhead of runtime compilation is negligible. Strategy A is recommended; Strategy B is noted for future consideration when the larger grammar's pattern count makes it worthwhile.

### 3.6 XSLoader Stub

The `.pm` file generated by `Target::XS` is an XSLoader stub that loads the compiled shared library at runtime. This follows standard CPAN convention — Module::Build copies `.pm` files to `blib/lib/` and the compiled shared object to `blib/arch/`.

```
lib/Chalk/Grammar/BNF/Rules.pm   ← XSLoader stub (Chalk::Target::XS output)
lib/Chalk/Grammar/BNF/Rules.xs   ← C source (Chalk::Target::XS output)
```

**Loading behavior:**

1. `use Chalk::Grammar::BNF::Rules` triggers module search
2. Perl loads the `.pm` stub
3. XSLoader loads the compiled shared library (`.so` / `.dll`)
4. Rule methods are now XS functions in the symbol table

**PM stub content:**

```perl
# Generated by Chalk::Bootstrap compiler — do not edit
package Chalk::Grammar::BNF::Rules;
use v5.42;
use XSLoader;
our $VERSION = '0.01';
XSLoader::load(__PACKAGE__, $VERSION);
1;
```

**Call-site transparency:** No code that calls `Chalk::Grammar::BNF::Rules->Grammar()` needs to change. The method dispatch resolves to whichever implementation is loaded — pure Perl or XS. This is the same interface contract documented in the predecessor PRD §2.6.

### 3.7 Build System

The XS distribution uses Module::Build for compilation:

**Build.PL:**

```perl
use Module::Build;

Module::Build->new(
    module_name   => 'Chalk::Grammar::BNF::Rules',
    dist_version  => '0.01',
    needs_compiler => 1,
    xs_files      => { 'lib/Chalk/Grammar/BNF/Rules.xs'
                       => 'lib/Chalk/Grammar/BNF/Rules' },
)->create_build_script;
```

**Build and install:**

```bash
perl Build.PL
./Build
./Build test
./Build install
```

The build process invokes `xsubpp` to translate the `.xs` file into C, then compiles and links the resulting shared library. This is standard Perl XS toolchain — no custom build steps are needed.

**Dependency:** The build requires a C compiler and the Perl development headers. These are the same requirements as any XS module. No external C libraries are needed — the generated code uses only the Perl C API.

## 4. IR-to-XS Lowering

### 4.1 Pipeline Position

```
BNF source → [Earley + Semiring] → IR → [Optimizer] → Scheduled IR
                                                          ↓
                                            ┌─────────────┼─────────────┐
                                            ↓             ↓             ↓
                                     Target::Perl   Target::XS    (future targets)
                                            ↓             ↓
                                         .pm file    .xs + .pm + Build.PL
```

The optimizer produces a single scheduled IR graph. Each target consumes this graph independently. Targets are peers — `Chalk::Target::XS` does not depend on `Chalk::Target::Perl` or vice versa. (The `.pm` fallback file is produced by a separate `Chalk::Target::Perl` invocation, not by the XS target.)

### 4.2 IR Node Lowering Table

Each IR node type maps to a C code emission strategy. The XS target walks the scheduled IR graph and dispatches on node type, exactly as the Perl target does — but emitting C/Perl API calls instead of Perl source.

| IR Node | Perl Target (§3.8 predecessor PRD) | XS Target |
|---|---|---|
| **Start** | `method NAME ($self) {` | XSUB signature: `SV * NAME(self)` + PREINIT declarations |
| **Return** | `return $rule;` | `RETVAL = rule_sv;` + OUTPUT section |
| **Constant(String)** | Perl string literal: `"Grammar"` | `newSVpvn("Grammar", 7)` |
| **MakeSymbol** | `Chalk::Grammar::Symbol->new(...)` | `call_method("new", G_SCALAR)` on `Chalk::Grammar::Symbol` (§3.4) |
| **MakeExpression** | `[ $sym1, $sym2, ... ]` | `newAV()` + `av_push` sequence |
| **MakeRule** | `Chalk::Grammar::Rule->new(...)` | `call_method("new", G_SCALAR)` on `Chalk::Grammar::Rule` (§3.4) |

**PREINIT generation:** The XS target must collect all C variable declarations needed by the XSUB body and emit them in the PREINIT section. This requires a pre-pass over the IR subgraph for each method to determine the set of temporary variables. Variable names are generated deterministically: `expr_0`, `expr_1`, `sym_0`, `sym_1`, etc.

**String length computation:** `newSVpvn` requires explicit string lengths. The XS target computes these at code generation time from the constant values in the IR. For string literals known at compile time, `newSVpvs` (which uses `sizeof` to determine length automatically) is preferred where the string is a C string literal.

### 4.3 XS AST

The XS target uses an intermediate XS AST (already present in the codebase as `Chalk::Target::XS::AST::*`) to structure the generated code before emission. This decouples IR traversal from text generation:

| XS AST Node | Role |
|---|---|
| `Module` | MODULE/PACKAGE declaration line |
| `XSUB` | Complete XSUB: signature, PREINIT, CODE, OUTPUT |
| `Statement` | Raw C statement within an XSUB body |
| `VarDecl` | PREINIT variable declaration |
| `CompositeNode` | Groups children for sequential emission |

The XS target walks the IR, builds an XS AST, then calls `emit()` on the root node to produce the `.xs` file text. This is the same pattern as the existing Perl target's code generation.

### 4.4 Determinism

The same determinism guarantees from the predecessor PRD (§2.4) apply to XS output:

- XSUB order matches grammar order (same as method order in Perl target)
- Helper rule XSUBs appear immediately after the rule that introduces them
- Variable naming within each XSUB is deterministic and derived from IR traversal order
- The same BNF input always produces byte-identical `.xs` output

## 5. Validation

### 5.1 Three-Way Recognizer Equivalence

The central validation is recognizer equivalence across three implementations:

| Implementation | Source | How produced |
|---|---|---|
| **M0** | Hand-written Perl Rules class | Manual (predecessor PRD §5.1 Milestone 0) |
| **M4** | Generated Perl Rules class | `Chalk::Target::Perl` (predecessor PRD §5.1 Milestone 4) |
| **M5** | Generated XS Rules class | `Chalk::Target::XS` (this PRD) |

For any input string in the test corpus:

```
Recognizer(M0, input) == Recognizer(M4, input) == Recognizer(M5, input)
```

The M0 ↔ M4 equivalence is already validated by the predecessor PRD. This PRD adds M4 ↔ M5, and transitivity gives M0 ↔ M5.

**Test procedure:**

1. Generate `.xs` from the BNF meta-grammar
2. Build the XS distribution (`perl Build.PL && ./Build`)
3. Load the XS Rules class via the PMC overlay
4. Run the full recognizer test corpus (grammar coverage + rejection coverage)
5. Compare accept/reject results against M4 (generated Perl)

### 5.2 Build Validation

The XS output must survive the full build toolchain:

- `xsubpp` translates `.xs` to `.c` without errors or warnings
- C compiler compiles the generated `.c` without errors or warnings (`-Wall -Wextra`)
- Linker produces a loadable shared library
- `XSLoader::load` succeeds at runtime

Build failures are bugs in the XS target, not in the input grammar.

### 5.3 Structural Comparison

The generated `.xs` file can be structurally compared against the generated `.pm` file:

- Same number of methods/XSUBs
- Same method names in the same order
- Same rule names and expression counts in each method
- Same symbol types, values, and quantifiers

This is not a textual diff (the languages are different) but a structural audit confirming that both targets lower the same IR to equivalent outputs.

### 5.4 PMC Overlay Validation

Verify the XS loading mechanism:

1. With XS compiled: `.pm` stub loads via XSLoader, methods are XS
2. Recognizer built from XS module produces identical results to hand-written and Perl-generated versions

### 5.5 Determinism

Regenerating the XS output from the same BNF input must produce byte-identical `.xs`, `.pm`, and `Build.PL` files. This is validated by generating twice and diffing.

## 6. Development Milestones

### Milestone 5.0: XS Target Infrastructure

- Implement `Chalk::Target::XS` target class with the same interface as `Chalk::Target::Perl`: given a scheduled IR graph, produce output text
- Implement IR node visitors: `visit_Start`, `visit_Return`, `visit_Constant`, `visit_MakeSymbol`, `visit_MakeExpression`, `visit_MakeRule`
- Generate the C preamble and MODULE/PACKAGE declaration
- Generate PREINIT sections by pre-scanning each method's IR subgraph
- Emit the `.xs` file for the BNF meta-grammar
- Acceptance: `xsubpp` translates the generated `.xs` to valid C without errors

### Milestone 5.1: Object Construction

- Implement `Chalk::Grammar::Symbol` construction via `call_method("new", ...)` (§3.4)
- Implement `Chalk::Grammar::Rule` construction via `call_method("new", ...)` (§3.4)
- Implement expression array construction (`newAV` + `av_push`)
- Handle optional fields (quantifier on Symbol: present or absent as constructor argument)
- Acceptance: generated XSUBs compile and produce correctly typed `SVt_PVOBJ` instances at runtime

### Milestone 5.2: Build System and PMC

- Generate `Build.PL` for Module::Build compilation
- Generate `.pm` stub with XSLoader
- Validate full build cycle: `perl Build.PL && ./Build && ./Build test`
- Acceptance: XS module builds, loads, and methods are callable from Perl

### Milestone 5.3: Recognizer Equivalence

- Run full recognizer test corpus against XS Rules class
- Compare accept/reject results against generated Perl Rules class (M4)
- Validate structural equivalence (same methods, same rule structure)
- Validate PMC overlay transparency (both loading paths work)
- Acceptance: three-way recognizer equivalence (M0 == M4 == M5)

### Milestone 5.4: Determinism and Polish

- Validate byte-identical regeneration
- Clean compiler warnings (`-Wall -Wextra`)
- Validate thread safety (`PERL_NO_GET_CONTEXT` throughout)
- Document the XS target in the codebase
- Acceptance: all validation criteria from §5 pass

## 7. Design Decisions and Trade-offs

### 7.1 Constructor Calls, Not Direct Construction

An earlier draft of this PRD considered directly constructing `feature class` objects from C by building blessed hashrefs. This approach is incorrect: `feature class` instances are `SVt_PVOBJ`, a distinct SV type that is a fixed-size array of SV pointers indexed by field position (see perlclassguts). They are not blessed hashrefs, and there is no stable C API for constructing `SVt_PVOBJ` instances from extension code.

The XS target calls `->new()` via `call_method("new", G_SCALAR)`. This is not a performance compromise — `feature class` constructors are themselves XSUBs, so the call path is XSUB → Perl stack → XSUB (constructor) → field initialization. The Perl stack overhead is minimal compared to the actual work of constructing Rule and Symbol objects, and these constructors run once at grammar setup time, not per-parse.

This also means the XS target is insulated from changes to `feature class` internals. As long as the constructor API (named `:param` arguments) is stable, the generated XS code is correct.

### 7.2 String Literals vs. Precompiled Regexes

§3.5 documents two strategies for regex terminals in XS. String literals are simpler and maintain exact behavioral equivalence with the Perl target. Precompiled regexes amortize compilation cost but add complexity.

**Recommendation:** Use string literals for the bootstrap. The BNF meta-grammar has ~8 distinct regex patterns. Runtime compilation cost is negligible. Precompiled regexes become interesting when the grammar has hundreds of patterns (the larger Perl subset compiler), but that's a future concern.

### 7.3 What About `Chalk::Target::XS::AST`?

The existing codebase contains an XS AST layer (`Chalk::Target::XS::AST::*`) with nodes for Module, XSUB, Statement, VarDecl, etc. This PRD builds on that infrastructure rather than replacing it. The XS target populates the XS AST from the IR, then calls `emit()` to produce text — the same pattern used by the Perl target.

The existing AST nodes may need extension to support PREINIT sections and the specific C API call patterns described here. This is expected incremental work, not a redesign.

### 7.4 Why Module::Build and Not ExtUtils::MakeMaker?

Module::Build is pure Perl — no `make` dependency. For a compiler that needs to be self-contained and portable, avoiding external tool dependencies is valuable. ExtUtils::MakeMaker is more widely deployed but introduces a `make` dependency. Module::Build::Tiny is even lighter but may lack features needed for XS builds.

**Recommendation:** Use Module::Build. If deployment constraints require EU::MM compatibility, add it as a second build system later — the `.xs` file is the same regardless of build system.

## 8. Relationship to Larger Compiler

This XS target handles the simplest possible case: data-centric rule methods that construct and return Perl objects. The larger compiler will need XS generation for:

- Control flow (if/else, loops, pattern matching)
- Arithmetic and string operations
- Method dispatch and object construction for arbitrary classes
- Closures and lexical variable capture
- Exception handling (eval/die)

The infrastructure built here — the IR-to-XS lowering pattern, the XS AST, the build system, the PMC overlay, the validation strategy — extends naturally. Adding a new IR node type means adding a new visitor method to the XS target and a new XS AST node if needed. The pipeline architecture is untouched.

| Component | Bootstrap XS (this PRD) | Larger Compiler XS |
|---|---|---|
| IR node types lowered | Start, Return, Constant, MakeSymbol, MakeExpression, MakeRule | Full set including control flow, arithmetic, OO |
| C API patterns | `newSV*`, `newAV`, `av_push`, `call_method` (constructor calls) | Above + `SvIV`/`SvNV`, `croak`, control macros |
| XSUB complexity | Single CODE block, no branching | PPCODE blocks, variable return counts, error handling |
| Build system | Single-module distribution | Multi-module, possibly with shared C libraries |

## 9. Glossary

Extends the predecessor PRD glossary with:

| Term | Definition |
|---|---|
| Build.PL | Configuration file for Module::Build; defines how to compile XS to a shared library |
| PM stub | The `.pm` file generated by `Target::XS`; contains XSLoader bootstrapping code to load the compiled shared object. |
| PREINIT | XS keyword for declaring C variables before typemap code in an XSUB (perlxs) |
| XSUB | An XS subroutine; after `xsubpp` compilation, becomes a C function providing glue between Perl and C calling conventions (perlxs) |
| xsubpp | The XS compiler; translates `.xs` files into C source code (perlxs) |
| XSLoader | Perl module that dynamically loads compiled XS shared libraries at runtime |
| `newAV()` | Perl C API: allocates a new empty array (AV) |
| `av_push()` | Perl C API: appends an SV to an array |
| `newSVpvn()` | Perl C API: creates a new string scalar from a pointer and length |
| `newSVpvs()` | Perl C API: creates a new string scalar from a C string literal (length computed by sizeof) |
| `newRV_noinc()` | Perl C API: creates a reference to an SV without incrementing the referent's refcount |
| `call_method()` | Perl C API: invokes a named method on the object/class at the top of the Perl stack. Used to call `feature class` constructors from XS. |
| `SVt_PVOBJ` | The SV type used for `feature class` instances. A fixed-size array of SV pointers, distinct from hashes or arrays. Cannot be constructed directly from XS — must use the class constructor. (perlclassguts) |

## 10. References

Extends the predecessor PRD references with:

- **perlxs** — XS language reference manual. Documents XSUB structure, MODULE/PACKAGE keywords, CODE/PPCODE sections, PREINIT, OUTPUT, typemaps. Primary reference for XS code generation.
- **perlxstut** — XS tutorial. Step-by-step guide to building XS extensions.
- **perlguts** — Perl internal functions for extension writers. Documents `SV*`, `AV*`, `HV*` manipulation, reference counting, and object construction from C.
- **perlclassguts** — Internals of `feature class`. Documents `SVt_PVOBJ` instance representation, auto-generated XSUB constructors, field storage layout, and why direct object construction from XS is not possible. Critical reference for understanding why constructor calls are mandatory (§3.4).
- **perlapi** — Perl C API listing. Function-by-function reference for all C API calls used in generated code.
- **perlclib** — C library replacements provided by Perl. Safety guidelines for XS code.
- **perlxstypemap** — Typemap reference. Documents how XS translates between Perl and C types.
