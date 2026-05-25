# SoN IR Phase 4b: Incremental Structural Split

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate structural Constructor types to metadata structs, one type at a time. Each step changes the semantic action output AND the codegen input atomically.

**Architecture:** Each structural type gets its own migration step. Codegen methods accept both old Constructor and new metadata during transition. The old codegen path is removed after all callers produce the new format.

**Tech Stack:** Perl 5.42.0, `feature class`.

**Design doc:** `docs/plans/2026-04-04-phase4-structural-split.md` (Phase 4b section)

**Migration order:** UseDecl → _Attribute → FieldDecl → MethodDecl → SubDecl → ClassDecl → Program

**Scope:** This plan covers the structural-split migration only — producing metadata structs from the seven structural Constructor types. It does NOT cover the remaining migration completion work: Shim.pm deletion, codegen migration from `body()` to graph-walk, removal of the `body` field from `MethodInfo` and `compat_class` from `Chalk::IR::Node`, or `_build_method_graph` SSA completion. Those acceptance criteria live in `docs/plans/2026-04-04-son-ir-polymorphic-migration.md`.

---

## Task 1: UseDecl → Chalk::IR::UseInfo

**Files:**
- Create: `lib/Chalk/IR/UseInfo.pm`
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (UseDeclaration method)
- Modify: `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` (_emit_use_decl)
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (use constant detection)
- Modify: `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (if UseDecl checked)
- Modify: `lib/Chalk/Bootstrap/DepChaser.pm` (UseDecl check)
- Test: `t/bootstrap/ir-structural-split.t`

- [ ] **Step 1: Create UseInfo class**

```perl
# ABOUTME: Metadata struct for a use declaration.
# ABOUTME: Stores module name and import arguments as plain data.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::UseInfo {
    field $name :param :reader;
    field $args :param :reader = [];
}
```

- [ ] **Step 2: Write failing test**

Test that UseDeclaration action produces UseInfo, and that codegen handles it.

- [ ] **Step 3: Change UseDeclaration action to produce UseInfo**

```perl
method UseDeclaration($ctx) {
    # ... existing leaf collection ...
    my $name_str = defined $module_name ? $module_name->value() : '';
    my $args_list = $import_args // [];
    return Chalk::IR::UseInfo->new(
        name => $name_str,
        args => $args_list,
    );
}
```

Note: `args` is still an arrayref of IR nodes (Constant nodes for import args). The UseInfo wraps plain data for the name but keeps IR nodes for args that codegen needs to emit.

- [ ] **Step 4: Update codegen to accept both formats**

In `_emit_use_decl`:
```perl
method _emit_use_decl($node) {
    my ($module_name, $args);
    if ($node isa Chalk::IR::UseInfo) {
        $module_name = $node->name();
        $args = $node->args()->@* ? $node->args() : undef;
    } else {
        # Old Constructor path
        $module_name = $node->inputs()->[0]->value();
        $args = $node->inputs()->[1];
    }
    # ... rest unchanged, uses $module_name and $args ...
}
```

Same dual-path in C.pm's `use constant` detection and DepChaser.

- [ ] **Step 5: Update _emit_node to route UseInfo**

In `_emit_node`, UseInfo isn't a Constructor, so the Constructor dispatch won't catch it. Add a typed check before the Constructor block:

```perl
if ($node isa Chalk::IR::UseInfo) {
    return $self->_emit_use_decl($node);
}
```

- [ ] **Step 6: Also handle UseInfo in the PostfixExpression merge logic**

Actions.pm line ~719 checks `$item->class() eq 'UseDecl'` during statement merging. UseInfo doesn't have `class()`. Add a typed isa check.

- [ ] **Step 7: Run tests, commit**

```bash
git commit -m "feat: UseDecl → Chalk::IR::UseInfo metadata struct"
```

---

## Task 2: _Attribute → plain hashref

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Actions.pm` (attribute creation sites)

_Attribute is used inside FieldDecl to represent :param, :reader, :writer.

- [ ] **Step 1: Find all _Attribute creation sites**

```bash
grep -n '_Attribute' lib/Chalk/Bootstrap/Perl/Actions.pm
```

- [ ] **Step 2: Change to produce plain hashrefs**

```perl
# Before:
$factory->make('Constructor', class => '_Attribute', name => $name_node, ...)

# After:
{ name => $name_str }
```

- [ ] **Step 3: Update FieldDecl consumers that read attributes**

The codegen reads attributes from FieldDecl's inputs. Since attributes become plain hashrefs, the codegen needs to read `$attr->{name}` instead of `$attr->inputs()->[0]->value()`.

But FieldDecl is still a Constructor — it wraps the attributes array in its inputs. The plain hashrefs are just elements of that array. Codegen already iterates the attributes array. Check if it accesses them as nodes.

- [ ] **Step 4: Run tests, commit**

