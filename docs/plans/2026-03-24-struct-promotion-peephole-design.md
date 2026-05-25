# Struct Promotion Peephole Optimizer

## Problem

The Earley parser's inner loop spends ~67% of parse time in overhead dominated
by Perl hash operations. Profiling Structural.pm (374 lines, 68.6s parse)
shows 712K `_chart_has` calls, 119K `_chart_set` calls, and 710K agenda
iterations — each accessing item fields via `hv_fetch` with literal string
keys like `$item->{core_id}`.

The generated earley.c emits 107 `hv_fetch` calls on item fields alone, each
executed millions of times per parse. Every item creation allocates an HV with
6 key-value pairs. Every copy (`{ %$item, value => $new }`) allocates a fresh
HV and copies all 6 entries.

These hashes have fully-known key sets at compile time. The keys are string
literals, never computed dynamically. The hashes never escape to uncompiled
Perl code. This makes them candidates for replacement with C structs.

## Solution

A generic IR-level peephole optimizer pass that detects hashes with
fully-known key sets across all compiled classes and rewrites them to C
structs. This is not Earley-specific — any compiled class benefits.

## Architecture

### Pipeline Position

The pass runs after IR construction but before any target emits code:

```
Source .pm → Parse → IR → [Struct Promotion Pass] → Target::C → .c file
                                                  → Target::Perl → .pm (lowered back to hashes)
```

### New IR Node Types

**StructRef** — replaces `Constructor('HashRef')` when all keys are known.
Carries a schema identifier and field values in declaration order.

**FieldAccess** — replaces `SubscriptExpr` with a literal string key on a
struct-typed variable. Carries the schema name and field name.

Target::Perl lowers these back to hash operations (HashRef constructor, hash
key access). Target::C emits typedef + direct field access.

### Schema Definition

Each promoted hash type gets a schema:

```
{
    name   => 'earley_item_t',
    fields => [
        { name => 'rule',    c_type => 'SV *' },
        { name => 'alt_idx', c_type => 'IV'   },
        { name => 'core_id', c_type => 'IV'   },
        { name => 'dot',     c_type => 'IV'   },
        { name => 'origin',  c_type => 'IV'   },
        { name => 'value',   c_type => 'SV *' },
    ],
}
```

C types are inferred from usage: fields used only in integer operations
(SvIV, arithmetic, array indexing) become `IV`. Fields used as object
references, passed to method calls, or dereferenced with SvRV become `SV *`.

## Two-Pass Algorithm

### Pass 1: Schema Collection

Walk all methods in all compiled classes in a single pass.

1. **Constructor detection**: When a variable is assigned `{}` (empty HashRef)
   followed by literal-key assignments (`$x->{literal} = expr`), or assigned
   a hash literal (`{ key => val, ... }`), record the key set.

2. **Key accumulation**: Every `SubscriptExpr($var, literal_string_key)` adds
   that key to the variable's key set. If `SubscriptExpr($var, $dynamic_expr)`
   is seen (non-literal key), mark the variable non-promotable.

3. **Cross-method tracking**: When a method returns a hash variable, record its
   schema as the method's return schema. When a call site receives a return
   value, inherit the callee's return schema. When a hash is stored in a data
   structure and later retrieved, the schema propagates through the storage.

4. **Schema unification**: Variables with identical key sets flowing to the
   same usage point get the same schema name. Different key sets get separate
   schemas.

5. **Escape analysis**: If a hash reaches a method call on an uncompiled class,
   or is returned from a public method callable by uncompiled code, the schema
   is invalidated and the hash stays as HV*.

**Output**: A map of `{ schema_name => { fields, constructor_sites, access_sites } }`.

### Pass 2: IR Rewrite

Walk the IR again and rewrite nodes for each validated schema:

1. **Constructor sites**: `$x = {}` + `$x->{key} = val` sequence becomes a
   single `StructRef(schema, field1_val, field2_val, ...)`. Fields ordered by
   schema declaration order.

2. **Access sites**: `$x->{literal_key}` becomes
   `FieldAccess(schema, field_name, $x)`.

3. **Copy-with-override**: `{ %$old, value => $new }` becomes struct memcpy +
   single field write (new StructRef copying all fields from source, overwriting
   the named field).

