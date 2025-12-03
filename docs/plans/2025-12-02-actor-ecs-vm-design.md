# Chalk VM Design: Actor-ECS Runtime with Staged Evolution

**Version:** 1.0
**Date:** 2025-12-02
**Status:** Design Phase

---

## Executive Summary

This document describes a three-stage evolution path for Chalk's runtime, progressing from a pragmatic actor-based scheduler to a research-grade Arrow-native VM. Each stage validates critical architectural decisions before adding complexity, with clear breaking points that indicate when to stop or pivot.

**Core Innovation:** Hybrid actor granularity with profile-guided optimization (PGO). The compiler ships pre-warmed with profiling data from self-compilation, eliminating cold-start overhead.

**Timeline:** 47-85 implementation sessions (4.7-8.5M tokens), parallelizable to 20-35 development rounds.

---

## Design Goals

1. **Production-ready performance** - Not just a reference implementation
2. **Full replacement** - Eventually replaces current `execute($context)` model
3. **Staged validation** - Each stage proves concepts before next layer
4. **Self-hosting optimization** - Profile from self-compilation ships with compiler
5. **Clear breaking points** - Know when to stop or pivot to alternative approach

---

## Four-Stage Evolution

### Stage 0: Perl→XS Compiler (Immediate Value)
**Validates:** Parsing, IR generation, type inference, code generation
**Effort:** 13-20 sessions (1.3-2.0M tokens)
**Deliverable:** Compile `feature class` to XS modules for CPAN

**Key insight:** Delivers standalone value before VM exists. Perl developers get performance without learning XS.

### Stage 1: Actor Scheduler (Foundation)
**Validates:** Actor model, message passing, continuations, basic block fusion
**Effort:** 15-25 sessions (1.5-2.5M tokens)
**Deliverable:** Working VM with comparable performance to current interpreter

### Stage 2: ECS + Persistence
**Validates:** Content addressing, death/rebirth, archetypes, event sourcing
**Effort:** 12-20 sessions (1.2-2.0M tokens)
**Deliverable:** Time-travel debugging, PGO foundation, checkpoint/replay

### Stage 3: Arrow-Native (Optional)
**Validates:** Zero-copy ecosystem integration, columnar performance
**Effort:** 20-40 sessions (2.0-4.0M tokens)
**Deliverable:** Jupyter integration, DuckDB queries, publishable architecture

**Decision point after Stage 2:** Only proceed to Stage 3 if lab integration or columnar performance is critical.

---

## Stage 0: Perl→XS Compiler Design

### Value Proposition

**"Modern Perl Performance Without Learning XS"**

Compile `feature class` definitions directly to XS modules. Developers write modern Perl, get C-speed performance, ship to CPAN—no XS knowledge required.

```perl
# Write this (pure Perl, feature class):
use feature 'class';

class Point {
    field $x :param :reader;
    field $y :param :reader;

    method distance_to($other) {
        my $dx = $x - $other->x;
        my $dy = $y - $other->y;
        return sqrt($dx * $dx + $dy * $dy);
    }
}

# Compile to XS:
$ chalk compile --target=xs lib/Point.pm
# Outputs: lib/Point.xs (XS implementation)

# Users get C-speed performance:
my $p1 = Point->new(x => 0, y => 0);
my $p2 = Point->new(x => 3, y => 4);
say $p1->distance_to($p2);  # Fast! XS-compiled
```

### Why Stage 0 Is Strategic

**Delivers value immediately:**
- ✅ Ships before VM exists
- ✅ Validates compilation pipeline (parse → IR → codegen)
- ✅ Proves type inference works
- ✅ Real Perl developers get real performance wins

**Backward compatible:**
- Code compiled with Stage 0 continues working through all later stages
- No breaking changes as Chalk evolves
- Investment in Stage 0 pays off forever

**Market fit:**
- Perl developers want modern syntax (`feature class`)
- Performance matters (but learning XS is hard)
- CPAN ecosystem needs faster modules

### Type Inference Strategy

**CRITICAL CONSTRAINT:** Chalk is a **pure subset of Perl**—no explicit type annotations.

**Type inference from context only:**

```perl
class Point {
    field $x :param;  # Type inferred from usage
    field $y :param;

    method distance_to($other) {
        # Infer: $x, $y are numeric (used in arithmetic)
        my $dx = $x - $other->x;
        my $dy = $y - $other->y;

        # Infer: sqrt returns numeric
        return sqrt($dx * $dx + $dy * $dy);
    }
}

# XS codegen sees:
# - $x, $y: numeric (used in -)
# - sqrt: numeric → numeric
# - Generates: NV (double) types in XS
```

**Inference rules:**

| Usage Pattern | Inferred Type |
|--------------|---------------|
| `$x + $y`, `$x - $y` | Numeric (NV) |
| `$x . $y` | String (SV*) |
| `$x < $y` | Numeric (NV) |
| `$x eq $y` | String (SV*) |
| `$x->method()` | Object (SV*) |
| `$x->[0]` | Array ref (AV*) |
| `$x->{key}` | Hash ref (HV*) |

**Conservative fallback:**
- If type can't be inferred → emit SV* (generic Perl scalar)
- Still works, just not as optimized
- User can refactor to make types clearer (without annotations!)

**Example of conservative fallback:**

```perl
class Ambiguous {
    field $value :param;

    method get { return $value }  # Type unknown
}

# XS emits:
SV* get(SV* self) {
    // Conservative: SV* (works for any Perl value)
    return SvRV(self)->value;
}
```

### What Stage 0 Compiles (MVP Scope)

**CRITICAL CONSTRAINT:** Stage 0 compiles **only Chalk-compatible code**.

Chalk currently supports:
- ✅ `feature class` definitions (the only functionally useful scope for XS compilation)
- ❌ Package scope (not in Chalk yet)
- ❌ Subroutines outside classes (no package scope)

**This means Stage 0 scope = `feature class` only:**

```perl
# ✅ Compilable (Chalk-compatible):
use feature 'class';

class Point {
    field $x :param :reader;      # Scalar fields
    field $y :param :reader;

    method distance_to($other) {  # Methods
        my $dx = $x - $other->x;  # Field access
        my $dy = $y - $other->y;
        return sqrt($dx * $dx + $dy * $dy);  # Built-in functions, arithmetic
    }

    method add($other) {
        return Point->new(
            x => $x + $other->x,
            y => $y + $other->y
        );
    }
}

class Container {
    field @items :param;              # Array fields (Chalk supports)
    field %lookup :param;             # Hash fields (Chalk supports)

    method add_item($item) {
        push @items, $item;
    }

    method find($key) {
        return $lookup{$key};
    }
}
```

**Not compilable (not in Chalk yet):**

