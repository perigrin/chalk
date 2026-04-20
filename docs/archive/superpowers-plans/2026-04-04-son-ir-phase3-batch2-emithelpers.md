# SoN IR Phase 3 Batch 2: EmitHelpers Migration

> **ARCHIVED — LANDED.** Zero `isa Constructor` sites remain in
> `EmitHelpers.pm`; 69 typed-node `isa Chalk::IR::Node::*` checks are in
> place. The dual-path transitional pattern has been collapsed to
> typed-node-only dispatch. Relevant commits:
> `716f8c3a feat: migrate EmitHelpers isa checks to typed nodes (dual-path)`,
> `ae1229e6 refactor: remove dead Constructor fallbacks from EmitHelpers`,
> `1b90daa8 feat: zero isa Constructor checks in lib — Constructor eliminated from Chalk pipeline`.
> Preserved for history.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (30 `isa Constructor` sites, 27 `->class() eq` checks) from Constructor dispatch to typed `isa Chalk::IR::Node::*` checks with dual-path fallback.

**Architecture:** Same dual-path pattern as Batch 1. Computation types get `$node isa Chalk::IR::Node::X || ($node isa Constructor && $node->class() eq 'X')`. Structural and deferred types keep their Constructor checks.

**Tech Stack:** Perl 5.42.0.

---

## Type Classification for EmitHelpers

| class() value | New type | Category | Action |
|---|---|---|---|
| VarDecl | `Chalk::IR::Node::VarDecl` | computation | migrate |
| MethodCallExpr | `Chalk::IR::Node::Call` (method) | computation | migrate |
| BuiltinCall | `Chalk::IR::Node::Call` (builtin) | computation | migrate |
| InterpolatedString | `Chalk::IR::Node::Interpolate` | computation | migrate |
| SubscriptExpr | `Chalk::IR::Node::Subscript` | computation | migrate |
| PostfixDerefExpr | `Chalk::IR::Node::PostfixDeref` | computation | migrate |
| TryCatchStmt | `Chalk::IR::Node::TryCatch` | computation | migrate |
| ClassDecl | Constructor | structural | keep |
| FieldDecl | Constructor | structural | keep |
| SubDecl | Constructor | structural | keep |
| ReturnStmt | Constructor | deferred (→Return CFG) | keep |
| DieCall | Constructor | deferred (→Unwind CFG) | keep |
| TernaryExpr | Constructor | deferred (→If+Proj CFG) | keep |

### Special case: MethodCallExpr vs BuiltinCall → Call

Both map to `Chalk::IR::Node::Call` but with different `dispatch_kind`. The dual-path for MethodCallExpr is:

```perl
($node isa Chalk::IR::Node::Call && $node->dispatch_kind() eq 'method')
|| ($node isa Chalk::Bootstrap::IR::Node::Constructor
    && $node->class() eq 'MethodCallExpr')
```

For BuiltinCall:
```perl
($node isa Chalk::IR::Node::Call && $node->dispatch_kind() eq 'builtin')
|| ($node isa Chalk::Bootstrap::IR::Node::Constructor
    && $node->class() eq 'BuiltinCall')
```

---

## Task 1: Migrate EmitHelpers.pm

This is a single large task — all 30 sites in one file.

**File:** `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm`

- [ ] **Step 1: Read the entire file**

Read all of EmitHelpers.pm to understand context around each site.

- [ ] **Step 2: Add use statements**

Add near the top, after existing `use` statements:

```perl
use Chalk::IR::Node;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Interpolate;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::TryCatch;
```

- [ ] **Step 3: Migrate each site**

For each of the 30 `isa Constructor` sites and 27 `->class() eq` sites:

**Sites checking ONLY structural/deferred types** — leave unchanged:
- ClassDecl, FieldDecl, SubDecl checks → no change
- ReturnStmt, DieCall, TernaryExpr checks → no change

**Sites checking computation types** — apply dual-path:

Pattern A — guard-then-single-check:
```perl
# Before:
if ($node isa Constructor && $node->class() eq 'VarDecl') { ... }

# After:
if ($node isa Chalk::IR::Node::VarDecl
    || ($node isa Constructor && $node->class() eq 'VarDecl')) { ... }
```

Pattern B — guard-then-multi-dispatch:
```perl
# Before:
if ($node isa Constructor) {
    if ($node->class() eq 'BuiltinCall') { ... }
    if ($node->class() eq 'SubscriptExpr') { ... }
    if ($node->class() eq 'ReturnStmt' ...) { ... }
}

# After:
if ($node isa Chalk::IR::Node::Call && $node->dispatch_kind() eq 'builtin') { ... }
elsif ($node isa Chalk::IR::Node::Subscript) { ... }
# ReturnStmt/DieCall still use Constructor check:
elsif ($node isa Constructor && ($node->class() eq 'ReturnStmt' || ...)) { ... }
# Or if originally wrapped in isa Constructor guard:
elsif ($node isa Constructor) {
    # structural/deferred checks stay here
}
```

Pattern C — `while` loop with isa Constructor guard:
```perl
# Before:
while (defined $cur && $cur isa Constructor) {
    if ($cur->class() eq 'BuiltinCall') { ... }
    ...
}

# After: broaden the guard to accept both
while (defined $cur && ($cur isa Chalk::IR::Node || $cur isa Constructor)) {
    if ($cur isa Chalk::IR::Node::Call && $cur->dispatch_kind() eq 'builtin') { ... }
    elsif ($cur isa Chalk::IR::Node::Subscript) { ... }
    # Keep Constructor fallback for ReturnStmt/DieCall
    elsif ($cur isa Constructor && ($cur->class() eq 'ReturnStmt' || ...)) { ... }
    ...
}
```

- [ ] **Step 4: Run tests**

```bash
SHELL=/bin/bash /bin/bash -c '$HOME/.local/share/pvm/versions/5.42.0/bin/perl -MTAP::Harness -e "TAP::Harness->new({verbosity => 0, lib => [qw(lib)]})->runtests(glob q{t/bootstrap/ir-*.t})"'
```

Also run any full-pipeline tests:
```bash
SHELL=/bin/bash /bin/bash -c '$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/grammar-data-model.t'
```

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: migrate EmitHelpers isa checks to typed nodes (dual-path)"
```

---

## Task 2: Regression Check

- [ ] **Step 1: Run full bootstrap test suite**

```bash
SHELL=/bin/bash /bin/bash -c '$HOME/.local/share/pvm/versions/5.42.0/bin/perl -MTAP::Harness -e "TAP::Harness->new({verbosity => 0, lib => [qw(lib)]})->runtests(glob q{t/bootstrap/*.t})"'
```

Expect: same failures as before (assignment-scope 4/26, c-build-pipeline 1/13, XS direct-call tests). No new failures.

- [ ] **Step 2: Commit any fixes needed**