```bash
git commit -m "feat: _Attribute → plain hashref {name => str}"
```

---

## Task 3: FieldDecl → Chalk::IR::FieldInfo

**Files:**
- Modify: Actions.pm (FieldDeclaration method, AssignmentExpression FieldDecl branch)
- Modify: Target/Perl.pm (_emit_field_decl)
- Modify: Target/C.pm (field analysis)
- Modify: EmitHelpers.pm (field detection)

- [ ] **Step 1: Change FieldDeclaration to produce FieldInfo**

FieldInfo already exists (Phase 1). Change:
```perl
# Before:
$factory->make('Constructor', class => 'FieldDecl', name => $name_node, ...)

# After:
Chalk::IR::FieldInfo->new(
    name => $name_str,
    attributes => \@attr_hashrefs,
    default_value => $default_value,
)
```

- [ ] **Step 2: Update codegen dual-path for FieldInfo**

- [ ] **Step 3: Update AssignmentExpression FieldDecl branch**

The assignment action checks `$target->class() eq 'FieldDecl'` and reads inputs. With FieldInfo, check `$target isa Chalk::IR::FieldInfo` and use accessors.

- [ ] **Step 4: Run tests, commit**

```bash
git commit -m "feat: FieldDecl → Chalk::IR::FieldInfo metadata struct"
```

---

## Task 4: MethodDecl → Chalk::IR::MethodInfo + Graph

This is the big one — method bodies become per-method graphs.

**Files:**
- Modify: Actions.pm (MethodDefinition/MethodDecl)
- Modify: `lib/Chalk/IR/Graph.pm` (add schedule field if not present)
- Modify: Target/Perl.pm (_emit_method_decl → _emit_method_info)
- Modify: Target/C.pm (_emit_method)
- Modify: EmitHelpers.pm (method analysis)

- [ ] **Step 1: Change MethodDefinition action**

Build a Chalk::IR::Graph from the method body, extract schedule from cfg_state, wrap in MethodInfo:

```perl
# Extract method name, params as plain strings
my $name_str = $name_node->value();
my @param_strs = map { $_->value() } $params->@*;

# Build graph (Start already exists from cfg_state)
my $graph = Chalk::IR::Graph->new(
    start    => $start_node,
    returns  => \@return_nodes,
    schedule => $schedule,
);

return Chalk::IR::MethodInfo->new(
    name   => $name_str,
    params => \@param_strs,
    graph  => $graph,
);
```

- [ ] **Step 2: Handle ReturnStmt → Return CFG node**

When building the graph, ReturnStmt Constructor nodes in the body become Return CFG nodes. Scan the body for ReturnStmt, convert to `make_cfg('Return', ...)`, collect in `@return_nodes`.

Similarly, DieCall → Unwind CFG node.

- [ ] **Step 3: Extract schedule from cfg_state**

Walk the cfg_state entries for nodes in this method's body, collect them as the graph's schedule hashref.

- [ ] **Step 4: Update codegen**

Add `_emit_method_info($method_info)` that reads metadata accessors and calls `_emit_body_from_graph()` for the method body.

- [ ] **Step 5: Run tests, commit**

```bash
git commit -m "feat: MethodDecl → Chalk::IR::MethodInfo + per-method Graph"
```

---

## Task 5: SubDecl → Chalk::IR::SubInfo + Graph

Same pattern as Task 4 but for subroutines. SubInfo has `scope` field.

- [ ] **Step 1-4: Same as Task 4, adapted for SubDecl/SubInfo**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: SubDecl → Chalk::IR::SubInfo + per-method Graph"
```

---

## Task 6: ClassDecl → Chalk::IR::ClassInfo

ClassDecl wraps fields, methods, subs. After Tasks 3-5, these are already FieldInfo, MethodInfo, SubInfo objects.

- [ ] **Step 1: Change ClassDeclaration action**

Partition body items into fields, methods, subs. Wrap in ClassInfo.

- [ ] **Step 2: Update codegen**

Add `_emit_class_info($class_info)` using metadata accessors.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: ClassDecl → Chalk::IR::ClassInfo metadata struct"
```

---

## Task 7: Program → Chalk::IR::Program

The final step — Program collects UseInfo, ClassInfo, SubInfo.

- [ ] **Step 1: Change Program action**

Partition top-level statements into use_decls, classes, top_level_subs.

- [ ] **Step 2: Update codegen entry points**

`generate()` and `generate_with_cfg()` accept `Chalk::IR::Program`.
Add `_emit_program_meta()` that walks metadata.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: Program → Chalk::IR::Program metadata struct"
```

---

## Task 8: Regression Check

- [ ] **Step 1: Run all IR + scope + cfg tests**
- [ ] **Step 2: Run full bootstrap test suite**
- [ ] **Step 3: Verify 16 green eval files still produce correct output**