```perl
# ❌ Package-scoped subs (Chalk doesn't support package scope)
package MyModule;
sub helper($x) { return $x * 2; }  # No package scope in Chalk

# ❌ CPAN module usage
use Some::CPAN::Module;

# ❌ Regex (Chalk restriction)
$str =~ s/foo/bar/g;
```

**Stage 0 is limited by Chalk's current feature set:**
- Only `feature class` definitions
- No package-scoped code
- This is actually fine—classes are the most useful target for XS optimization

**Future expansion:**
If/when Chalk adds package scope support, Stage 0 can compile package-scoped subs. But for now: **classes only**.

### Generated Output (CPAN-Ready Distribution)

```bash
# Input: lib/Point.pm (Chalk source)
$ chalk compile --target=xs lib/Point.pm

# Generates lib/Point.xs in same directory
# (Research needed: proper per-file XS format/location)
```

```perl

# 1. xs/Point.xs (XS implementation)
MODULE = Point  PACKAGE = Point

typedef struct {
    NV x;  // Inferred: numeric
    NV y;  // Inferred: numeric
} point_t;

SV*
new(const char* class, NV x, NV y)
CODE:
    point_t* point;
    Newx(point, 1, point_t);
    point->x = x;
    point->y = y;
    RETVAL = newRV_noinc((SV*)point);
OUTPUT:
    RETVAL

NV
distance_to(SV* self_sv, SV* other_sv)
CODE:
    point_t* self = (point_t*)SvRV(self_sv);
    point_t* other = (point_t*)SvRV(other_sv);
    NV dx = self->x - other->x;
    NV dy = self->y - other->y;
    RETVAL = sqrt(dx*dx + dy*dy);
OUTPUT:
    RETVAL

# 2. lib/Point.pm (loader stub)
package Point 0.01;
use XSLoader;
XSLoader::load(__PACKAGE__, our $VERSION);
1;

# 3. Makefile.PL (standard Perl build)
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME => 'Point',
    VERSION_FROM => 'lib/Point.pm',
);
```

**Distribution structure (example - actual layout TBD):**

```
Point/
├── lib/
│   ├── Point.pm           ← Chalk source
│   └── Point.xs           ← Generated XS (same directory?)
├── Makefile.PL            ← Standard Perl build
├── META.json              ← CPAN metadata
└── t/
    └── basic.t            ← Tests

# Note: Need to research proper XS file organization:
# - Same directory as .pm? (lib/Point.xs)
# - Separate xs/ directory? (xs/Point.xs)
# - Root level? (Point.xs)
# Will follow ExtUtils::MakeMaker conventions
```

### Compilation Pipeline

```
Chalk source (feature class)
    ↓ parse (existing Chalk parser)
Chalk AST
    ↓ semantic analysis
Sea of Nodes IR
    ↓ type inference (usage-based, no annotations)
Typed IR (knows $x:NV, $y:NV)
    ↓ XS code generator
XS source (.xs file)
    ↓ (user runs perl Makefile.PL && make)
Compiled .so (loadable by Perl)
```

**Key insight:** Uses the **same IR pipeline** as the full VM. Stage 0 just stops at XS codegen instead of continuing to actor runtime.

### Pure Perl Fallback

```perl
# Generated Point.pm includes fallback:
package Point 0.01;

BEGIN {
    eval {
        require XSLoader;
        XSLoader::load(__PACKAGE__, our $VERSION);
        1;
    } or do {
        # XS compilation failed, load pure Perl version
        # (Original class definition inlined here)
        eval q{
            use feature 'class';
            class Point {
                field $x :param :reader;
                field $y :param :reader;
                method distance_to($other) { ... }
            }
        };
    };
}
1;
```

**Result:** Works everywhere—XS if available, pure Perl if not.

### Stage 0 Implementation Effort

| Component | Sessions | Tokens | Complexity |
|-----------|----------|--------|------------|
| Perl Parser (class syntax) | 2-3 | 200-300K | Medium (reuse existing) |
| Type Inference Engine | 3-4 | 300-400K | Medium-High |
| XS Code Generator | 4-5 | 400-500K | High |
| Calling Convention | 2-3 | 200-300K | Medium |
| Makefile.PL Generator | 1 | 50-100K | Simple |
| Testing Framework | 2-3 | 200-300K | Medium |
| Documentation | 1-2 | 100-200K | Simple |
| **Total** | **15-21** | **1.5-2.1M** | |

**Timeline:** 2-3 months focused work

**Dependencies:** Chalk parser (already exists), Sea of Nodes IR (already exists)

### Stage 0 Validation Criteria

**Success:**
- ✅ Compiles simple `feature class` to working XS
- ✅ Type inference works for numeric/string operations
- ✅ Generated module loadable via `use Module`
- ✅ Performance: 5-10x faster than pure Perl
- ✅ CPAN uploadable (standard distribution format)

**Breaking points (pivot if):**
- ❌ Type inference < 70% accurate
- ❌ Generated XS doesn't compile
- ❌ Performance gain < 2x (not worth complexity)
- ❌ Can't generate standard CPAN distribution

---

## Stage 1: Actor Scheduler Design

### Architecture Overview

Keep existing `Chalk::IR::Node::*` classes, add actor scheduling layer on top:

```perl
class Chalk::Runtime::Scheduler {
    field $ecs :param;          # ECS World for state management
    field @ready_queue;         # Actors ready to execute
    field %node_states;         # node_id => execution state

    method tick {
        # Query ECS for ready actors
        my @ready = $ecs->query(has => ['ReadyState']);

        for my $actor (@ready) {
            my $result = $actor->execute();
            $self->handle_result($actor, $result);
            $self->propagate_to_downstream($actor);
        }
    }
}
```

**Key insight:** Scheduler mediates access to results via message passing, making dataflow dependencies explicit.

### Hybrid Actor Granularity

**Critical design decision:** Actor granularity determined by compilation tier, not hardcoded.

```
Tier 0 (Baseline): Basic block actors
  - Natural boundary = Sea of Nodes control flow (Region/Loop/If/Phi)
  - Straight-line code between control flow fused into FusedBlockActor
  - This is the "normal" execution mode
  - Still allows instrumentation, debugging

Tier 1 (Optimized): Profile-guided fusion
  - Guided by persistent profile from self-compilation
  - Hot blocks get additional optimization (inlining, specialization)
  - May fuse across some control flow boundaries if safe

Tier 2 (Future JIT): Specialized compiled code
  - Monomorphic inline caching
  - Native code generation
  - Per-type specialization

Debug Mode (Optional): Per-node actors
  - Every IR node is separate actor
  - Maximum granularity for debugging
  - Only when explicitly requested (--debug-mode)
```

### Basic Block Fusion

