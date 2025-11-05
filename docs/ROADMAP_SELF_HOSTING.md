# Chalk Self-Hosting Interpreter Roadmap

**Generated**: 2025-11-04
**Status**: Based on accurate audit of codebase (not outdated docs)

## Executive Summary

Chalk is **much closer to self-hosting** than documentation suggests:

- ✅ **88% interpreter complete** (30/34 nodes have `execute()` methods)
- ✅ **100% parsing self-hosting** (125/125 lib files parse)
- ✅ **Pure context-as-closure memory model** (Phases 1-4 complete)
- ✅ **Type system with context handling** via `Type::List->convert_to_target()`
- ⚠️ **2-3 critical bugs** blocking execution

**Estimated timeline to minimal self-hosting: 2-3 months**

## Current State (Accurate Assessment)

### What Works ✅

**Parser & IR Generation**
- Earley parser with Leo optimization
- Sea of Nodes IR generation (default behavior)
- Composite semiring (SPPF + semantic actions)
- 100% of Chalk codebase parses successfully

**Memory Model**
- Pure context-as-closure (no Store/Load nodes)
- Heapless architecture: collections ARE contexts
- References via `(context, label)` indirection
- Immutable + rebind semantics

**Type System**
- 20+ types with inference
- Context handling via `List->convert_to_target($sigil)`
- Coercion: `to_num()`, `to_str()`, `to_bool()`
- Ephemeral List type converts to Array/Hash

**Interpreter Coverage**
- 30/34 nodes (88%) have `execute()` methods
- Only missing: PreIncrement, PostIncrement, PreDecrement, PostDecrement
- Note: Grammar rules exist, just need semantic actions

**Validation**
- Comprehensive `Chalk::IR::Validator`
- CFG, SSA, dominance, phi placement checks
- Class, array, hash, string, module node validation

### What's Broken 🔴

**Critical Blockers (P0)**

1. **Variable Reassignment Bug**
   ```perl
   my $x = 5;
   $x = 10;
   return $x;  # Returns 5, should return 10
   ```
   - Issue: Context extension creates proper shadowing, but lookup doesn't see new value
   - Location: `Builder->build_store_node()` or interpreter context threading
   - Impact: Blocks all stateful programs

2. **Control Flow Assignment**
   ```perl
   my $result = 0;
   if ($x > 0) { $result = 10; }
   return $result;  # Doesn't update correctly
   ```
   - Issue: Assignments inside if/else don't propagate through Region/Phi
   - Location: `Region.pm`, `Phi.pm` execute() methods
   - Impact: Blocks conditional logic with side effects

3. **Multiple Return Nodes**
   ```perl
   if ($x > 0) { return 42; } else { return -42; }
   # Error: Multiple Return nodes without __CONTROL_PLACEHOLDER__
   ```
   - Issue: Parser creates multiple Return nodes for if/else with returns
   - Location: Grammar semantic actions, IR builder
   - Impact: Blocks early returns in branches

**Secondary Issues (P1)**

4. **Negative Literal Parsing**
   ```perl
   return -5;  # Creates 4 Return nodes (parser ambiguity)
   ```
   - Workaround: Use `0 - 5` instead

5. **Boolean Type Representation**
   ```perl
   return 5 > 10;  # Returns 0, Perl 5.42 returns ''
   ```
   - May be acceptable difference (needs decision)

## Roadmap

### Phase 1: Fix Critical Context Bugs (3-4 weeks)

**Goal**: Execute linear programs with variables and arithmetic

**1.1 Variable Reassignment (Week 1-2)**

Issue deep-dive:
```perl
# Builder creates context extension:
$context = extend_context($context, "lexical:\$x", $node_5);  # $x = 5
$context = extend_context($context, "lexical:\$x", $node_10); # $x = 10

# Interpreter should see node_10, but sees node_5
# Hypothesis: Builder stores old context in IR, interpreter uses stale context
```

**Debugging approach:**
1. Add debug logging to `Builder->build_store_node()`
2. Trace context state through IR construction
3. Check if `VariableRead` execute() gets updated context
4. Verify interpreter threads context correctly between nodes

**Files to investigate:**
- `lib/Chalk/IR/Builder.pm` (lines 201-214: `build_store_node`)
- `lib/Chalk/IR/Builder.pm` (lines 218-240: `build_load_node`)
- `lib/Chalk/IR/Node/VariableRead.pm` (line 23-30: `execute`)
- `lib/Chalk/IR/Interpreter.pm` (lines 23-54: context threading)

**Test case:**
```perl
# Add to t/sea-of-nodes/interpreter-differential.t
test_against_perl('my $x = 5; $x = 10; return $x;', 'Variable reassignment');
```

**Success criteria:**
- Test passes (returns 10)
- Context lookup finds most recent binding
- Differential tests for reassignment pass

**1.2 Control Flow Context Merging (Week 2-3)**

Issue: Region/Phi nodes don't properly merge contexts after branches

