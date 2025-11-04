# Chalk Delivery Roadmap

**Generated:** 2025-11-03
**Current Status:** Self-hosting at 100% (parsing), Context abstraction complete (PR #140)
**Goal:** Self-hosting compiler that can compile and execute Perl code

---

## Executive Summary

Chalk has achieved **100% self-parsing** (all 125 files in `lib/` parse successfully). The fundamental infrastructure is in place:
- ✅ Parser with Earley algorithm + SPPF forest representation
- ✅ Sea of Nodes IR with 34+ node types
- ✅ Context-as-closure memory model with collections and references
- ✅ IR Builder with semantic actions
- ✅ Threaded interpreter for IR validation
- ✅ Type inference system (latent types)
- ✅ Optimizer pipeline infrastructure

**The critical path to self-hosting is:** Fix IR generation → Implement Perl code generator → Bootstrap compiler.

This roadmap organizes the 41 open issues into pragmatic categories focused on **shipping a working self-hosting compiler** in the shortest time.

---

## 1. Critical Path Issues (MUST DO - IN ORDER)

These issues must be completed sequentially to achieve self-hosting. Total estimated time: **6-8 weeks**

### 1.1 Fix IR Generation Pipeline (1 week)
**Issue #112:** Fix --generate-ir to use SPPF+Semantic composite instead of SPPFViterbi
**Effort:** Medium | **Impact:** High (BLOCKER)

**Why critical:** Currently broken - uses wrong semiring composite, prevents IR generation from parsed code.

**Dependencies:** None (infrastructure exists, just needs wiring fix)

**What's needed:**
- Change `app.pl` to use `Composite(SPPF, Semantic)` instead of `SPPFViterbiSemiring`
- Create IR Builder before parsing and pass via `env`
- Wire up semantic actions to build IR during parse

**Success metric:** `./app.pl --generate-ir lib/Chalk/Parser.pm` produces valid IR graph

**Estimated complexity:** 1 person-week (mostly testing and validation)

---

### 1.2 Implement Perl Code Generator (4-6 weeks)
**Issue #127:** Implement Perl Code Generator for Self-Hosting (Chalk::CodeGen::Perl)
**Effort:** Complex | **Impact:** CRITICAL (BLOCKER for self-hosting)

**Why critical:** This is THE blocker for self-hosting. Without code generation, Chalk cannot produce executable code.

**Dependencies:** Issue #112 (IR generation must work)

**Implementation phases:**
1. **Phase 1: Data operations** (2-3 hours) - Constant, Add, Subtract, Multiply, Divide
2. **Phase 2: Variables** (1-2 hours) - Load/Store with lexical scoping
3. **Phase 3: Control flow** (3-4 hours) - If/Region/Phi nodes (trickiest part)
4. **Phase 4: Function structure** (2-3 hours) - Start/Proj/Return nodes
5. **Phase 5: Context handling** (2-3 hours) - Arrays, hashes via Context model
6. **Phase 6: Testing** (2-3 hours) - Comprehensive test suite
7. **Phase 7: Module bundling** (4-6 hours) - Create standalone `chalk.app`

**Success metrics:**
- `chalk.app` generated from all Chalk source files
- `perl chalk.app compile test.chalk` produces working Perl code
- **Ultimate test:** `perl chalk.app compile lib/Chalk/Parser.pm > Parser.pl && perl Parser.pl` works

**Estimated complexity:** 4-6 person-weeks (16-24 focused hours per issue description, but account for edge cases)

**Technical notes:**
- Implement as visitor pattern (`Chalk::CodeGen::Perl` class)
- Focus on correctness over performance
- Use interpreter as reference for execution semantics
- Graph linearization provides nodes in execution order

---

### 1.3 Bootstrap Verification (1-2 weeks)
**Issue #14:** Bootstrap and Self-Host Verification
**Effort:** Complex | **Impact:** High (MILESTONE)

**Why critical:** Validates that self-hosting actually works - Chalk can compile itself.

**Dependencies:** Issues #112, #127 (both MUST be complete)

**What's needed:**
1. Compile chalk with itself → `chalk2`
2. Use `chalk2` to compile chalk source → `chalk3`
3. Verify `chalk2` and `chalk3` are functionally identical (bootstrap fixpoint)
4. Run all existing tests with self-compiled version
5. Performance and correctness verification

**Success metrics:**
- Bootstrap process reaches fixpoint (chalk2 ≈ chalk3)
- All tests pass with self-compiled version
- `chalk.app` works standalone (no `lib/` directory needed)

**Estimated complexity:** 1-2 person-weeks (mostly testing and edge case handling)

---

## 2. High-Impact Foundation Work (SHOULD DO SOON)

These enable multiple future features and significantly improve the system. Can be done in parallel with critical path once #112 is fixed. Total estimated time: **4-6 weeks**

### 2.1 Function Call Support (2-3 weeks)
**Issue #133:** Implement Function Call Support in IR and Interpreter (Chapter 11)
**Effort:** Complex | **Impact:** High

**Why important:** Required for any non-trivial program. Currently subroutine parsing works but calls don't execute.

**Dependencies:** None (can start immediately)

**What's needed:**
- `Call` IR node with control flow + arguments
- `FunctionDef` node for function signatures
- Separate IR graph per function
- Interprocedural control flow
- Return value handling

**Decision point:** Start with Call nodes (full support including recursion) rather than inlining

**Estimated complexity:** 2-3 person-weeks

**Impact on self-hosting:** Essential for compiling modules with function calls (most of Chalk)

---

### 2.2 Minimal ECA Architecture for Type Organization (1 week)
**Issue #146:** Implement Minimal ECA Architecture for Semantic Type Organization
**Effort:** Medium | **Impact:** High

**Why important:** Reduces cognitive load, speeds up type-specific feature development 2-3x

**Dependencies:** None (organizational refactor)

**What's needed:**
- Each semantic type becomes self-contained class (Int, Str, Num, Array, Hash, Any)
- Standard protocol: `name()`, `detect(value)`, `codegen(node, env)`, `optimize(node, env)`
- Type registry in Environment
- Migrate type detection/codegen from switch statements to type classes

**Benefits:**
- Adding new type: 3-5x faster (1 file vs 3-5 files)
- Better debugging (direct to type class vs searching switches)
- Easier testing (isolated type behavior)

**Estimated complexity:** 1 person-week (~5 hours implementation per issue, account for testing)

**Impact on self-hosting:** Makes code generator implementation (Issue #127) easier and cleaner

---

### 2.3 Context Optimizations (2 weeks)
**Issue #143:** Optimize context operations: inlining, escape analysis, constant folding
**Effort:** Medium | **Impact:** Medium

**Why important:** Context-as-closure model creates overhead; these optimizations make it practical

**Dependencies:** Issue #130 Phase 3-4 complete ✅

**Optimization opportunities:**
1. **Reference inlining** - Inline non-mutated references (eliminate dereference overhead)
2. **Escape analysis** - Non-escaping collections use SSA values instead of contexts
3. **Constant label folding** - Fold compile-time constant context lookups
4. **Context extension chain compaction** - Batch multiple extends into single operation

**Estimated complexity:** 2 person-weeks

**Impact on self-hosting:** Improves generated code performance, may be needed if bootstrap is too slow

---

## 3. Quick Wins (LOW EFFORT, DO ANYTIME)

These provide immediate value with minimal effort. Good for filling gaps between larger tasks. Total estimated time: **1-2 weeks**

### 3.1 Parser Bug Fixes (2-3 days)

**Issue #62:** Heredoc preprocessor fails to transform multiple heredocs on same line
**Effort:** Low | **Impact:** Medium
**Complexity:** 2-3 hours
**Why:** Simple bug fix, improves parser correctness

**Issue #70:** BNF parser incorrectly includes standalone comment lines in grammar rules
**Effort:** Low | **Impact:** Medium
**Complexity:** 2-3 hours
**Why:** Simple bug fix, improves grammar maintainability

**Issue #64:** BNF grammar should be whitespace-insensitive for epsilon productions
**Effort:** Medium | **Impact:** Medium | **Label:** good first issue
**Complexity:** 4-6 hours
**Why:** Improves grammar ergonomics, good for new contributors

**Combined complexity:** ~2-3 person-days for all three

---

### 3.2 Error Reporting (1 week)

**Issue #61:** Parser should report original line numbers, not preprocessed line numbers
**Effort:** Medium | **Impact:** Medium
**Complexity:** 1 person-week
**Why:** Dramatically improves debugging experience (users see correct line numbers)

**Issue #9:** Improve Error Handling and Diagnostics
**Effort:** Medium | **Impact:** High
**Complexity:** Ongoing (start with basics, iterate)
**Why:** Better error messages = faster development cycle

---

## 4. Nice to Have (DEFER UNTIL POST-SELF-HOSTING)

These are valuable but not critical for initial self-hosting. Estimated time: **8-12 weeks** (defer)

### 4.1 Advanced Type System Features

**Issue #145:** Implement ECA type namespaces for non-aliasing proofs
**Effort:** Medium | **Impact:** Medium
**Why defer:** Enables optimization but not required for correctness. Do after self-hosting works.

**Issue #135:** Enhance Semantic semiring type inference to handle operator patterns and coercion
**Effort:** Medium | **Impact:** Medium
**Why defer:** Improves type inference but current latent types sufficient for initial self-hosting

**Issue #136:** Add type validation and explicit coercion nodes to IR Builder
**Effort:** Complex | **Impact:** High
**Why defer:** Improves correctness but adds complexity. Self-host first, then harden.

---

### 4.2 Advanced Language Features

**Issue #142:** Support autovivification for nested data structures
**Effort:** Medium | **Impact:** Medium
**Why defer:** Nice Perl feature but not essential for Chalk self-hosting

**Issue #141:** Support tie() via method dispatch and operator overloading
**Effort:** Medium | **Impact:** Medium
**Why defer:** Advanced feature, low priority for initial self-hosting

**Issue #120:** Implement flip-flop operator (scalar context for ..)
**Effort:** Complex | **Impact:** Low
**Why defer:** Rare operator, minimal impact on self-hosting

**Issue #4:** Add Pattern Matching and Advanced String Operations
**Effort:** Complex | **Impact:** High
**Why defer:** Regex support important but not needed for bootstrapping Chalk itself

---

### 4.3 Grammar Improvements

**Issue #144:** Replace grammar-encoded operator precedence with precedence semiring
**Effort:** Complex | **Impact:** High
**Why defer:** Significant architectural change. Expected 2-5x speedup and 60-70% grammar reduction, but high risk. Do after self-hosting proves current approach works.

**Issue #50:** Refactor: Collapse R/L/U/0 expression variants using natural recursion patterns
**Effort:** Complex | **Impact:** High
**Why defer:** Large refactor, defer until grammar is stable and self-hosting works

**Issue #49:** Refactor grammar to eliminate NonBraceExpr variants
**Effort:** Medium | **Impact:** High
**Why defer:** Grammar cleanup, not critical for functionality

---

### 4.4 Performance Optimizations

**Issue #10:** Implement Leo Items for Linear Parsing
**Effort:** Medium | **Impact:** Medium
**Why defer:** Parser performance optimization. Current performance acceptable (100% self-parsing in ~5 minutes).

**Issue #11:** Optimize Chart Operations
**Effort:** Medium | **Impact:** Medium
**Why defer:** Parser performance. Optimize after self-hosting works.

**Issue #24:** Optimize Earley Parser Chart Size Using Marpa-Like Grammar Preprocessing
**Effort:** Complex | **Impact:** High
**Why defer:** Major parser optimization, defer until bottlenecks identified

**Issue #83:** Optimize Dominance Computation with Lengauer-Tarjan Algorithm
**Effort:** Medium | **Impact:** Medium
**Why defer:** Optimizer performance, not critical for initial self-hosting

**Issue #86:** Optimize Validator CFG Reachability Check Performance
**Effort:** Medium | **Impact:** Medium
**Why defer:** Validation performance, nice to have but not blocker

---

### 4.5 IR Infrastructure Enhancements

**Issue #139:** Implement fexpr-inspired IR enhancements: source preservation, transformation tracking, and context objects
**Effort:** Complex | **Impact:** High
**Why defer:** Improves debugging and metaprogramming but adds complexity. Self-host first.

**Issue #17:** Refactor LoadNode linking from execution phase to semantic phase
**Effort:** Medium | **Impact:** Medium
**Why defer:** Architectural improvement, not blocking self-hosting

**Issue #75:** Refactor peephole optimization to plugin-based system using comonad pattern
**Effort:** Medium | **Impact:** High
**Why defer:** Optimizer architecture, good design but not urgent

**Issue #131:** Implement Dead Code Elimination (DCE) Optimizer Pass
**Effort:** Medium | **Impact:** Medium
**Why defer:** Optimization pass, nice to have but not critical

**Issue #16:** Implement G-Set → OR-Set CRDT transition for parallel peephole optimization
**Effort:** Complex | **Impact:** Low
**Why defer:** Advanced optimization feature, very low priority

---

### 4.6 Testing and Validation

**Issue #128:** Expand Interpreter Test Coverage and Validate Against Perl 5.42.0
**Effort:** Medium | **Impact:** Medium
**Why defer:** Important for correctness but self-hosting is primary validation

**Issue #66:** Review all tests in t/ for relevance and correctness
**Effort:** Complex | **Impact:** Medium
**Why defer:** Test cleanup, do after self-hosting stabilizes

---

### 4.7 Bug Fixes - Non-Critical

**Issue #59:** Arrow expressions fail to parse when nested inside arrow method parameters
**Effort:** Complex | **Impact:** High
**Why defer:** Parser bug but likely rare case. Fix after self-hosting works.

**Issue #84:** Fix Platform-Dependent Integer Overflow Checking
**Effort:** Medium | **Impact:** Medium
**Why defer:** Edge case, address during hardening phase

**Issue #132:** Fix Loop Execution in Interpreter (Chapter 7-8 Test Failures)
**Effort:** Medium | **Impact:** Medium
**Why defer:** Interpreter bug, not blocking code generator approach

---

### 4.8 Documentation and Future Work

**Issue #52:** Write practitioner-level journal paper on simplified Perl grammar
**Effort:** Complex | **Impact:** High
**Why defer:** Academic contribution, do after self-hosting proves approach

**Issue #56:** Parse Fatpacked Version of Chalk
**Effort:** Medium | **Impact:** Medium
**Why defer:** Advanced packaging feature, not needed for initial self-hosting

**Issue #134:** Implement Sea of Nodes Chapters 12-24 Examples
**Effort:** Complex | **Impact:** TBD
**Why defer:** Educational/validation work, ongoing as features are needed

**Issue #87:** Add Validation for JSON Serialization of IR Attributes
**Effort:** Low | **Impact:** Low
**Why defer:** IR tooling enhancement, nice to have

---

## 5. Issues Not Blocking Self-Hosting

These are from older planning phases and largely superseded by recent work:

**Issue #13:** Add Compilation Infrastructure
**Status:** ✅ Mostly complete - IR infrastructure exists, just needs code generator (Issue #127)

**Issue #7:** Add Array and Hash Data Structures
**Status:** ✅ Complete via Issue #130 (arrays/hashes as contexts with ArrayGet/ArraySet/HashGet/HashSet nodes)

---

## Recommended Delivery Sequence

### Phase 1: Critical Path (Weeks 1-8)
**Goal:** Achieve basic self-hosting

1. **Week 1:** Fix Issue #112 (IR generation pipeline) ← START HERE
2. **Weeks 2-7:** Implement Issue #127 (Perl code generator) in phases
   - Weeks 2-3: Phases 1-3 (data ops, variables, control flow)
   - Weeks 4-5: Phases 4-5 (functions, contexts)
   - Weeks 6-7: Phases 6-7 (testing, bundling)
3. **Week 8:** Issue #14 (Bootstrap verification)

**Milestone:** Self-hosting compiler that can compile itself

### Phase 2: Stabilization (Weeks 9-14)
**Goal:** Make self-hosting practical

4. **Weeks 9-11:** Issue #133 (Function call support) - parallel work possible
5. **Week 12:** Issue #146 (ECA architecture) - improves maintainability
6. **Weeks 13-14:** Quick wins (Issues #62, #70, #64, #61) - improve UX

**Milestone:** Robust self-hosting with good ergonomics

### Phase 3: Performance & Features (Weeks 15-20)
**Goal:** Optimize and expand capabilities

7. **Weeks 15-16:** Issue #143 (Context optimizations)
8. **Week 17:** Issue #9 (Error diagnostics)
9. **Weeks 18-20:** Begin Feature work (Issues #142, #141, #135, etc.) based on user needs

**Milestone:** Production-ready self-hosting compiler

---

## Success Metrics

### Phase 1 Complete (Self-Hosting)
- ✅ `chalk.app` can compile all 125 files in `lib/` to Perl code
- ✅ Compiled Perl code runs correctly
- ✅ Bootstrap fixpoint reached (chalk2 ≈ chalk3)
- ✅ All core tests pass with self-compiled version

### Phase 2 Complete (Stabilization)
- ✅ Function calls work (can compile recursive functions)
- ✅ Error messages show correct line numbers
- ✅ Parser handles edge cases (heredocs, comments)
- ✅ Type system organized via ECA architecture

### Phase 3 Complete (Production-Ready)
- ✅ Generated code performance acceptable (within 10x of hand-written Perl)
- ✅ Context optimizations reduce overhead
- ✅ Comprehensive error diagnostics
- ✅ Advanced Perl features (autovivification, tie, etc.)

---

## Risk Assessment

### High Risk Issues

**Issue #127 (Code Generator):** Most complex task, many edge cases
- **Mitigation:** Incremental phases, use interpreter as reference, comprehensive testing
- **Contingency:** If too complex, consider simpler initial target (e.g., transpile to simpler Perl subset)

**Issue #133 (Function Calls):** Complex control flow, interprocedural analysis
- **Mitigation:** Start with simple non-recursive calls, add complexity incrementally
- **Contingency:** Initial self-hosting might work with inlined functions only

**Issue #144 (Precedence Semiring):** Architectural change with high impact
- **Mitigation:** Defer until after self-hosting, measure baseline first
- **Contingency:** Current grammar works, this is optimization not requirement

### Medium Risk Issues

**Issue #14 (Bootstrap):** May uncover edge cases in code generator
- **Mitigation:** Extensive testing in Issue #127 phases
- **Contingency:** Allow extra time for bug fixing

**Issue #143 (Optimizations):** Performance might not meet expectations
- **Mitigation:** Profile first, optimize hot paths
- **Contingency:** Generated code doesn't have to be fast, just correct

---

## Dependency Graph

```
Issue #112 (Fix IR Generation) [WEEK 1]
    ↓
Issue #127 (Perl Code Generator) [WEEKS 2-7]
    ↓
Issue #14 (Bootstrap Verification) [WEEK 8]
    ↓
SELF-HOSTING ACHIEVED ✅

Parallel tracks (can start after #112):
- Issue #133 (Function Calls)
- Issue #146 (ECA Architecture)
- Quick Wins (#62, #70, #64, #61)

After self-hosting:
- Issue #143 (Context Optimizations)
- Issue #9 (Error Diagnostics)
- Feature expansion based on user needs
```

---

## Notes on Issue Estimation

**Person-week estimates assume:**
- Full-time focused work (40 hours/week)
- Experienced developer familiar with codebase
- Includes implementation, testing, and documentation
- Includes time for code review and iteration

**Effort labels from issues:**
- Low: 2-8 hours
- Medium: 1-2 weeks
- Complex: 2-4 weeks

**Impact assessment:**
- High: Directly enables or blocks self-hosting
- Medium: Improves system significantly but not blocking
- Low: Nice to have, minimal impact on core goals

---

## Conclusion

**Chalk is 80% of the way to self-hosting.** The parser works perfectly (100% self-parsing), the IR infrastructure is solid, and the context abstraction is complete. The remaining 20% is:

1. **Fix IR generation wiring** (Issue #112) - 1 week
2. **Implement code generator** (Issue #127) - 4-6 weeks
3. **Bootstrap verification** (Issue #14) - 1-2 weeks

**Total critical path: 6-9 weeks of focused work.**

Everything else is optimization, features, or polish that can be done after achieving the self-hosting milestone.

**Recommendation:** Focus ALL effort on Issues #112 → #127 → #14 until self-hosting works. Defer everything else. Once Chalk can compile itself, you have a working foundation to build upon.