**Leverages Sea of Nodes CFG structure:** Chalk already has Region/Loop/If nodes that define control flow boundaries. Fusion respects this existing structure.

**AoT pass partitions IR into fusion candidates:**

```perl
class Chalk::AOT::FusionPass {
    # Basic blocks in Sea of Nodes are naturally delimited by:
    # - Region nodes (control flow merge points)
    # - Loop nodes (iteration boundaries)
    # - If nodes (conditional branches)
    # - Phi nodes (SSA value merges)

    method partition_by_cfg_regions($ir_graph) {
        my @blocks;

        # Each Region defines a basic block boundary
        for my $region ($ir_graph->all_regions) {
            # Find all nodes dominated by this region
            # until next control flow node
            my @nodes = $self->collect_dominated_nodes($region);

            # Further subdivide if escape analysis shows value crossing boundary
            my @sub_blocks = $self->split_on_escapes(@nodes);

            push @blocks, @sub_blocks;
        }

        return @blocks;
    }

    method collect_dominated_nodes($region) {
        my @nodes;
        my $current = $region;

        # Walk dataflow edges until hitting:
        # - Another Region/Loop/If (control flow)
        # - Phi node (merge point)
        # - Node with escaping value
        while ($current && !$current->is_control_flow) {
            push @nodes, $current;
            $current = $self->next_in_dataflow($current);
        }

        return @nodes;
    }
}
```

**Relationship to Sea of Nodes CFG:**

| Sea of Nodes Concept | Fusion Behavior |
|---------------------|-----------------|
| **Region node** | Basic block boundary (merge point) |
| **Loop node** | Basic block boundary (iteration) |
| **If node** | Basic block boundary (branch) |
| **Phi node** | Basic block boundary (SSA merge) |
| **Straight-line dataflow** | Fused into single FusedBlockActor |

**Example with existing Loop structure:**

```perl
# From chapter07: while ($i < 10) { $i = $i + 1; }

# Sea of Nodes IR (already has CFG):
Loop (Region boundary)
  ├─ Phi_i (SSA merge - block boundary)
  ├─ Less (straight-line computation)
  ├─ If (control flow - block boundary)
  │   ├─ IfTrue
  │   │   └─ Add (straight-line - fusable!)
  │   └─ IfFalse
  └─ Region (exit - block boundary)

# After fusion:
Loop (stays separate - control flow)
  ├─ Phi_i (stays separate - SSA merge)
  ├─ FusedBlock_1([Less])  ← fused
  ├─ If (stays separate - control flow)
  │   ├─ IfTrue
  │   │   └─ FusedBlock_2([Add])  ← fused
  │   └─ IfFalse
  └─ Region (stays separate - control flow)
```

**FusedBlockActor executes multiple nodes atomically:**

```perl
class Chalk::Runtime::FusedBlockActor {
    field @nodes :param;        # Nodes in this block
    field @inputs :param;       # Block inputs (from other actors)
    field @outputs :param;      # Block outputs (to other actors)

    method execute {
        my %locals;  # Block-local values (never escape)

        for my $node (@nodes) {
            my $result = $node->execute(sub ($key) {
                $locals{$key} // $self->get_input($key)
            });

            if ($self->is_output($node)) {
                $self->send_message($result);
            } else {
                $locals{"node:" . $node->id} = $result;
            }
        }
    }
}
```

**Benefits:**
- Block-local values never spawn ValueActors (no allocation)
- Fused nodes execute with no scheduling overhead between them
- Actor-granular at block boundaries (enables region-level parallelism)

### Profile-Guided Optimization (PGO)

**Killer feature:** Compiler ships pre-warmed with profiling data from self-compilation.

```perl
# During Chalk's CI/build:
sub generate_release_profile {
    my $compiler = Chalk::Compiler->new(
        tier => 0,  # Fully instrumented
        profile => Chalk::Profile::Database->new(db => "chalk-compiler.profile.db")
    );

    # Compile Chalk with itself (self-hosting)
    $compiler->compile(read_file("chalk"));

    # Profile DB now contains hot paths from:
    # - Parser execution
    # - Semantic analysis
    # - Optimization passes

    # Ship this with the release!
    install_file("chalk-compiler.profile.db", "$PREFIX/share/chalk/");
}
```

**Production mode loads persistent profile:**

```perl
class Chalk::Runtime::Prod {
    method new {
        my $profile_path = find_installed_profile();
        my $profile = Chalk::Profile::Database->new(db => $profile_path);

        return $self->SUPER::new(
            tier => 1,               # AoT fused blocks
            profile => $profile,
            instrumentation => 'minimal',  # Only new code paths
        );
    }
}
```

**Content-addressed blocks enable profile portability:**

```perl
method block_hash(@nodes) {
    my $content = join(":",
        map { $_->op . ":" . join(",", $_->inputs->@*) } @nodes
    );
    return sha256_hex($content);
}

# Same IR structure → same hash → same optimization applies
# Portable across machines, OS, Perl versions
```

**Result:** Users get an optimized compiler from day 1, no cold-start penalty.

### Message Passing & Dataflow

**Two message delivery modes** (escape analysis determines):

```perl
class Chalk::Runtime::Message {
    field $from :param;      # Sender actor ID
    field $to :param;        # Recipient actor ID
    field $port :param;      # Which input (0=left, 1=right)
    field $payload :param;   # Direct value OR actor ID reference
}
```

| Value Type | Delivery | Example |
|------------|----------|---------|
| **Non-escaping** | Direct payload | `$x = 1 + 2` → message contains `3` |
| **Escaping** | Actor reference | `return $x` → message contains `ValueActor_42` ID |

**FusedBlockActor internal messages are eliminated:**

```perl
# Instead of:
AddActor → sends message → MultiplyActor

# Fused version:
FusedBlockActor {
    local $x = $a + $b;    # No message
    local $y = $x * 2;     # No message
    send(to: continuation, payload: $y);  # Only output sends
}
```

### State Management (ECS Components)

```perl
# Component: ReadyState
class Chalk::ECS::Component::ReadyState {
    field $timestamp :param;  # For scheduling fairness (FIFO)
}

# Component: WaitingState
class Chalk::ECS::Component::WaitingState {
    field %inputs_received;   # port => value
    field %inputs_needed;     # port => true

    method all_ready { keys(%inputs_needed) == 0 }
}

# Component: CompletedState
class Chalk::ECS::Component::CompletedState {
    field $result :param;
    field $completion_time :param;
}
```

**Scheduler queries ECS:**

```perl
# Find all ready actors
my @ready = $ecs->query(
    has => ['ReadyState'],
    order_by => 'timestamp'
);
```

### Continuation Model

**Every computation has two continuations:**