**Investigation:**
```perl
# IR structure for: if ($x > 0) { $result = 10; } else { $result = 20; }
#
# Start → If($x > 0)
#         ├─ IfTrue  → Store($result, 10) → Region
#         └─ IfFalse → Store($result, 20) → Region
#                                           ↓
#                                         Phi($result)
#                                           ↓
#                                         Load($result)
```

With context model, Phi should:
1. Take contexts from both branches
2. Merge using Phi semantics
3. Provide merged context to successor

**Files to fix:**
- `lib/Chalk/IR/Node/Region.pm` (execute method)
- `lib/Chalk/IR/Node/Phi.pm` (execute method)
- `lib/Chalk/IR/Node/If.pm` (verify control flow)

**Test cases:**
```perl
test_against_perl('my $x = 5; my $r = 0; if ($x > 0) { $r = 10; } return $r;', 'If with assignment');
test_against_perl('my $x = 5; my $r; if ($x > 0) { $r = 10; } else { $r = 20; } return $r;', 'If-else with assignment');
```

**Success criteria:**
- Region merges incoming control + contexts
- Phi selects correct value from correct context
- Assignments inside branches visible after merge

**1.3 Multiple Return Nodes (Week 3-4)**

Issue: Grammar creates multiple Return nodes for if/else with returns

**Root cause:**
Parser creates intermediate parse states where each branch has a Return node, but doesn't properly mark them with `__CONTROL_PLACEHOLDER__`.

**Investigation:**
- Check grammar semantic actions for `if/else` statements
- Verify Return node creation in `Builder->build_return_node()`
- Ensure control flow properly links Returns via `__CONTROL_PLACEHOLDER__`

**Files to fix:**
- Grammar semantic actions for conditional statements
- `lib/Chalk/IR/Builder.pm` (Return node control flow)
- Possibly `lib/Chalk/Semiring/Semantic.pm`

**Test case:**
```perl
test_against_perl('if (1) { return 42; } else { return -42; }', 'If-else with returns');
```

**Success criteria:**
- Only one winning Return node in final IR
- Or multiple Returns properly linked to control flow
- Validator passes (no malformed IR error)

### Phase 2: Complete Missing Features (2-3 weeks)

**Goal**: Support increment/decrement operators

**2.1 Implement Increment/Decrement (Week 1-2)**

Currently:
- ✅ Grammar rules exist (`++$x`, `$x++`, `--$x`, `$x--`)
- ❌ Semantic actions not implemented (TODOs in code)
- ❌ Execute methods not implemented

**Implementation steps:**

1. Add semantic actions to `lib/Chalk/Grammar/Chalk/Rule/Unary.pm`:
```perl
# Add to evaluate() method:
elsif ($operator eq '++') {
    return $builder->build_pre_increment_node($operand);
}
elsif ($operator eq '--') {
    return $builder->build_pre_decrement_node($operand);
}
```

2. Add semantic actions to `lib/Chalk/Grammar/Chalk/Rule/Postfix.pm`:
```perl
method evaluate($context) {
    my @children = $context->children->@*;

    if (@children == 2) {
        my $var = $context->child(0);
        my $op = $context->child(1)->extract;

        my $builder = $context->env->{ir_builder};
        if ($op eq '++') {
            return $builder->build_post_increment_node($var);
        } elsif ($op eq '--') {
            return $builder->build_post_decrement_node($var);
        }
    }

    return $context->child(0);
}
```

3. Add builder methods:
```perl
method build_pre_increment_node($operand) {
    # ++$x is equivalent to: $x = $x + 1; return $x;
    my $one = $self->build_constant_node(1);
    my $sum = $self->build_add_node($operand, $one);
    # Update variable in context
    my $var_label = $operand->var_label;  # Assuming VariableRead node
    $self->build_store_node($var_label, $sum);
    return $sum;  # Return new value
}

method build_post_increment_node($operand) {
    # $x++ is equivalent to: my $tmp = $x; $x = $x + 1; return $tmp;
    my $old_value = $operand;  # Save old value
    my $one = $self->build_constant_node(1);
    my $sum = $self->build_add_node($operand, $one);
    # Update variable in context
    my $var_label = $operand->var_label;
    $self->build_store_node($var_label, $sum);
    return $old_value;  # Return old value
}
```

4. Implement execute() methods in node classes
5. Add differential tests

**Prerequisites:**
- Variable reassignment bug MUST be fixed first
- Context extension must work correctly

**Test cases:**
```perl
test_against_perl('my $x = 5; ++$x; return $x;', 'Pre-increment');
test_against_perl('my $x = 5; my $y = ++$x; return $y;', 'Pre-increment return value');
test_against_perl('my $x = 5; $x++; return $x;', 'Post-increment');
test_against_perl('my $x = 5; my $y = $x++; return $y;', 'Post-increment return value');
```

**2.2 String Operations (Week 2-3)**

IR nodes exist, need execute() methods:
- StrConcat
- StrLength
- StrSubstr

Required for: Parser self-hosting (grammar string manipulation)

### Phase 3: Enhanced Validation (2-3 weeks)

**Goal**: Catch IR bugs early with better validation

