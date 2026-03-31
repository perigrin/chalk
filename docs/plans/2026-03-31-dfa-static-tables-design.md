# Static DFA Tables via BNF::Target::C

**Date**: 2026-03-31
**Status**: Design
**Issue**: #679

## Problem

The LR0 DFA, CoreItemIndex, terminal maps, and completion maps are built at
runtime in Earley's ADJUST block, stored as Perl objects, and accessed via
method calls and hash lookups. In XS-compiled Earley, every access crosses
the Perl/C bridge. The DFA is deterministic from the grammar — rebuilding it
per parser instance is wasted work, and accessing it through Perl objects in
the hot loop is wasted bridge crossings.

## Solution

Add `BNF::Target::C` as a sibling to the existing `BNF::Target::Perl`. Both
consume the same BNF IR. The Perl target emits grammar Rule/Symbol objects.
The C target constructs CoreItemIndex + LR0DFA from the IR, then serializes
them as static C arrays using flattened-array-with-offset encoding.

```
BNF text → BNF parser → IR → BNF::Target::Perl → grammar.pm (Perl rules)
                            → BNF::Target::C    → dfa_tables.c + dfa_tables.h
```

The generated `dfa_tables.c` compiles into `chalk.so`. The XS-compiled
Earley `#include "dfa_tables.h"` and indexes the arrays directly. Pure-Perl
Earley is unchanged — it still builds its own DFA in ADJUST.

## Data Layout: Flattened Arrays with Offset Tables

### CoreItemIndex (7 parallel arrays, indexed by core_id)

```c
#define NUM_CORE_ITEMS N

static const char *ci_rule_names[NUM_CORE_ITEMS];
static const int ci_alt_idxs[NUM_CORE_ITEMS];
static const int ci_dots[NUM_CORE_ITEMS];
static const int ci_is_complete[NUM_CORE_ITEMS];
static const int ci_advance[NUM_CORE_ITEMS];        // core_id of dot+1, or -1
static const int ci_to_state[NUM_CORE_ITEMS];        // DFA state_id

// Symbol after dot: pattern string (NULL if complete) + type flag
static const char *ci_symbol_after_pattern[NUM_CORE_ITEMS];
static const int ci_symbol_after_is_ref[NUM_CORE_ITEMS];
```

### Terminal Maps (flattened + offsets)

```c
// Flat array of all core_ids across all states and patterns
static const int tmap_core_ids[TOTAL_TMAP_ENTRIES];

// Unique pattern strings (deduplicated across states)
static const char *tmap_patterns[NUM_UNIQUE_PATTERNS];

// Per (state, pattern) slice into tmap_core_ids
typedef struct { int pattern_idx; int offset; int count; } TMapSlice;
static const TMapSlice tmap_slices[TOTAL_TMAP_SLICES];

// Per state: where its slices start and how many
static const int tmap_state_offset[NUM_STATES];
static const int tmap_state_count[NUM_STATES];
```

Access pattern:
```c
int off = tmap_state_offset[state_id];
int cnt = tmap_state_count[state_id];
for (int i = 0; i < cnt; i++) {
    TMapSlice s = tmap_slices[off + i];
    const char *pattern = tmap_patterns[s.pattern_idx];
    for (int j = 0; j < s.count; j++) {
        int cid = tmap_core_ids[s.offset + j];
        // ...
    }
}
```

### Completion Maps (same encoding)

```c
static const int cmap_core_ids[TOTAL_CMAP_ENTRIES];
static const char *cmap_nonterminals[NUM_UNIQUE_NONTERMS];

typedef struct { int nonterm_idx; int offset; int count; } CMapSlice;
static const CMapSlice cmap_slices[TOTAL_CMAP_SLICES];
static const int cmap_state_offset[NUM_STATES];
static const int cmap_state_count[NUM_STATES];
```

### Goto Tables (flattened pairs)

```c
typedef struct { const char *symbol_key; int target_state; } GotoEntry;
static const GotoEntry goto_entries[TOTAL_GOTO_ENTRIES];
static const int goto_state_offset[NUM_STATES];
static const int goto_state_count[NUM_STATES];
```

### Prediction Items (flattened per nonterminal)

```c
typedef struct { int core_id; int skip_count; } PredictionEntry;
static const PredictionEntry prediction_entries[TOTAL_PRED_ENTRIES];

// Per nonterminal: offset and count into prediction_entries
static const char *prediction_nonterminals[NUM_PRED_NONTERMS];
static const int prediction_offset[NUM_PRED_NONTERMS];
static const int prediction_count[NUM_PRED_NONTERMS];
```

### Nullable Set

```c
static const char *nullable_nonterminals[NUM_NULLABLE];
static const int num_nullable;
```

## BNF::Target::C Module

```perl
class Chalk::Bootstrap::BNF::Target::C :isa(Chalk::Bootstrap::Target) {
    method generate($ir) {
        # 1. Extract Rule/Symbol objects from BNF IR (same logic as Target::Perl)
        # 2. Build CoreItemIndex from grammar
        # 3. Build LR0DFA from grammar + core_index
        # 4. Serialize to C arrays
        # Returns: { 'dfa_tables.c' => $c_text, 'dfa_tables.h' => $h_text }
    }
}
```

The module reuses the existing `CoreItemIndex->build_from_grammar()` and
`LR0DFA->build()` logic. No changes to those modules.

## Integration with Earley Codegen

**Phase A** (this issue): Generate the tables. Test by compiling the `.c`
file and verifying array contents match the Perl objects.

**Phase B** (future): Modify Target/C.pm's Earley codegen to emit C array
indexing instead of Perl object access. This requires detecting DFA access
patterns in the Earley IR and replacing them. Deferred — Phase A delivers
the tables; Phase B delivers the speedup.

## What Does Not Change

- Pure-Perl Earley continues building DFA in ADJUST
- BNF::Target::Perl is untouched
- The grammar Rule/Symbol objects are untouched
- LR0DFA.pm and CoreItemIndex.pm are untouched (read-only consumers)

## Testing

1. **Round-trip correctness**: Build DFA from test grammar, emit C tables,
   parse the C text to extract values, verify every entry matches the Perl
   object
2. **Determinism**: Emit twice, diff — must be byte-identical
3. **Compilation**: `cc -c dfa_tables.c` must succeed
4. **Completeness**: All 7 CoreItemIndex arrays + all 4 DFA map types present
5. **Header**: `dfa_tables.h` declares all arrays as `extern const`