```perl
class Chalk::Runtime::ContinuationActor {
    field $return_continuation :param;      # Normal flow
    field $exception_continuation :param;   # Error handling (eval/die)
    field @inputs_to_mark_free :param;      # Consumed values
}
```

**Normal flow:**

```
ComputeActor completes
  ↓ sends result to return continuation
ReturnContinuationActor
  ↓ marks consumed values free
  ↓ triggers next computation
NextComputeActor
```

**Exception flow:**

```
ComputeActor encounters error
  ↓ sends error to exception continuation
ExceptionContinuationActor
  ↓ either handles (eval block) or propagates to parent
```

**Scope-based memory management:**

```perl
class Chalk::Runtime::ScopeActor {
    field @owned_values;        # ValueActors in this scope
    field $return_continuation;
    field $exception_continuation;

    method on_scope_exit {
        for my $value (@owned_values) {
            $value->mark_free() unless $value->escaped;
        }
        send(to: $return_continuation);
    }
}
```

### Control Flow Actors

**RegionActor** - synchronizes control flow merge:

```perl
class Chalk::Runtime::RegionActor {
    field @expected_inputs :param;
    field @received = [];

    method receive_control($from_branch) {
        push @received, $from_branch;

        # If-merge: wait for 1
        # Loop-header: wait for entry OR backedge
        if (@received >= @expected_inputs) {
            send(to: $continuation, control_from => @received);
        }
    }
}
```

**PhiActor** - selects value based on control path:

```perl
class Chalk::Runtime::PhiActor {
    field %branch_to_value :param;
    field $control_region :param;

    method execute {
        my $active_branch = $control_region->received->[-1];
        my $value = $branch_to_value{$active_branch};
        send(to: continuation, payload: $value);
    }
}
```

### Stage 1 Implementation Effort

| Component | Sessions | Tokens | Complexity |
|-----------|----------|--------|------------|
| ECS Core | 3-5 | 300-500K | Medium |
| Message Passing | 2-3 | 200-300K | Medium |
| Actor Base Classes | 4-6 | 400-600K | Medium-High |
| Scheduler | 2-3 | 200-300K | Medium |
| Basic Block Fusion | 3-5 | 300-500K | High |
| Testing | 1-3 | 100-300K | Variable |
| **Total** | **15-25** | **1.5-2.5M** | |

**Parallelization:** ECS, Message Passing, Actors, Fusion can be developed concurrently (3-4 parallel tracks).

**Critical path:** ECS → Actors → Scheduler (serial: 6-10 sessions)

---

## Stage 2: ECS + Persistence Design

### Content-Addressed Actors

**Actor identity derives from content hash:**

```perl
class Chalk::Runtime::ContentIntern {
    field %hash_to_slot;     # content_hash => slot_id
    field @slot_to_hash;     # slot_id => content_hash
    field @slot_to_actor;    # slot_id => actor object
    field @free_slots;       # Reusable slot IDs

    method intern($actor) {
        my $hash = $self->content_hash($actor);

        # Already exists? Return cached slot (memoization!)
        return $hash_to_slot{$hash} if exists $hash_to_slot{$hash};

        # Allocate new slot (reuse freed slot if available)
        my $slot = shift(@free_slots) // scalar(@slot_to_hash);

        $hash_to_slot{$hash} = $slot;
        $slot_to_hash[$slot] = $hash;
        $slot_to_actor[$slot] = $actor;

        return $slot;
    }
}
```

**Memoization emerges naturally:**

```perl
# Code: $a = $x + 1; $b = $x + 1;

# First: AddActor(inputs: [$x, 1]) → hash="Add:$x,1" → executes → slot 100
# Second: AddActor(inputs: [$x, 1]) → hash="Add:$x,1" → cached! → slot 100

# Automatic memoization via content addressing
```

**Benefits:**
- Deterministic IDs (same inputs → same hash)
- Automatic memoization (no explicit cache)
- Historical identity (hash survives across runs)
- Profile portability (hash-based, not address-based)

### Death/Rebirth Execution Model

**Actors execute once, then die:**

```perl
class Chalk::Runtime::Actor {
    method execute {
        my $result = $self->do_computation();

        # Spawn continuation with result
        my $continuation = $self->spawn_continuation($result);

        # Die (slot becomes reusable)
        $self->mark_completed();

        return $continuation;
    }
}
```

**Execution trace becomes event log:**

```
Actor_1 (Add) spawns, executes, dies
  ├─ spawns: Actor_2 (Value: 5)
  ├─ spawns: Actor_3 (Continuation)
  └─ slot 1 → free list

Actor_3 (Continuation) spawns, executes, dies
  ├─ marks: Actor_2 free
  ├─ spawns: Actor_4 (next computation)
  └─ slot 3 → free list
```

**Why death/rebirth?**
- Immutability enforcement
- Event sourcing (history = spawn/die events)
- CPS natural fit
- Time-travel debugging (replay spawn sequence)

### ECS Archetypes

**Group actors by shape for cache locality:**

```perl
class Chalk::ECS::Archetype {
    field $signature :param;    # [ComputeActor, BinaryOp]
    field @entities;            # Slot IDs
    field %components;          # component_name => [values...]
    field @free_slots;

    method query($filter) {
        my @results;
        for my $i (0 .. $#entities) {
            next unless defined $entities[$i];
            if ($self->matches_filter($i, $filter)) {
                push @results, $entities[$i];
            }
        }
        return @results;
    }
}
```

**Archetype examples:**

| Signature | Contains | Components |
|-----------|----------|------------|
| `[ComputeActor, BinaryOp]` | Add, Multiply, Divide | `left`, `right`, `op` |
| `[ValueActor, Int]` | Integers | `value`, `escaped` |
| `[FusedBlockActor]` | Fused blocks | `nodes`, `inputs`, `outputs` |
| `[ContinuationActor]` | Continuations | `next_actor`, `free_list` |

**Region-local archetypes** (better cache locality):

```perl
# Instead of global archetypes, organize by Region
LoopRegion_42 => {
    archetypes => {
        'ComputeActor:BinaryOp' => [...],  # Only this loop's ops
        'ValueActor:Int' => [...],          # Only this loop's values
    },
    local_free_list => [...],
}
```

### SQLite Persistence

**Schema:**

```sql
-- Current state
CREATE TABLE actors (
    slot_id INTEGER PRIMARY KEY,
    content_hash TEXT NOT NULL,
    archetype TEXT NOT NULL,
    state TEXT,
    actor_data BLOB  -- Sereal-encoded
);

-- Event sourcing (execution history)
CREATE TABLE actor_events (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp REAL,
    event_type TEXT,  -- 'spawn', 'execute', 'die'
    slot_id INTEGER,
    content_hash TEXT,
    parent_slot INTEGER,
    result BLOB
);

-- Profile data (PGO)
CREATE TABLE block_profiles (
    block_hash TEXT PRIMARY KEY,
    exec_count INTEGER DEFAULT 0,
    total_time_us INTEGER DEFAULT 0,
    escape_info TEXT  -- JSON
);
```