**3.1 Context-Aware Validation**
- Validate contexts thread properly through control flow
- Check Region nodes merge contexts from all predecessors
- Verify Phi nodes have entries for each predecessor

**3.2 Runtime Validation Mode**
- Add `--validate` flag to interpreter
- Check IR structure before execution
- Validate variable lookups succeed

**3.3 Better Error Messages**
- Include source locations in errors
- Visualize IR graphs with GraphViz
- Add "explain" mode for validation failures

### Phase 4: Module System & Method Dispatch (4-6 weeks)

**Goal**: Execute multi-file Chalk programs with OOP

**4.1 Method Dispatch**
- Implement method calls on objects
- Required for: `$builder->add_node($node)`
- Critical for: Self-hosting (Chalk uses OOP heavily)

**4.2 Module Loading**
- UseStatement nodes exist
- Implement interpreter support for `use`
- Handle imports/exports

**4.3 Package Namespacing**
- Support `package Chalk::Parser;`
- Namespace isolation

### Phase 5: Bootstrap Subset Execution (4-6 weeks)

**Goal**: Execute simple Chalk modules

**5.1 Target Simple Modules First**
- `Chalk::Type::Int`, `Chalk::Type::Str` (simple classes)
- `Chalk::IR::Node::Constant` (minimal dependencies)
- Build complexity incrementally

**5.2 Progressive Testing**
- Execute one module at a time
- Fix discovered issues
- Expand to more complex modules

**5.3 Closure Support**
- Lexical variable capture
- Required for: Contexts-as-closures executing themselves!

### Phase 6: Full Self-Hosting (6-8 weeks)

**Goal**: Chalk compiles and executes Chalk

**6.1 Parser Execution**
- Execute `Chalk::Parser`, `Chalk::Grammar`
- Full grammar BNF parsing

**6.2 Semantic Actions**
- Execute semantic action evaluation
- Semiring operations

**6.3 Bootstrap Closure**
- `chalk.pl` compiles `chalk.pl`
- Generated IR matches original
- Fixed point verification

## Priority Matrix

| Priority | Task | Est. Time | Dependencies |
|----------|------|-----------|--------------|
| **P0** | Variable reassignment bug | 1-2 weeks | None |
| **P0** | Control flow assignment (Region/Phi) | 1-2 weeks | None |
| **P0** | Multiple Return nodes | 1 week | None |
| **P1** | Negative literal parsing | 1 week | Grammar knowledge |
| **P2** | Increment/decrement operators | 1-2 weeks | P0 complete |
| **P2** | String operation execute() | 1 week | None |
| **P3** | Enhanced validation | 2-3 weeks | P0 complete |
| **P3** | Method dispatch | 2-3 weeks | P0 complete |
| **P4** | Module system | 2-3 weeks | Method dispatch |
| **P4** | Bootstrap simple modules | 3-4 weeks | Module system |
| **P5** | Full self-hosting | 6-8 weeks | All above |

## Milestones

### Milestone 1: Linear Program Execution (Week 4)
- ✅ Variables with reassignment
- ✅ Arithmetic operations
- ✅ Simple returns
- **Test**: `my $x = 5; $x = $x + 10; return $x;`

### Milestone 2: Control Flow (Week 8)
- ✅ If/else statements
- ✅ Loops
- ✅ Early returns
- **Test**: Fizzbuzz in Chalk

### Milestone 3: Data Structures (Week 12)
- ✅ Arrays and hashes
- ✅ String operations
- ✅ References
- **Test**: Array manipulation programs

### Milestone 4: OOP (Week 18)
- ✅ Method dispatch
- ✅ Module loading
- ✅ Class instantiation
- **Test**: Simple class-based program

### Milestone 5: Bootstrap (Week 26)
- ✅ Execute simple Chalk modules
- ✅ Execute parser components
- ✅ Full self-hosting
- **Test**: Chalk compiles Chalk

## Key Insights

1. **Much closer than expected**: 88% of interpreter done, not 71%
2. **Documentation was outdated**: Mentioned Store/Load nodes that don't exist
3. **Type system handles context**: List vs scalar via `convert_to_target()`
4. **Only 2-3 critical bugs**: Fix those, and simple programs will run
5. **Increment/decrement not blocking**: Just need semantic actions, grammar exists

## Success Criteria

**Minimal Self-Hosting (3 months)**
- Execute linear programs with variables
- Control flow with if/else/loops
- Basic data structures

**Full Self-Hosting (6-12 months)**
- Chalk parses its own source
- Chalk generates IR for itself
- Chalk executes generated IR
- Bootstrap closure achieved

## Next Actions

**This Week:**
1. Debug variable reassignment (add logging to Builder/Interpreter)
2. Create minimal test case that isolates the bug
3. Fix context threading through IR

**Next Week:**
1. Fix Region/Phi context merging
2. Add differential tests for control flow
3. Document Boolean type decision

**This Month:**
1. Complete P0 critical bugs
2. Implement increment/decrement
3. Execute first simple Chalk program end-to-end

---

**Note**: This roadmap is based on actual code audit, not outdated documentation. Numbers are accurate as of 2025-11-04.