4. **Storage sites**: Structs stored in containers remain as opaque SV*.
   Retrieved variables are re-tagged with their schema for subsequent
   FieldAccess nodes.

5. **C type inference**: Each field gets a C type based on usage across all
   access sites:
   - SvIV(), arithmetic, array indexing → `IV`
   - SvTRUE() only → `IV` (boolean as int)
   - Method calls, SvRV(), stored as SV* → `SV *`

## Target Emission

### Target::C

**Typedef** (emitted once per schema at file scope):
```c
typedef struct {
    SV *rule;
    IV  alt_idx;
    IV  core_id;
    IV  dot;
    IV  origin;
    SV *value;
} earley_item_t;
```

**StructRef** (allocation):
```c
SV *item_sv = newSV(sizeof(earley_item_t));
SvPOK_on(item_sv);
SvCUR_set(item_sv, sizeof(earley_item_t));
earley_item_t *item = (earley_item_t *)SvPVX(item_sv);
item->rule    = rule_sv;
item->alt_idx = alt_idx;
item->core_id = core_id;
item->dot     = dot;
item->origin  = origin;
item->value   = value_sv;
```

IV fields are stored as plain C integers — no SV allocation.

**FieldAccess** (direct access):
```c
// IV field — plain integer, no SV unwrapping:
((earley_item_t *)SvPVX(item_sv))->core_id

// SV* field — pointer dereference:
((earley_item_t *)SvPVX(item_sv))->value
```

**Copy-with-override** (memcpy + field write):
```c
SV *new_sv = newSV(sizeof(earley_item_t));
SvPOK_on(new_sv);
SvCUR_set(new_sv, sizeof(earley_item_t));
Copy(SvPVX(src_sv), SvPVX(new_sv), 1, earley_item_t);
((earley_item_t *)SvPVX(new_sv))->value = new_value;
```

### Target::Perl

**StructRef** lowers to hash constructor:
```perl
my $item = { rule => $rule, alt_idx => $alt_idx, ... };
```

**FieldAccess** lowers to hash key access:
```perl
$item->{core_id}
```

Perl behavior is unchanged. The optimization is transparent to the Perl target.

## Memory and Lifetime Model

**No refcounting required.** Items use SSA assignment — every "mutation" creates
a new struct (`{ %$old, value => $new }` → memcpy + field write). The old struct
is never modified.

Struct lifetime is governed by chart ownership:
- Struct is created as bytes inside an SV (via `newSV(sizeof(T))`)
- Chart slot holds the only reference to the wrapper SV
- When the chart slot is overwritten (merged item) or cleared (GC sweep),
  Perl decrements the wrapper SV's refcount to zero and frees it
- The struct bytes are freed as part of the SV's PV buffer

SV* fields inside the struct (`rule`, `value`) are borrowed pointers:
- `rule` is owned by the grammar array (alive for entire parse)
- `value` is a semiring value — either a singleton or created by multiply/add

Neither depends on the struct for its lifetime. No magic, no destructors,
no per-schema cleanup.

## Promotable Schemas (Current Codebase)

| Class | Schema | Fields | Impact |
|-------|--------|--------|--------|
| Earley | earley_item_t | 6 (4 IV, 2 SV*) | ~76M hv_fetch eliminated per 374-line parse |
| Earley | leo_item_t | 8 (5 IV, 3 SV*) | Leo optimization path |
| CoreItemIndex | core_info_t | 3 (1 SV*, 2 IV) | O(grammar_size) allocations |
| Precedence | prec_value_t | 5 (2 IV, 1 IV, 2 SV*) | Semiring cache entries |

TypeInference tag hashes are NOT promotable (dynamic keys). FilterComposite
values are already arrays. SemanticAction cfg_state has dynamic extra fields.

## Expected Performance Impact

For Structural.pm (374 lines):
- **Item creation**: 74K `_make_item` calls go from HV + 6 hv_store → newSV(48) + 6 field writes
- **Item access**: ~76M hv_fetch(key_string) → pointer dereference
- **Item copy**: 6 hash entry copies → memcpy(48 bytes)
- **IV fields**: 4 fields × 74K items = 296K fewer SV allocations

The 67% "unaccounted" overhead in profiling is largely Perl hash operations
in the inner loop. Struct promotion attacks this directly.