**Write-behind checkpointing:**

```perl
class Chalk::Runtime::Persistence {
    field $db :param;
    field @pending_events;

    method record_event($event) {
        push @pending_events, $event;

        # Flush every 1000 events or every 1 second
        if (@pending_events >= 1000 || time() - $last_flush > 1.0) {
            $self->flush_events();
        }
    }
}
```

**Time-travel debugging:**

```perl
# Replay to specific event
method replay_to_event($target_event_id) {
    my $events = $db->selectall_arrayref(q{
        SELECT * FROM actor_events
        WHERE event_id <= ?
        ORDER BY event_id
    }, {Slice => {}}, $target_event_id);

    my $runtime = Chalk::Runtime->new(replay_mode => 1);
    for my $event (@$events) {
        $runtime->replay_event($event);
    }
    return $runtime;
}

# Binary search for behavior change
method bisect_behavior($test_fn, $start, $end) {
    # Standard binary search over event IDs
    # Find first event where $test_fn changes result
}
```

### Stage 2 Implementation Effort

| Component | Sessions | Tokens | Complexity |
|-----------|----------|--------|------------|
| Content Addressing | 2-3 | 200-300K | Medium |
| Death/Rebirth | 2-3 | 200-300K | Medium |
| Archetype Refinement | 2-4 | 200-400K | Medium-High |
| SQLite Persistence | 3-5 | 300-500K | Medium |
| Profiling Infrastructure | 2-3 | 200-300K | Medium |
| Time-Travel Debugging | 1-2 | 100-200K | Medium |
| **Total** | **12-20** | **1.2-2.0M** | |

**Parallelization:** Content addressing, persistence, profiling = 3 parallel tracks

**Critical path:** Stage 1 → Content addressing → Persistence (serial: 5-8 sessions)

---

## Stage 3: Arrow-Native Design (Optional)

### Decision Criteria

**Proceed to Stage 3 if ANY of:**

1. **Performance:** Columnar data layout improves cache behavior for archetype iteration
2. **Lab integration:** Jupyter/Pandas zero-copy interop is critical
3. **Research publication:** Novel architecture needs demonstration
4. **Serialization bottleneck:** Stage 2's Sereal overhead > 20% of runtime

**Arrow provides two distinct benefits:**

| Benefit | What It Enables | When It Matters |
|---------|----------------|-----------------|
| **Columnar layout** | Cache-friendly archetype iteration, SIMD | Hot loops, bulk operations |
| **Ecosystem interop** | Zero-copy to Jupyter/Pandas/DuckDB | Lab workflows, analysis |

**Note:** Columnar performance and ecosystem integration are **separate wins**. You might want Arrow for performance even without lab integration (or vice versa).

### Columnar Layout Performance

**Why columnar matters for ECS archetypes:**

Traditional row-oriented storage (Perl hashes/arrays):
```perl
# Each actor is a hashref (row-oriented)
@actors = (
    { id => 1, op => 'Add', left => 10, right => 20, state => 'ready' },
    { id => 2, op => 'Add', left => 30, right => 40, state => 'ready' },
    { id => 3, op => 'Mul', left => 50, right => 60, state => 'waiting' },
);

# Query "all ready Add actors":
for my $actor (@actors) {
    next unless $actor->{state} eq 'ready';  # Touch all memory!
    next unless $actor->{op} eq 'Add';       # Touch all memory!
    execute($actor);
}
```

**Problem:** Accessing `state` and `op` requires loading the **entire hashref** into cache (including unused fields like `left`, `right`).

Arrow columnar storage:
```perl
# Columns stored separately (columnar)
Archetype 'Add' => {
    id:    [1, 2, 4, 5, ...],           # Column 1
    left:  [10, 30, 70, 90, ...],       # Column 2
    right: [20, 40, 80, 100, ...],      # Column 3
    state: ['ready', 'ready', 'waiting', 'ready', ...], # Column 4
}

# Query "all ready Add actors":
# Only touch state column + id column
for my $i (0..$#{$archetype->{state}}) {
    next unless $archetype->{state}[$i] eq 'ready';
    my $id = $archetype->{id}[$i];
    execute_add($id);
}
```

**Win:** Query only loads `state` column into cache. Rest of columns untouched until execution.

**Cache efficiency example:**

| Layout | Memory Touched | Cache Lines | SIMD Possible |
|--------|---------------|-------------|---------------|
| **Row (hashref)** | All 5 fields × 1000 actors = 5000 fields | ~625 lines | No |
| **Columnar (Arrow)** | 1 field × 1000 actors = 1000 values | ~16 lines | Yes |

**Speedup:** 40x fewer cache lines loaded for queries.

**SIMD vectorization:**

```c
// Arrow's contiguous layout enables SIMD
// Check 8 states at once:
__m256i states = _mm256_load_si256(archetype->state + i);
__m256i ready_mask = _mm256_cmpeq_epi32(states, READY_CONST);
// Process 8 actors in one instruction
```

**When columnar wins big:**

1. **Archetype queries** - "Find all ready actors" (only touch state column)
2. **Bulk operations** - "Mark all completed actors free" (SIMD over columns)
3. **Profile analysis** - "Sum execution counts" (aggregate single column)
4. **Hot loops** - Same actors iterated repeatedly (column stays in L1 cache)

**When columnar doesn't help:**

1. **Random access** - "Get specific actor by ID" (row-oriented is fine)
2. **Small archetypes** - < 100 actors (overhead not worth it)
3. **Sparse queries** - Most actors filtered out (wasted column scan)

### Arrow as Unified Format

**Radical idea:** Compile-time IR and runtime ECS use same Arrow tables.

```
Parser
  ↓
Arrow Table "IR_Nodes" (columnar)
  ├─ Column: op (enum)
  ├─ Column: left_input (uint64 refs)
  ├─ Column: right_input (uint64 refs)
  ↓
Optimization passes (work on Arrow directly)
  ↓
Runtime (same tables + execution state columns)
  ├─ Column: state (Ready/Waiting/Completed)
  ├─ Column: result (variant type)
```

**No serialization boundary.** The IR format IS the runtime format.

### Zero-Copy Ecosystem Integration

```python
# From Jupyter notebook:
import pyarrow as pa
import polars as pl

# Connect to Chalk runtime
chalk = pa.flight.connect("localhost:8815")

# Query Chalk's IR (zero-copy!)
ir_table = chalk.do_get("IR_NODES").read_all()

# Analyze with Polars
df = pl.from_arrow(ir_table)
hot_nodes = df.filter(pl.col("exec_count") > 1000)
print(hot_nodes)
```

