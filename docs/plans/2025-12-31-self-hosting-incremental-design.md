# Self-Hosting Incremental Compilation Design (#520)

## Summary

Prove Stage 0 self-hosting capability by incrementally compiling 5-10 core Chalk modules from `lib/` to XS and validating they work identically to pure Perl.

## Current State

- ✅ All 17/19 critical blockers closed
- ✅ `Chalk::Grammar::Token` already compiles to XS (Test 10 in `t/target/xs-class-e2e.t`)
- ⚠️ Only 1 of ~43 lib/ files tested
- 🎯 Need systematic proof across core modules

## Scope Decision

**Incremental approach: 5-10 core modules**
- Lower risk than full 43-file compilation
- Systematic gap discovery
- Faster iteration and debugging
- Proves self-hosting concept

## Module Selection Strategy

Dependency-ordered tiers, each module can use previously compiled modules:

**Tier 1 - Data structures (no dependencies):**
- `Chalk::Grammar::Token` ✅ (baseline)
- `Chalk::IR::Type::String`
- `Chalk::IR::Type::Integer`

**Tier 2 - Core IR nodes (depend on Tier 1):**
- `Chalk::IR::Node::Constant`
- `Chalk::IR::Node::Load`
- `Chalk::IR::Node::Store`

**Tier 3 - Complex components (depend on Tiers 1-2):**
- `Chalk::IR::Graph`
- `Chalk::Parser` (if dependencies allow)

## Test Structure

### Directory Layout
```
t/self-hosting/
├── 00-token.t              # Chalk::Grammar::Token (baseline)
├── 01-type-string.t        # Chalk::IR::Type::String
├── 02-type-integer.t       # Chalk::IR::Type::Integer
├── 03-node-constant.t      # Chalk::IR::Node::Constant
├── 04-node-load.t          # Chalk::IR::Node::Load
├── 05-node-store.t         # Chalk::IR::Node::Store
├── 06-ir-graph.t           # Chalk::IR::Graph
└── 07-parser.t             # Chalk::Parser (stretch goal)

t/lib/
└── Test/Chalk/CompileHelper.pm  # Shared compilation workflow
```

### Per-Test Workflow

Each test file:
1. Parse source module from `lib/`
2. Generate IR graph
3. Generate XS + PMC files
4. Compile to `.so` with ExtUtils::CBuilder
5. Load compiled module
6. Verify basic functionality
7. Compare behavior against pure Perl

### Shared Helper (Test::Chalk::CompileHelper)

Encapsulates:
```perl
sub compile_module {
    my ($module_path) = @_;

    # 1. Parse with ChalkIR semiring
    my $ir_root = parse_chalk_file($module_path);

    # 2. Build IR graph
    my $graph = build_ir_graph($ir_root);

    # 3. Generate XS
    my $xs_target = Chalk::Target::XS->new(
        graph => $graph,
        module_name => extract_module_name($module_path)
    );
    my $files = $xs_target->generate_files();

    # 4. Write and compile
    my $so_file = write_and_compile($files, $tempdir);

    return {
        so  => $so_file,
        pmc => $files->{pmc},
        xs  => $files->{xs}
    };
}
```

Helper provides:
- Grammar loading (cached)
- Parse workflow
- IR graph construction
- XS generation
- Compilation with proper error handling
- Diagnostics for each failure mode

## Failure Modes and Diagnostics

| Failure | Diagnostic |
|---------|------------|
| Parse failure | Syntax error with line/column |
| IR generation failure | Dump partial graph, identify missing visitor |
| XS compilation failure | Show C compiler errors |
| Load failure | Show Perl require errors with @INC |
| Behavior mismatch | Compare outputs, show diff |

Each test uses `TODO` blocks initially, converting to hard assertions as features stabilize.

## Success Criteria

**Per-module validation:**
1. ✅ Structural correctness - XS contains expected XSUBs
2. ✅ Functional correctness - Methods return expected values
3. ✅ Memory safety - No segfaults during lifecycle
4. ✅ Behavioral equivalence - XS ≡ Pure Perl

**Stage 0 completion criteria:**
- ≥5 core modules compile and run
- No segfaults or memory corruption
- Clear path identified for remaining modules
- Document any new blockers discovered

## What We'll Learn

- Which Perl features are actually used (vs. theoretical blockers)
- Missing XS visitors not anticipated in closed issues
- Performance characteristics of compiled code
- Module dependency order for full self-hosting

## Implementation Tasks

1. Create `t/lib/Test/Chalk/CompileHelper.pm`
2. Port Test 10 logic to use CompileHelper
3. Create `t/self-hosting/00-token.t` (baseline)
4. Add Tier 1 tests (Type::String, Type::Integer)
5. Add Tier 2 tests (Node::Constant, Load, Store)
6. Add Tier 3 tests (IR::Graph)
7. Document gaps and create targeted issues

## Deferred Items

Not in initial scope:
- Full 43-file compilation
- Performance benchmarking (covered by existing tests)
- Test suite execution with compiled lib/

These are follow-up work after initial proof succeeds.
