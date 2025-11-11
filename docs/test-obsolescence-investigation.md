# Test Obsolescence Investigation - Phase 3

Investigation of potentially obsolete test files from comprehensive audit.

## Files Investigated

### 1. t/parser/ambiguous-baseline.t

**Purpose**: Test baseline ambiguous grammar parsing with Viterbi and Boolean semirings

**Status**: **KEEP WITH CLEANUP**

**Analysis**:
- Tests ambiguous grammar `E -> E+E | E*E | n` with multiple semirings
- `t/parser/02-parser-grammars.t` has similar ambiguous grammar test
- **However**: This file tests BOTH Viterbi and Boolean semirings explicitly
- **Additionally**: Has debug print statements that should be removed
- Not truly duplicate - tests semiring behavior specifically

**Recommendation**:
- Keep the file - it's testing semiring-specific behavior
- Remove debug print statements (lines 36-37 and similar)
- Consider renaming to `semiring-ambiguous-grammar.t` for clarity

**Action**: Clean up debug output, keep file

---

### 2. t/parser/augmented.t

**Purpose**: Test parsing with augmented start rule `S -> E`

**Status**: **KEEP - Already strengthened in Phase 2**

**Analysis**:
- Tests specific parser behavior with augmented start rules
- Was weak (had `ok 1`) but we JUST fixed it in Phase 2
- Now has proper assertions for 4 test cases
- Validates important edge case (augmented start rules)

**Recommendation**: Keep - recently improved and tests valid scenario

**Action**: None needed - already strengthened

---

### 3. t/parser/generalized.t

**Purpose**: Test general parsing without artificial start rule

**Status**: **KEEP - Already cleaned in Phase 1**

**Analysis**:
- Only 2 test cases but they're important
- Tests that `E` can be start symbol directly (no artificial `S -> E`)
- We already cleaned up debug output in Phase 1 (quick wins)
- Validates grammar can work without augmentation

**Recommendation**: Keep - tests important edge case, already clean

**Action**: None needed - already improved

---

### 4. t/bnf-parser-equivalence.t

**Purpose**: Compare grammars built via BNF parsing vs direct construction

**Status**: **KEEP - Important validation**

**Analysis**:
- Tests that `Chalk::Grammar::BNF->new()` produces equivalent grammars
- Validates BNF parser semantic actions work correctly
- Tests terminal escaping, comments, nonterminals, etc.
- This is validation that the BNF parser itself works

**Recommendation**: Keep - validates critical BNF parser functionality

**Action**: None needed

---

## Summary

**All 4 files should be KEPT**

- 1 file needs cleanup (ambiguous-baseline.t)
- 3 files are already in good shape

None of these files are truly obsolete. The audit flagged them for investigation due to:
- Small test counts (generalized.t)
- Debug output (ambiguous-baseline.t, augmented.t)
- Potential duplication (ambiguous-baseline.t vs 02-parser-grammars.t)

But investigation shows each serves a distinct purpose.

---

### 5. t/sea-of-nodes/chapter09.t vs t/sea-of-nodes/gvn.t

**Purpose**: Chapter 9 conceptual tests vs actual GVN implementation tests

**Status**: **KEEP BOTH - Different purposes**

**Analysis**:
- `chapter09.t` (492 lines): Tests GVN **concepts** through manual IR construction
  - Does NOT use actual `Chalk::IR::Optimizer::GVN` module
  - Tests theoretical understanding: redundant computation, node identity, commutativity, algebraic identities
  - Educational/conceptual tests that verify IR graph structure
  - All tests pass with basic assertions - no actual optimization runs

- `gvn.t` (883 lines): Tests the ACTUAL `Chalk::IR::Optimizer::GVN` implementation
  - Uses `use_ok('Chalk::IR::Optimizer::GVN')` and calls `->run_gvn($graph)`
  - Tests real optimization with metrics: `nodes_eliminated`, `redirections`
  - Production GVN implementation test

**Relationship**:
- chapter09.t teaches GVN concepts (educational)
- gvn.t validates GVN works (functional)
- Not duplicates - complementary purposes

**Recommendation**: Keep both files - they serve different purposes

**Action**: None needed - both files are valuable

---

## Actions Required

1. Clean up `t/parser/ambiguous-baseline.t`:
   - Remove debug print statements
   - Keep file - it tests semiring-specific behavior
   - Optional: Rename for clarity

2. No other actions - other files are fine

## Known Bugs Status

From audit section "10. Known Bugs Documented in Tests":
- ✅ Memory aliasing bug → Filed as issue #183
- ✅ Builder validation gap → Filed as issue #184
- ❌ chapter09.t "stub test" → Not a bug, files serve different purposes (see investigation above)