**Benefits:**
- Researchers push data from Jupyter → Chalk (zero-copy)
- Chalk results pull back to Pandas (zero-copy)
- DuckDB SQL over Chalk state (zero-copy)

### DuckDB Persistence

**Replace SQLite with DuckDB:**

```perl
class Chalk::Runtime::Persistence::DuckDB {
    method persist_ir($arrow_table) {
        $db->register('ir_nodes', $arrow_table);

        # Persist to Parquet (columnar on-disk)
        $db->execute(q{
            COPY ir_nodes TO 'chalk-ir.parquet' (FORMAT PARQUET)
        });
    }

    method load_ir() {
        return $db->execute(q{
            SELECT * FROM read_parquet('chalk-ir.parquet')
        })->fetch_arrow_table();
    }
}
```

**DuckDB advantages:**
- Native Arrow (zero-copy)
- Columnar storage (Parquet)
- Advanced query optimizer
- Built for analytics (OLAP)

### Implementation Path Options

**Option 1: Wrap libarrow-glib (GObject bindings)**

```perl
use Glib::Object::Introspection;

Glib::Object::Introspection->setup(
    basename => 'Arrow',
    version => '1.0',
    package => 'Arrow',
);
```

**Pros:** No C needed, leverages GLib
**Cons:** GLib dependency, may not expose all features

**Option 2: Write XS bindings**

```xs
MODULE = Chalk::Arrow::Table
SV* new(...)
    // Wrap libarrow C++ API
```

**Pros:** Full control, optimal performance
**Cons:** C++ expertise, maintenance burden

**Option 3: Arrow Flight IPC only**

```perl
# Don't use Arrow internally, just for external queries
# Convert SQLite data to Arrow on demand
```

**Pros:** Minimal Arrow commitment
**Cons:** Conversion overhead, not zero-copy internally

### Stage 3 Implementation Effort

| Component | Sessions | Tokens | Complexity |
|-----------|----------|--------|------------|
| Arrow Bindings | 10-20 | 1-2M | Very High |
| Arrow Schema Gen | 2-3 | 200-300K | Medium |
| IR→Arrow Conversion | 3-5 | 300-500K | Medium-High |
| DuckDB Integration | 2-3 | 200-300K | Medium |
| Arrow Flight Server | 2-4 | 200-400K | Medium-High |
| Testing | 2-5 | 200-500K | Variable |
| **Total** | **20-40** | **2.0-4.0M** | |

**Wild card:** Arrow bindings could be 10 sessions or 30+ sessions

**Critical path:** Bindings are mostly serial (10-20 sessions)

### How Arrow Columnar Layout Helps AoT Compilation

**Columnar IR enables efficient whole-program analysis:**

```perl
# Arrow IR as columns (Stage 3):
IR_Table = {
    node_id:   [1, 2, 3, 4, ...],
    op:        ['Add', 'Add', 'Mul', 'Add', ...],
    left_id:   [10, 20, 30, 40, ...],
    right_id:  [11, 21, 31, 41, ...],
    type:      ['Int', 'Int', 'Float', 'Int', ...],
}

# AoT compiler queries for specialization opportunities:
SELECT node_id FROM IR_Table
WHERE op = 'Add' AND type = 'Int'
GROUP BY op, type
HAVING COUNT(*) > 100;  -- Hot monomorphic sites

# Result: Specialize these to native add_int_int() function
```

**Analysis speed comparison:**

| Analysis | Row-Oriented (Stage 2) | Columnar Arrow (Stage 3) |
|----------|----------------------|-------------------------|
| Find all Add nodes | O(N) scan all nodes | Query op column only (~40x faster) |
| Count ops by type | Touch all fields | Touch op + type columns (~20x faster) |
| Find monomorphic sites | Iterate + hash | DuckDB optimized query |
| Type frequency analysis | Manual aggregation | SQL GROUP BY (vectorized) |

**SIMD-accelerated AoT analysis:**

```c
// Count operations by type (for specialization decisions)
// Only possible with columnar layout

int count_operation_types(ArrowArray* ops, ArrowArray* types) {
    int counts[NUM_OPS][NUM_TYPES] = {0};

    // Vectorized: process 8 nodes at once
    for (int i = 0; i < ops->length; i += 8) {
        __m256i op_chunk = _mm256_load_si256(&ops->data[i]);
        __m256i type_chunk = _mm256_load_si256(&types->data[i]);
        // ... SIMD counting logic ...
    }

    return counts;
}
```

**Whole-program optimization via SQL:**

```sql
-- Find fusion opportunities across entire program
WITH consecutive_ops AS (
    SELECT
        a.node_id as first_id,
        b.node_id as second_id,
        a.op || '_' || b.op as fusion_pattern
    FROM IR_Table a
    JOIN IR_Table b ON b.left_id = a.node_id
    WHERE NOT EXISTS (
        -- No control flow between nodes
        SELECT 1 FROM IR_Table c
        WHERE c.node_id BETWEEN a.node_id AND b.node_id
          AND c.op IN ('If', 'Loop', 'Region', 'Phi')
    )
)
SELECT fusion_pattern, COUNT(*) as frequency
FROM consecutive_ops
GROUP BY fusion_pattern
ORDER BY frequency DESC
LIMIT 20;

-- Output: Top fusion patterns to emit as specialized functions
-- Example: Add_Multiply appears 5000 times → emit fused_add_mul()
```

**Benefits for AoT:**
- ✅ Fast pattern matching (DuckDB query optimizer)
- ✅ Data-driven optimization decisions (query hot paths)
- ✅ Whole-program visibility (SQL joins across entire IR)
- ✅ SIMD code generation (vectorized analysis)

---

## Stage 4: Full AoT Compilation (Future)

Building on Stages 1-3, full ahead-of-time (AoT) compilation to native code becomes straightforward.

### What Full AoT Means

Instead of shipping IR and executing via runtime, compile the entire program to native code:

```bash
# Staged execution (Stages 1-3):
chalk compile program.pl → program.ir     # IR (Arrow/SQLite)
chalk run program.ir                       # Runtime executes actors

# Full AoT (Stage 4):
chalk compile --aot program.pl → program   # Native binary
./program                                   # Direct execution
```

### Why This Architecture Enables AoT

**1. Actor graph IS the execution plan**

FusedBlockActors + message routing already define execution order. AoT just emits:
- Each FusedBlockActor → native function
- Message passing → direct function calls (when static)
- Dynamic dispatch only where necessary

**2. Content addressing enables monomorphization**

```perl
# Profile shows:
AddActor(hash="Add:Int,Int") → 5000 calls, always Int

# AoT emits specialized function:
int64_t add_int_int(int64_t left, int64_t right) {
    return left + right;  // No type checks, no dispatch
}
```

**3. Profile guides specialization**

Persistent profile tells AoT compiler:
- Which types flow through actors (hot paths)
- Which branches always/never taken (speculation)
- Which values escape (stack vs heap)

**4. Escape analysis enables stack allocation**

```perl
# Source:
sub compute($x) {
    my $temp = $x + 1;  # Doesn't escape
    return $temp;
}

# AoT compiled:
int64_t compute(int64_t x) {
    int64_t temp = x + 1;  // Stack, no allocation
    return temp;
}
```

### AoT Compilation Tiers

| Tier | Output | Runtime Needed | Performance Gain |
|------|--------|---------------|------------------|
| **Tier 0-2** | IR + actors | Full runtime | Baseline (1x) |
| **Tier 3** | Arrow IR | Arrow runtime | 2-5x (columnar) |
| **Tier 4a** | C code + runtime | Minimal runtime | 10-20x |
| **Tier 4b** | Native only | No runtime | 20-50x |

**Tier 4a: Hybrid AoT (pragmatic first step)**

```c
// Generated C code
void fused_block_42(Context* ctx) {
    int64_t x = ctx_get_value(ctx, VAR_X);
    int64_t y = x + 1;
    ctx_send_message(ctx, NEXT_BLOCK, y);
}

// Uses lightweight runtime for:
// - Dynamic dispatch (method calls)
// - Heap allocation (escaping values)
// - Exception handling
```

**Tier 4b: Full Static (research/embedded)**

```c
// All control flow compiled away
int main(int argc, char** argv) {
    int64_t x = 0;
    while (x < 10) {
        x = x + 1;
    }
    return x;
}

// No runtime - fully static binary
```

### Backend Options (Following Chalk's Existing Plan)

Chalk already has a clear backend progression: **Perl → XS → WASM → LLVM**

**Backend 1: XS (Performance + FFI - Stage 1-2)**
- Hot runtime functions in XS (C bindings for Perl)
  - Archetype queries, message routing, slot allocation
  - Hash computation, content interning
- FFI primitives for C interop
  - FFI::Platypus-style declarative interface
  - Pure Perl can declare foreign functions
  - Establishes calling conventions, type mappings
  - Later: WASM/LLVM backends reuse FFI semantics
- Already part of Chalk's ecosystem
- **Effort:** Incremental, part of Stage 1-2 implementation

**Why XS is strategic:**
- Performance: C-speed hot paths in the runtime
- FFI validation: Proves out foreign function calling conventions
- Pure Perl participation: FFI works from interpreted code too
- Learning: XS/Platypus experience informs WASM/LLVM FFI design

**FFI design example (FFI::Platypus-style):**

```perl
# Stage 1-2: Establish FFI patterns
use Chalk::FFI;

# Declare foreign function
my $ffi = Chalk::FFI->new(lib => 'c');
$ffi->attach(strlen => ['string'] => 'size_t');

# Now callable from Chalk:
my $len = strlen("hello");  # Calls libc strlen

# Stage 4a: WASM reuses same semantics
# WASM import generated from same declaration:
# (import "env" "strlen" (func $strlen (param i32) (result i32)))

# Stage 4b: LLVM reuses same semantics
# LLVM IR generated from same declaration:
# declare i64 @strlen(i8*)
```

**Key insight:** FFI interface designed at Perl level works across all backends. Pure Perl, XS, WASM, and LLVM all see the same foreign function API.

**Backend 2: WASM (Portable, Sandboxed - Stage 4a)**
- Compile FusedBlockActors to WebAssembly
- Run in browser or WASI runtime
- Sandboxed, portable across platforms
- **Effort:** 10-15 sessions

**Backend 3: LLVM IR (Maximum Optimization - Stage 4b)**
- Emit LLVM bitcode from actor graph
- Access to full LLVM optimization pipeline
- Multiple target architectures (x86_64, ARM, etc.)
- Industry-standard code generation
- **Effort:** 15-20 sessions

**Why Skip C Code Generation:**
- XS already provides C interop where needed (runtime hot paths)
- WASM is better for portable bytecode target
- LLVM is better for native compilation with full optimization
- C backend would be redundant middle ground

### Self-Hosting AoT Bootstrap

**Perfect synergy with profile-guided optimization:**

1. Chalk compiles itself (Tier 1) → generates profile
2. Profile shows hot paths + type information
3. AoT compiler (Tier 4) uses profile to specialize
4. **Chalk ships as native-compiled binary**
5. Users get production-ready Perl compiler from day 1

**Result:** Native-speed Perl compiler with zero cold-start overhead.

### Stage 4 Implementation Effort

Following the **Perl → XS → WASM → LLVM** progression:

| Component | Sessions | Tokens | Complexity |
|-----------|----------|--------|------------|
| **WASM Backend (Stage 4a)** | | | |
| WASM Module Generator | 3-4 | 300-400K | Medium-High |
| FusedBlock → WASM Translation | 2-3 | 200-300K | Medium |
| Runtime Bindings (WASI) | 2-3 | 200-300K | Medium |
| Testing & Validation | 2-3 | 200-300K | Variable |
| **WASM Subtotal** | **9-13** | **900K-1.3M** | |
| | | | |
| **LLVM Backend (Stage 4b)** | | | |
| LLVM IR Generator | 4-5 | 400-500K | High |
| Static Analysis Pass | 2-3 | 200-300K | Medium |
| Runtime Interface | 2-3 | 200-300K | Medium |
| Optimization Pipeline | 2-3 | 200-300K | Medium-High |
| Linker Integration | 1-2 | 100-200K | Medium |
| Testing & Validation | 2-3 | 200-300K | Variable |
| **LLVM Subtotal** | **13-19** | **1.3-2.0M** | |

**Dependencies:** Requires Stage 1-2 complete. Stage 3 (Arrow) optional but helps with whole-program analysis.

**XS integration:** Happens incrementally during Stage 1-2 for runtime hot paths (not a separate AoT backend).

### Example: Loop AoT Compilation

```perl
# Source:
my $sum = 0;
for my $i (1..10) {
    $sum += $i;
}
return $sum;

# Stage 1 (actors):
LoopActor → PhiActor($i) → PhiActor($sum) → AddActor

# Stage 2 (fused):
FusedBlockActor([LoopBody: Add, Increment])

# Stage 3 (profiled):
Profile: always Int, always 10 iterations

# Stage 4a (AoT WASM):
(module
  (func $compute (result i64)
    (local $sum i64)
    (local $i i64)
    (local.set $sum (i64.const 0))
    (local.set $i (i64.const 1))
    (block $exit
      (loop $loop
        (br_if $exit (i64.gt_s (local.get $i) (i64.const 10)))
        (local.set $sum (i64.add (local.get $sum) (local.get $i)))
        (local.set $i (i64.add (local.get $i) (i64.const 1)))
        (br $loop)
      )
    )
    (local.get $sum)
  )
)

# Stage 4b (AoT LLVM IR):
define i64 @compute() {
entry:
  br label %loop
loop:
  %i = phi i64 [ 1, %entry ], [ %i.next, %loop ]
  %sum = phi i64 [ 0, %entry ], [ %sum.next, %loop ]
  %sum.next = add i64 %sum, %i
  %i.next = add i64 %i, 1
  %cond = icmp sle i64 %i.next, 10
  br i1 %cond, label %loop, label %exit
exit:
  ret i64 %sum.next
}

# Fully specialized, LLVM optimizes further
```

### What You Get With AoT

**Performance:**
- 10-50x faster than interpreter
- Comparable to hand-written C
- Zero startup overhead

**Deployment:**
- Single static binary
- No runtime dependency
- Embedded systems ready

**Optimization:**
- Whole-program inlining
- Dead code elimination
- SIMD vectorization (LLVM)
- Aggressive specialization

---

## Validation & Breaking Points

### Stage 1 Validation

**Success criteria:**
- ✅ Actor scheduler executes programs correctly
- ✅ Performance within 2x of current interpreter
- ✅ Fusion reduces spawn overhead by > 50%
- ✅ PGO profile generation works in self-compilation

**Breaking points (stop if):**
- ❌ Actor overhead > 3x current interpreter
- ❌ Fusion < 30% effectiveness
- ❌ Message passing fundamentally incompatible with Perl semantics

### Stage 2 Validation

**Success criteria:**
- ✅ Content addressing overhead < 10% of execution time
- ✅ ECS archetypes improve cache behavior vs Stage 1
- ✅ Event sourcing DB size manageable (< 10x source size)
- ✅ Time-travel debugging works (replay, bisect)

**Breaking points (stop if):**
- ❌ Hash computation > 15% of runtime
- ❌ Archetypes slower than direct access
- ❌ SQLite writes block execution
- ❌ DB growth unsustainable

**Decision point:** If validation succeeds but no need for Arrow, stop here.

### Stage 3 Validation

**Success criteria:**
- ✅ Arrow bindings built/wrapped successfully
- ✅ Zero-copy interop works (Jupyter ↔ Chalk)
- ✅ Performance comparable to Stage 2
- ✅ Ecosystem integration valuable in practice

**Breaking points (stop if):**
- ❌ Arrow bindings unmaintainable
- ❌ Columnar layout hurts graph traversal
- ❌ No actual users need Jupyter integration
- ❌ Build complexity too high

---

## Research Contributions

This architecture enables several publishable contributions:

### 1. ECS/ECA for Compiler Optimization

**Insight:** Game engine memory organization (ECS) applies to compiler alias analysis.

**Novelty:** Using archetypes for type-specialized code generation (Equivalence Class Aliasing).

### 2. Actor-Based Compilation

**Insight:** Sea of Nodes dataflow ≈ actor message passing. Compilation and execution use same model.

**Novelty:** Unified runtime where compiler compiling itself uses same system as running programs.

### 3. Continuation-Controlled Memory

**Insight:** Continuations know when values consumed → no garbage collection needed.

**Novelty:** Linear types enforced by actor topology, not type system.

### 4. Profile-Guided Self-Hosting

**Insight:** Compiler ships with profile from self-compilation → no cold start.

**Novelty:** Content-addressed blocks make profiles portable across runs.

---

## Implementation Timeline

### With Parallelization

| Stage | Parallel Tracks | Rounds | Total Sessions |
|-------|----------------|--------|----------------|
| Stage 1 | 3-4 tracks | 5-8 rounds | 15-25 |
| Stage 2 | 3 tracks | 4-7 rounds | 12-20 |
| Stage 3 | 2 tracks (bindings serial) | 10-20 rounds | 20-40 |
| **Total** | **Varies** | **20-35 rounds** | **47-85** |

### Critical Path (Cannot Parallelize)

1. Stage 1: ECS → Actors → Scheduler (6-10 sessions)
2. Stage 2: Content → Persistence (5-8 sessions)
3. Stage 3: Bindings → Integration (12-25 sessions)

**Minimum critical path:** 23-43 sessions

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Actor overhead too high | Medium | High | Fusion pass, escape analysis |
| ECS poor fit for graphs | Medium | Medium | Region-local archetypes |
| Arrow bindings infeasible | High | Medium | Stop at Stage 2 (SQLite adequate) |
| Hash computation bottleneck | Low | Medium | Fast hash (xxHash), skip for locals |
| Profile portability fails | Low | Low | Fallback to runtime profiling |

---

## Appendix A: Related Work

- **Click compiler** (Cliff Click) - Sea of Nodes inspiration
- **Unity ECS** - Game engine archetype pattern
- **Erlang/OTP** - Actor model for distributed systems
- **Apache Arrow** - Columnar in-memory format
- **DuckDB** - Embedded analytical database

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| **Actor** | Independent computation unit communicating via messages |
| **Archetype** | ECS grouping of entities with same component signature |
| **Basic Block** | Straight-line code with no branches (fused into one actor) |
| **Content Hash** | SHA256 of actor's inputs/operation (deterministic ID) |
| **Continuation** | Actor representing "what happens next" (CPS) |
| **Death/Rebirth** | Actor executes once, dies, spawns continuation |
| **ECA** | Equivalence Class Aliasing - grouping by semantic type |
| **ECS** | Entity-Component-System architecture |
| **Escape Analysis** | Determines if value outlives its defining scope |
| **FusedBlockActor** | Actor executing multiple nodes atomically |
| **Hugh Jackman Model** | Mutation spawns new actor, original persists |
| **PGO** | Profile-Guided Optimization |
| **Region** | Control flow merge point (If/Else join, Loop header) |
| **Slot Reuse** | Arena-style allocation (free list per archetype) |
| **Tier 0/1/2** | Compilation tiers (per-node / fused / JIT) |

---

## Appendix C: Open Questions

1. **Archetype granularity:** Region-local vs global?
   - Measure cache miss rates to decide

2. **Message batching:** Immediate vs batched delivery?
   - Start immediate, add batching if profiling shows benefit

3. **Cross-region parallelism:** How much actually available?
   - Profile: what % of actors have no dependencies?

4. **Arrow necessity:** Is ecosystem integration worth binding complexity?
   - Measure after Stage 2: serialization overhead + user demand

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-02 | Initial design (brainstorming session with perigrin) |

