# Phase 7d Implementation Plan — Schedule-Driven Body Emission in Target::C

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Target::C's method/sub body emission from `$method->body` arrayref iteration to consuming `Chalk::IR::Schedule` instances produced by `Chalk::IR::Scheduler::EagerPinning`, mirroring Target::Perl's existing schedule-driven shape.

**Architecture:** Three commits on `fixup-audit-baseline`. Commit 1 instruments repair counters as a measurement instrument (pure data gathering, no behavior change). Commit 2 migrates `_emit_method` / `_emit_complex_method` / `_emit_sub` plus 9 analysis helpers, builds the C-side schedule walker mirroring Target::Perl, and deletes repairs proven dead by Commit 1's counters. Commit 3 always ships and documents the outcome (delete counters if all repairs dead; comment-document survivors otherwise).

**Tech Stack:** Perl 5.42.0 (via pvm at `$HOME/.local/share/pvm/versions/5.42.0/bin/perl`, NOT plenv), `feature class`, postfix dereferencing, `true`/`false` builtins, `try/catch`. Test harness: `perl -Ilib t/...`.

**Spec:** `docs/plans/2026-05-25-phase-7d-design.md`

**Skills mandate (per CLAUDE.md):** every implementer of every task MUST invoke `@superpowers:writing-perl-5.42.0` and `@superpowers:test-driven-development` before writing code.

---

## File Map

### Commit 1 — files touched

**Modify:**
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` — add `%_repair_counters` field + accessors + `_record_repair` calls inside each repair entry-point.

**Create:**
- `t/bootstrap/c-repair-coverage.t` — runs a small corpus through `_generate_c_files` and reports repair fire counts via `diag`.

### Commit 2 — files touched

**Modify:**
- `lib/Chalk/Bootstrap/Perl/Target/C.pm` — rewrite `_emit_method`, `_emit_complex_method`, `_emit_sub`; add new schedule-walker helpers (`_emit_scheduled_c_body`, `_emit_c_schedule_item`, the head emitters, `_emit_c_block_close_tail`); add `_emit_complex_sub_body`.
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` — rewrite 6 analysis helpers (schedule-substrate group); 3 helpers stay node-level with calling-pattern changes only. Delete repair-mechanism methods whose Commit 1 counts were zero. Add `_emit_simple_*_method` extracted helpers.
- `lib/Chalk/Bootstrap/Perl/Target/C.pm` — update the sub-emission loop at C.pm:1585-1604 to call `_emit_sub($sub)` instead of `_emit_sub($sname, $sparams, $sbody)`.
- `t/bootstrap/c-emit-helpers-inheritance.t` — drop `can(...)` assertions for any deleted repair methods.

**Create:**
- `t/bootstrap/c-simple-body-shortcuts.t` — asserts simple-body detection still fires for trivially simple methods after the schedule migration.
- `t/bootstrap/c-sub-state-leak.t` — verifies `_emit_sub`'s try/catch state save/restore.
- `t/bootstrap/c-schedule-tail-control.t` — smoke test for VarDecl-with-control-flow-init handling.

### Commit 3 — files touched

**Modify (Case A — all dead):**
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` — delete `%_repair_counters`, `_record_repair`, `repair_counters` accessor.
- Delete: `t/bootstrap/c-repair-coverage.t`.

**Modify (Case B — survivors):**
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` — add documentation comments above each surviving repair counter explaining what it monitors and under what conditions it should fire.

---

## Baseline capture (one-time, before any task)

Captured against `fixup-audit-baseline` HEAD at start of Phase 7d (currently `3d70fce7` after the design commit). These are the regression-gate counts; any change in pass/fail count after Commit 2 must be deliberately accounted for in the commit message.

- [ ] **Step B1: Confirm branch state and HEAD.**

```bash
git log --oneline -1
git status
```

Expected: first line of log is `3d70fce7 docs(plans): Phase 7d design — schedule-driven body emission` (or a later docs-only commit if other work landed). Working tree clean.

- [ ] **Step B2: Run test gates and record pass/fail counts.**

```bash
PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl
for t in t/bootstrap/mop/codegen-byte-compat.t \
         t/bootstrap/mop/class-scope-vars.t \
         t/bootstrap/mop/use-constants.t \
         t/bootstrap/mop/parse-integration.t \
         t/bootstrap/mop/parse-threading.t \
         t/bootstrap/mop/ctx-mop-propagation.t \
         t/bootstrap/mop/field-helpers.t \
         t/bootstrap/mop/test-pipeline-helper.t \
         t/bootstrap/c-emit-helpers-inheritance.t \
         t/bootstrap/bnf-target-c.t \
         t/bootstrap/xs-isa-inheritance.t \
         t/bootstrap/xs-athx-no-args.t; do
    echo "=== $t ==="
    $PERL -Ilib "$t" 2>&1 | tail -3
done
```

Record:
- `mop/codegen-byte-compat.t`: expected 19/19
- `mop/class-scope-vars.t`: expected 16/16
- `mop/use-constants.t`: expected 11/11
- `mop/parse-integration.t`: expected 34/34
- `mop/parse-threading.t`: expected 11/11
- `mop/ctx-mop-propagation.t`: expected 10/10
- `mop/field-helpers.t`: expected 14/14
- `mop/test-pipeline-helper.t`: expected 5/5
- `c-emit-helpers-inheritance.t`: expected 55/55
- `bnf-target-c.t`: expected 178/178
- `xs-isa-inheritance.t`: expected 10/10
- `xs-athx-no-args.t`: expected 7/7

- [ ] **Step B3: Record pre-existing failures (NOT regressions).**

```bash
PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/xs-polymorphic-dispatch.t 2>&1 | tail -3
$PERL -Ilib t/bootstrap/xs-int-specialization.t 2>&1 | tail -3
```

Record:
- `xs-polymorphic-dispatch.t`: expected 59/60 (1 pre-existing fail at Component 4).
- `xs-int-specialization.t`: expected 2/6 (4 pre-existing fails on `newSVnv` matching).

These must not get WORSE post-Commit-2; they need not improve.

---

## COMMIT 1 — repair-counter instrumentation

### Task 1.1: Add `%_repair_counters` field and `_record_repair` method to EmitHelpers

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm`

- [ ] **Step 1: Find the existing `field` declarations block.**

```bash
grep -n '^    field ' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm | head -20
```

Expected: lines 33-52 area; multiple `field $foo;` lines.

- [ ] **Step 2: Add the new field.**

Edit `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm`. Near the end of the `field` declarations block (find the last field declaration around line 51-52 and add immediately after):

```perl
    field %_repair_counters;  # repair_name => fire_count; populated by _record_repair.
```

- [ ] **Step 3: Find the accessor methods block.**

The accessor methods (e.g., `method _get_field_map() { ... }`) live around lines 60-100. Add the counter accessors at the end of that block (find the last simple accessor and add after):

```perl
    method _record_repair($name) {
        $_repair_counters{$name}++;
        return;
    }
    method repair_counters()   { return { %_repair_counters }; }
    method reset_repair_counters() { %_repair_counters = (); }
```

(`reset_repair_counters` is for the test to isolate per-class counts; `repair_counters` returns a hash COPY so callers can't mutate internal state.)

- [ ] **Step 4: Sanity-test by running existing tests.**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -5
```

Expected: still 55/55 — adding a field + 3 methods is invisible to existing tests (no behavior change yet).

- [ ] **Step 5: Do NOT commit yet.** Commit 1 lands after Tasks 1.2 and 1.3.

---

### Task 1.2: Instrument each repair method with `_record_repair` calls

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm`

**Repair sites to instrument** (verified line numbers from current head):

| Method | Line | Repair name to record |
|---|---|---|
| `_repair_stale_merge` | 330 | `'repair_stale_merge'` |
| `_is_stale_merge` (detection only — separate counter) | 315 | `'is_stale_merge_detected'` |
| `_fixup_xs_list_destructuring` (line 395) | 395 | per-pattern: `'list_destr_pred_entry'`, `'list_destr_safe_set'`, etc. — see Step 3 |
| `_fixup_ternary_assignment` | grep first | `'ternary_assignment'` |
| `_fixup_filtercomposite_add_destructuring` | grep first | `'filtercomposite_add_destr'` |
| `emit_cfg_loop` chart-re-read injection | ~1207 | `'chart_re_read'` |

- [ ] **Step 1: Locate each repair method's entry point.**

```bash
PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl
grep -n 'method _repair_stale_merge\|method _is_stale_merge\|method _fixup_xs_list_destructuring\|method _fixup_ternary_assignment\|method _fixup_filtercomposite_add_destructuring\|method emit_cfg_loop' lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm
```

- [ ] **Step 2: Add `_record_repair` calls at each method's first "patch fired" branch.**

For each method, find the FIRST regex match / substitution that fires when the repair actually applies (not the entry-point itself — we want to count fires, not calls). Add `$self->_record_repair('NAME');` immediately after the match check, BEFORE the substitution.

Example for `_repair_stale_merge` (around line 330-360):

```perl
    method _repair_stale_merge($xs_lines, $method_decl) {
        # ... existing setup ...
        my @fixed;
        my $fired = 0;
        for my $line ($xs_lines->@*) {
            if ($line =~ /SOME_STALE_MERGE_PATTERN/) {
                $self->_record_repair('repair_stale_merge') unless $fired++;
                # ... existing substitution ...
            }
            push @fixed, $line;
        }
        return \@fixed;
    }
```

The `unless $fired++` idiom ensures one count per method invocation, not one per matched line — we want "did this method fire for THIS method body" granularity. Without the guard, a single method with multiple matching lines counts as N fires.

Apply the same pattern to each repair method. For `_fixup_xs_list_destructuring` which has multiple distinct patterns (lines 395-450 area), use a separate counter name per pattern AND the per-pattern-per-method guard:

```perl
    method _fixup_xs_list_destructuring($xs_text) {
        if ($xs_text =~ /core_id_sv = .../) {
            $self->_record_repair('list_destr_pred_entry');
            # ... substitution ...
        }
        $xs_text =~ s{(w_core_id_sv = ...)}{$1\n ...}sg
            and $self->_record_repair('list_destr_wref');
        # ... and so on for each named substitution ...
    }
```

Use the postfix `and` idiom for direct `=~ s/.../.../` substitutions (the substitution returns the number of replacements; the `and` only fires if non-zero). For `if (match) { substitute }` blocks, record inside the `if`.

For `emit_cfg_loop`'s chart-re-read at ~line 1207: find the branch that does the actual injection (look for the comment about chart re-read at line 1184); record at the top of that branch.

For `_is_stale_merge`: it's a detection method (returns bool). Record at the top of the method whenever it returns TRUE (the call sites use the return value to decide whether to invoke `_repair_stale_merge`). Easiest pattern:

```perl
    method _is_stale_merge($xs_output) {
        my $is = ...existing detection logic...;
        $self->_record_repair('is_stale_merge_detected') if $is;
        return $is;
    }
```

- [ ] **Step 3: Sanity-test that the instrumentation doesn't break existing tests.**

```bash
$PERL -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -5
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -5
```

Expected: 55/55 and 178/178 unchanged. The instrumentation must not change emission output — it only counts fires.

- [ ] **Step 4: Do NOT commit yet.** Task 1.3 lands next.

---

### Task 1.3: Create the coverage test (TDD)

**Files:**
- Create: `t/bootstrap/c-repair-coverage.t`

- [ ] **Step 1: Write the test.**

Create `t/bootstrap/c-repair-coverage.t`:

```perl
# ABOUTME: Phase 7d Commit 1 instrument — runs corpus through Target::C and reports repair fires.
# ABOUTME: Always passes; the diag output drives Commit 2's repair-deletion decisions.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(parse_perl_source);
use Chalk::Bootstrap::Perl::Target::C;

# Small corpus: 3 real classes from lib/Chalk/Bootstrap/Semiring/.
# These exercise enough body shapes to fire any repair that has live cases.
my @CORPUS = (
    'lib/Chalk/Bootstrap/Semiring/Boolean.pm',
    'lib/Chalk/Bootstrap/Semiring/Structural.pm',
    'lib/Chalk/Grammar/Symbol.pm',
);

my %total_counters;

for my $src_path (@CORPUS) {
    SKIP: {
        skip "Source file not present: $src_path", 1 unless -e $src_path;

        open my $fh, '<:utf8', $src_path or skip "Cannot read $src_path: $!", 1;
        local $/;
        my $source = <$fh>;
        close $fh;

        my $mop = Chalk::MOP->new;
        Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
        my ($ir, $sa, $ctx) = parse_perl_source($source);

        skip "Parse failed for $src_path", 1 unless defined $ctx;

        my $mop_class;
        for my $cls ($mop->classes) {
            next if $cls->name eq 'main';
            $mop_class = $cls;
            last;
        }
        skip "No class in $src_path", 1 unless defined $mop_class;

        my $module_name = $mop_class->name;
        my $target = Chalk::Bootstrap::Perl::Target::C->new(
            module_name => $module_name,
        );
        $target->reset_repair_counters;

        my $result = eval {
            $target->_generate_c_files($ir, $sa, $ctx)
        };
        ok(defined $result, "Generated C for $src_path") or do {
            diag "Error generating $src_path: $@";
        };

        my $counters = $target->repair_counters;
        for my $name (sort keys $counters->%*) {
            $total_counters{$name} += $counters->{$name};
            diag(sprintf "  %-40s  %4d fires (in %s)",
                 $name, $counters->{$name}, $module_name);
        }
    }
}

diag('');
diag('=== Repair counter totals across corpus ===');
if (%total_counters) {
    for my $name (sort keys %total_counters) {
        diag(sprintf "  %-40s  %4d fires", $name, $total_counters{$name});
    }
} else {
    diag('  (no repairs fired on any corpus file)');
}
diag('');
diag('Commit 2 should DELETE repairs with zero fires here, KEEP and document survivors.');

done_testing();
```

- [ ] **Step 2: Run the test.**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-repair-coverage.t 2>&1 | tail -40
```

Expected: PASS (with diag output reporting repair counts).

**SAVE THE OUTPUT.** Copy the "Repair counter totals across corpus" block into a scratch note — Commit 2 reads this to decide which repairs to delete.

---

### Task 1.4: Commit 1

- [ ] **Step 1: Run the full regression suite.**

```bash
PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl
for t in t/bootstrap/c-emit-helpers-inheritance.t \
         t/bootstrap/bnf-target-c.t \
         t/bootstrap/xs-isa-inheritance.t \
         t/bootstrap/xs-athx-no-args.t \
         t/bootstrap/mop/*.t \
         t/bootstrap/c-repair-coverage.t; do
    echo "=== $t ===";
    $PERL -Ilib "$t" 2>&1 | tail -3;
done
```

Expected: all green at baseline counts plus c-repair-coverage.t passing.

- [ ] **Step 2: Stage and commit.**

```bash
git status
git add lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm \
        t/bootstrap/c-repair-coverage.t
git status   # verify nothing extra staged
git commit -m "$(cat <<'EOF'
chore(target-c): instrument repair mechanisms for 7d retirement audit

Adds %_repair_counters field, _record_repair / repair_counters /
reset_repair_counters methods on EmitHelpers. Each repair method's
first patch-fired branch records its fire count. The new test
t/bootstrap/c-repair-coverage.t runs a small corpus through
_generate_c_files and reports per-repair fire totals via diag.

Pure measurement instrument; no production-behavior change. The
diag output drives Commit 2's deletion decisions for individual
repair mechanisms.

Repairs instrumented:
- _repair_stale_merge
- _is_stale_merge (detection)
- _fixup_xs_list_destructuring (per-pattern)
- _fixup_ternary_assignment
- _fixup_filtercomposite_add_destructuring
- emit_cfg_loop chart-re-read injection

Design: docs/plans/2026-05-25-phase-7d-design.md
EOF
)"
```

- [ ] **Step 3: Confirm.**

```bash
git log --oneline -2
```

Expected: top line is the new commit.

---

## Pre-Commit-2 GATE: read the counter output

**STOP. Do not proceed to Task 2.1 until the following is done:**

1. Re-run `c-repair-coverage.t` and capture the totals block:
   ```bash
   $HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-repair-coverage.t 2>&1 | grep -A 20 "Repair counter totals"
   ```

2. Build a deletion-decision table. For each repair name reported (and any not reported = zero fires):

   | Repair | Fires | Decision (delete / keep+port / keep+document) | Notes |
   |---|---|---|---|
   | `repair_stale_merge` | N | ... | ... |
   | `is_stale_merge_detected` | N | ... | ... |
   | `list_destr_pred_entry` | N | ... | ... |
   | (etc.) |

   For each zero-fire row: **delete**. For each non-zero-fire row: investigate. The investigation question: does the schedule path produce the same output that the repair was patching? If yes, port the repair. If no, the repair was patching a symptom whose cause is now fixed elsewhere — delete.

3. Save the decision table into a scratch note. Commit 2's message will reference it.

The remainder of Commit 2 (the migration tasks below) assumes the decision table has been built. The "delete repairs" task (Task 2.10) consumes it.

---

## COMMIT 2 — schedule-driven body emission migration

### Task 2.1: Document the cfg_lookup → schedule_data cross-reference

**Files:** none modified; produces a table for the commit message.

The spec's Risk #1 requires this before any code change. Map every `_cfg_lookup{refaddr(...)}` read site in EmitHelpers to the equivalent schedule_data field.

- [ ] **Step 1: List the cfg_lookup read sites.**

```bash
grep -n '_cfg_lookup{' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm
```

Expected matches (verified at HEAD of branch): lines 574, 603, 684, 734, 776, 1305 (approximate).

- [ ] **Step 2: For each site, capture which cfg_state keys it reads.**

For each match, read 20 lines of surrounding context and list every `$state->{KEY}` access. Common keys: `if_node`, `then_stmts`, `else_stmts`, `loop`, `body_stmts`, `try_node`, `try_stmts`, `catch_stmts`, `catch_var`, `iterator`, `list`, `for_init`, `for_step`, `loop_jump`.

- [ ] **Step 3: For each cfg_state key, identify the schedule_data equivalent.**

Read `lib/Chalk/IR/Scheduler/EagerPinning.pm` for the `schedule_data` shapes attached to nodes. Search for typed `EagerPinning::If`, `EagerPinning::Loop`, `EagerPinning::TryCatch` classes (likely sub-packages under `Chalk::Scheduler::EagerPinning::*`):

```bash
grep -n '^class \|field ' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/IR/Scheduler/EagerPinning.pm | head -40
```

Build the table:

| EmitHelpers site (line) | cfg_state keys read | schedule_data field used | Replacement notes |
|---|---|---|---|
| `_has_early_return` (574) | `if_node`, `then_stmts`, `else_stmts`, `loop`, `body_stmts` | none — flat schedule walk replaces recursion | Per correctness invariant; branch-internal stmts appear as 'stmt' items inline |
| `_body_contains_return` (603) | same | same | same |
| `_collect_var_decls` (684) | `then_stmts`, `else_stmts`, `body_stmts`, `try_stmts`, `catch_stmts`, **`iterator`** | iterator: `block_open(form='foreach')->node->schedule_data->iterator` | flat walk + block_open hook |
| `_collect_all_var_refs` (753 or 776) | similar to 684 | similar | similar |
| `_emit_stmt` cfg dispatch (1305) | `if_node`, `loop_jump`, `then_stmts`, `else_stmts`, `loop`, `try_node` | UNREACHABLE in schedule path — control-flow nodes appear only as `block_open`/`block_close`, not as 'stmt' items | this entire dispatch is dead post-migration (Task 2.6 verifies); 7g deletes |

- [ ] **Step 4: Save the table.**

The table goes into the Commit 2 message body OR into `docs/plans/2026-05-25-phase-7d-schedule-data-coverage.md`. If any cfg_state key has NO schedule_data equivalent, STOP — that means the migration requires scheduler changes that are out of 7d's scope. Escalate.

If all cfg_state keys map cleanly, proceed to Task 2.2.

---

### Task 2.2: Add the schedule-walking helpers to C.pm (TDD)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (add new methods)
- Create: `t/bootstrap/c-schedule-walker.t`

- [ ] **Step 1: Write the failing test for `_emit_scheduled_c_body`.**

Create `t/bootstrap/c-schedule-walker.t`:

```perl
# ABOUTME: Phase 7d unit tests for Target::C's schedule walker.
# ABOUTME: Exercises _emit_scheduled_c_body and _emit_c_schedule_item against minimal fixtures.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::MOP::Method;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Constant;
use Chalk::Bootstrap::Perl::Target::C;

# Build a minimal MOP::Method whose body is a single Return of a Constant.
my $factory = Chalk::IR::NodeFactory->new;
my $graph   = Chalk::IR::Graph->new;

my $mop = Chalk::MOP->new;
my $mop_class = $mop->declare_class('Test::ScheduleWalker');

# Construct the IR: Start -> Return(Constant('hello'))
my $start = $factory->make('Start');
$graph->merge($start);
my $value = $factory->make('Constant', const_type => 'string', value => 'hello');
$graph->merge($value);
my $ret = $factory->make_cfg('Return', inputs => [$start, $value]);
$graph->merge($ret);

my $method = $mop_class->declare_method('greet',
    params => ['$self'],
    body   => [$ret],
    graph  => $graph,
);

my $target = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => 'Test::ScheduleWalker',
);
$target->_set_current_slug('schedulewalker');

# _emit_scheduled_c_body should return an arrayref of C lines.
my $lines = $target->_emit_scheduled_c_body($method);
isa_ok($lines, 'ARRAY', '_emit_scheduled_c_body returns an arrayref');

# The body should contain the constant value somewhere.
my $body_text = join("\n", $lines->@*);
like($body_text, qr/hello/, 'body C contains the constant value');

done_testing();
```

- [ ] **Step 2: Run to confirm failure.**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-schedule-walker.t 2>&1 | tail -10
```

Expected: FAIL with `Can't locate object method "_emit_scheduled_c_body"`.

- [ ] **Step 3: Add `_emit_scheduled_c_body` to C.pm.**

Edit `lib/Chalk/Bootstrap/Perl/Target/C.pm`. Add the `use` line near the top with the other `use Chalk::IR::*` lines:

```perl
use Chalk::IR::Scheduler::EagerPinning;
```

Add the new method anywhere appropriate in the class body (suggested: just before the existing `_emit_method` at line 98):

```perl
    # Build the schedule for a MOP::Method or MOP::Sub and walk
    # the items into C body lines. Mirrors Target::Perl's
    # _emit_scheduled_body (Perl.pm:234-244). Returns an arrayref
    # of body lines (NOT a joined string); the caller assembles
    # the helper template around it.
    method _emit_scheduled_c_body($method) {
        my $scheduler = Chalk::IR::Scheduler::EagerPinning->new;
        my $schedule  = $scheduler->schedule($method);

        my @lines;
        my $indent = 0;
        my %declared_vars;
        for my $item ($schedule->items->@*) {
            $self->_emit_c_schedule_item(
                $item, \@lines, \$indent, $scheduler, \%declared_vars
            );
        }
        return \@lines;
    }
```

- [ ] **Step 4: Add a stub `_emit_c_schedule_item` so the test can run.**

```perl
    # Emit a single Schedule Item into the C lines accumulator.
    # Mirrors Target::Perl's _emit_schedule_item (Perl.pm:251-326)
    # but produces C syntax. The 'stmt' case dispatches to
    # _emit_stmt for ordinary statements; structural-marker
    # items (block_open, block_close, else, elsif, catch) emit
    # the C-syntax head or tail.
    method _emit_c_schedule_item($item, $lines, $indent_ref, $scheduler, $declared_vars) {
        my $kind = $item->kind;
        if ($kind eq 'stmt') {
            my $code = $self->_emit_stmt($item->node, $declared_vars, false);
            return unless defined $code;
            for my $l (split /\n/, $code) {
                push $lines->@*, ('    ' x $$indent_ref) . $l;
            }
        } elsif ($kind eq 'block_open') {
            my $head = $self->_emit_c_block_open_head($item);
            push $lines->@*, ('    ' x $$indent_ref) . $head;
            $$indent_ref++;
        } elsif ($kind eq 'block_close') {
            $$indent_ref-- if $$indent_ref > 0;
            my $tail = $self->_emit_c_block_close_tail($item);
            push $lines->@*, ('    ' x $$indent_ref) . $tail;
        } elsif ($kind eq 'else') {
            $$indent_ref-- if $$indent_ref > 0;
            push $lines->@*, ('    ' x $$indent_ref) . '} else {';
            $$indent_ref++;
        } elsif ($kind eq 'elsif') {
            $$indent_ref-- if $$indent_ref > 0;
            push $lines->@*, ('    ' x $$indent_ref)
                . '} else ' . $self->_emit_c_if_head($item->node);
            $$indent_ref++;
        } elsif ($kind eq 'catch') {
            $$indent_ref-- if $$indent_ref > 0;
            push $lines->@*, ('    ' x $$indent_ref)
                . '} ' . $self->_emit_c_catch_head($item);
            $$indent_ref++;
        } else {
            die "Unknown Schedule Item kind: $kind";
        }
    }

    # Stub head emitters — implemented incrementally in subsequent tasks.
    method _emit_c_block_open_head($item) {
        my $form = $item->form // '';
        if ($form eq 'if')      { return $self->_emit_c_if_head($item->node); }
        if ($form eq 'while')   { return $self->_emit_c_while_head($item->node); }
        if ($form eq 'foreach') { return $self->_emit_c_foreach_head($item->node); }
        if ($form eq 'for')     { return $self->_emit_c_for_head($item->node); }
        if ($form eq 'try')     { return 'JMPENV_PUSH(rs); switch (rs) { case 0: {'; }
        die "Unknown block_open form: $form";
    }

    method _emit_c_block_close_tail($item) {
        my $form = $item->form // '';
        # For foreach: TWO close braces (one for the for-loop, one
        # for the AV/iterator scope). See design Risk #2 for rationale.
        return '}}' if $form eq 'foreach';
        # For try: switch+JMPENV_POP epilogue
        return '} break; default: { /* exception */ } } JMPENV_POP;' if $form eq 'try';
        return '}';
    }

    method _emit_c_if_head($if_node) {
        my $cond = $if_node->inputs->[1];
        my $cond_expr = $self->_emit_node($cond);
        return "if (SvTRUE($cond_expr)) {";
    }

    method _emit_c_while_head($loop) {
        my $cond = $self->_loop_condition_c($loop);
        return "while (SvTRUE($cond)) {";
    }

    method _emit_c_foreach_head($loop) {
        my $sd = $loop->schedule_data;
        my $iter = $sd->iterator;
        my $list = $sd->list;
        my $iter_name = ref($iter) ? $iter->value : "$iter";
        $iter_name =~ s/^[\$\@\%]//;
        # The implementer MUST verify the actual shape of $sd->list
        # before relying on this branch. Grep lib/Chalk/Bootstrap/Perl/Actions.pm
        # for `schedule_data(EagerPinning::Loop->new(...))` to see what the
        # parser action passes. If $list is always a single node, drop
        # the arrayref branch. If sometimes an arrayref (matching the
        # legacy emit_cfg_loop foreach pattern), keep both.
        my $list_expr = ref($list) eq 'ARRAY'
            ? '(' . join(', ', map { $self->_emit_node($_) } $list->@*) . ')'
            : $self->_emit_node($list);
        # Outer scope holds the AV; for-loop iterates.
        return "{ AV *_iter_av = (AV*)SvRV($list_expr); for (IV _i = 0; _i <= av_len(_iter_av); _i++) { SV *${iter_name}_sv = *av_fetch(_iter_av, _i, 0);";
    }

    method _emit_c_for_head($loop) {
        my $sd = $loop->schedule_data;
        my $init = $sd->for_init;
        my $cond = $self->_loop_condition_c($loop);
        my $step = $sd->for_step;
        my $init_str = defined $init ? $self->_emit_node($init) : '';
        my $step_str = defined $step ? $self->_emit_node($step) : '';
        return "for ($init_str; SvTRUE($cond); $step_str) {";
    }

    method _emit_c_catch_head($item) {
        my $try = $item->node;
        my $sd  = $try->schedule_data;
        my $var = $sd->catch_var;
        my $var_name = ref($var) ? $var->value : "$var";
        $var_name =~ s/^[\$\@\%]//;
        # Catch entry: error message lives in ERRSV.
        # IMPLEMENTATION NOTE: this is a sketch. The legacy try/catch
        # in EmitHelpers.pm:1080+ (search for `emit_cfg_try_catch`)
        # has substantially more JMPENV_PUSH/JMPENV_POP boilerplate
        # than this one-line head. Before Commit 2 lands, port the
        # full legacy machinery: the JMPENV setup goes in the
        # `try` block_open head, the case-1 dispatch + ERRSV access
        # goes here, the POP goes in the `try` block_close tail.
        # The test that exercises this is the catch path of a real
        # corpus class — find one via `grep -l 'try {' lib/Chalk/`
        # and ensure its emission still works.
        return "} break; case 1: { SV *${var_name}_sv = ERRSV;";
    }

    # Walk a Loop's controlled If to extract its condition as a C expr.
    # MIRRORS Perl.pm:429-437 exactly: the controlled If is a CONSUMER of
    # the Loop (Loop.inputs[0] = entry control; Loop.inputs[1] = backedge,
    # set later via set_backedge_ctrl — NEITHER is an If node).
    method _loop_condition_c($loop) {
        for my $c ($loop->consumers->@*) {
            return $self->_emit_node($c->inputs->[1])
                if blessed($c) && $c isa Chalk::IR::Node::If;
        }
        return '';
    }
```

- [ ] **Step 5: Run the test to confirm it passes.**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-schedule-walker.t 2>&1 | tail -10
```

Expected: PASS — the simple Return-of-Constant case routes through the 'stmt' case and emits via `_emit_stmt`.

The catch/foreach/for/while head emitters are stubs that produce best-effort C; they're verified more rigorously by Task 2.5+ when real corpus methods exercise them. The minimum-viable check at this stage is that `_emit_scheduled_c_body` runs end-to-end without errors.

- [ ] **Step 6: Do NOT commit yet.** Commit 2 lands at the end of this batch.

---

### Task 2.3: Migrate the 6 schedule-substrate analysis helpers (TDD)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (helpers at lines 542, 571, 599, 624, 680, 753)
- Create: `t/bootstrap/c-analysis-helpers-schedule.t`

These 6 helpers take `$schedule` post-migration: `_is_complex_method`, `_has_early_return`, `_body_contains_return`, `_body_contains_bare_return`, `_collect_var_decls`, `_collect_all_var_refs`.

- [ ] **Step 1: Write tests for each helper's schedule-substrate signature.**

Create `t/bootstrap/c-analysis-helpers-schedule.t`:

```perl
# ABOUTME: Phase 7d unit tests for analysis helpers rewritten to consume Schedule.
# ABOUTME: Verifies the 6 schedule-substrate helpers produce equivalent results to legacy.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Schedule;
use Chalk::IR::Schedule::Item;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::VarDecl;
use Chalk::Bootstrap::Perl::Target::C;

my $factory = Chalk::IR::NodeFactory->new;
my $target  = Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Test::H');

# Helper: build a schedule from a list of stmt-node items
sub schedule_of(@nodes) {
    return Chalk::IR::Schedule->new(items => [
        map { Chalk::IR::Schedule::Item->new(kind => 'stmt', node => $_) } @nodes
    ]);
}

# Test _body_contains_return
{
    my $start = $factory->make('Start');
    my $val = $factory->make('Constant', const_type => 'string', value => 'x');
    my $ret = $factory->make_cfg('Return', inputs => [$start, $val]);

    my $sched_with_return = schedule_of($ret);
    my $sched_no_return = schedule_of($val);

    ok($target->_body_contains_return($sched_with_return),
       '_body_contains_return: schedule with Return returns true');
    ok(!$target->_body_contains_return($sched_no_return),
       '_body_contains_return: schedule without Return returns false');
}

# Test _has_early_return: a Return that is NOT the trailing
# synthetic-Return counts; the trailing synthetic-Return does NOT.
{
    my $start = $factory->make('Start');
    my $val = $factory->make('Constant', const_type => 'string', value => 'x');
    my $ret_early = $factory->make_cfg('Return', inputs => [$start, $val]);
    my $val2 = $factory->make('Constant', const_type => 'string', value => 'y');

    my $sched_early = schedule_of($ret_early, $val2);
    ok($target->_has_early_return($sched_early),
       '_has_early_return: non-trailing Return counts');

    my $sched_only_trailing = schedule_of($val, $ret_early);
    # The trailing Return is the LAST stmt; doesn't count as early.
    ok(!$target->_has_early_return($sched_only_trailing),
       '_has_early_return: trailing Return does not count as early');
}

# Test _collect_var_decls registers each VarDecl
{
    my $name = $factory->make('Constant', const_type => 'variable', value => '$foo');
    my $vd = $factory->make_cfg('VarDecl', name => $name, init => undef, inputs => [$factory->make('Start')]);
    my $sched = schedule_of($vd);
    my %declared;
    $target->_collect_var_decls($sched, \%declared);
    ok(exists $declared{foo}, '_collect_var_decls registers foo from VarDecl');
}

# Test _is_complex_method: empty / single-stmt / multi-stmt
{
    my $val = $factory->make('Constant', const_type => 'string', value => '1');
    my $empty = Chalk::IR::Schedule->new(items => []);
    my $single = schedule_of($val);
    my $multi = schedule_of($val, $val);

    ok(!$target->_is_complex_method($empty),  '_is_complex_method: empty is not complex');
    ok(!$target->_is_complex_method($single), '_is_complex_method: single stmt is not complex');
    ok($target->_is_complex_method($multi),   '_is_complex_method: multi stmt is complex');
}

done_testing();
```

- [ ] **Step 2: Run to confirm failures.**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-analysis-helpers-schedule.t 2>&1 | tail -20
```

Expected: most tests fail because the helpers still take `$body` arrayref / `$method_decl`, not `$schedule`. Some may pass by accident if the helper's existing logic happens to also work on Schedule objects (unlikely but possible).

- [ ] **Step 3: Rewrite the 6 helpers in EmitHelpers.pm.**

For each helper, replace the existing body with a schedule-walking version. The general pattern:

```perl
    method HELPER_NAME($schedule, $maybe_other_args) {
        for my $item ($schedule->items->@*) {
            next unless $item->kind eq 'stmt';
            my $node = $item->node;
            # ... per-helper logic against $node ...
        }
        return ...;
    }
```

Concrete rewrites (replace each method's body; keep the same name):

**`_is_complex_method` (line 542)** — currently takes `$method_decl`. New shape:

```perl
    method _is_complex_method($schedule) {
        my @stmts = grep { $_->kind eq 'stmt' } $schedule->items->@*;
        return false if @stmts <= 1;
        # If there are block_open items, it's structured control flow.
        return true if grep { $_->kind eq 'block_open' } $schedule->items->@*;
        return true;  # multi-stmt without blocks is still complex
    }
```

**`_has_early_return` (line 571)** — currently takes `$nodes` arrayref. New shape:

```perl
    method _has_early_return($schedule) {
        # Walk all 'stmt' items EXCEPT the terminal synthetic-Return.
        # Per the design doc's correctness invariant, branch-internal
        # Returns appear as their own 'stmt' items in the flat sequence;
        # those ARE early returns that need the xsreturn: label.
        my @items = $schedule->items->@*;
        return false unless @items;

        # Identify the terminal synthetic-Return (if any) to exclude.
        my $last = $items[-1];
        my $is_terminal_synthetic = $last->kind eq 'stmt'
            && $last->node isa Chalk::IR::Node::Return
            && $last->node->can('synthetic')
            && $last->node->synthetic;

        my $end_idx = $is_terminal_synthetic ? $#items - 1 : $#items;
        # The LAST non-terminal-synthetic 'stmt' item is also not
        # counted as an early return — it's the normal trailing return.
        # We want: any 'stmt' before the last 'stmt' that is a
        # non-synthetic Return.
        my @stmt_idx;
        for my $i (0 .. $end_idx) {
            push @stmt_idx, $i if $items[$i]->kind eq 'stmt';
        }
        return false if @stmt_idx <= 1;
        pop @stmt_idx;  # exclude the last stmt
        for my $i (@stmt_idx) {
            my $node = $items[$i]->node;
            return true if $node isa Chalk::IR::Node::Return
                        && !($node->can('synthetic') && $node->synthetic);
        }
        return false;
    }
```

**`_body_contains_return` (line 599)** — currently takes `$body` arrayref. New shape:

```perl
    method _body_contains_return($schedule) {
        for my $item ($schedule->items->@*) {
            next unless $item->kind eq 'stmt';
            my $node = $item->node;
            return true if $node isa Chalk::IR::Node::Return;
        }
        return false;
    }
```

**`_body_contains_bare_return` (line 624)** — currently takes `$body`. New shape:

```perl
    method _body_contains_bare_return($schedule) {
        for my $item ($schedule->items->@*) {
            next unless $item->kind eq 'stmt';
            my $node = $item->node;
            next unless $node isa Chalk::IR::Node::Return;
            my $val = $node->inputs->[1];
            return true unless defined $val;
        }
        return false;
    }
```

**`_collect_var_decls` (line 680)** — currently takes `($nodes, $declared_vars)`. New shape:

```perl
    method _collect_var_decls($schedule, $declared_vars) {
        for my $item ($schedule->items->@*) {
            if ($item->kind eq 'stmt') {
                my $node = $item->node;
                if ($node isa Chalk::IR::Node::VarDecl) {
                    my $name = $node->name;
                    my $vname = ref($name) ? $name->value : "$name";
                    $vname =~ s/^[\$\@\%]//;
                    $declared_vars->{$vname} = true;
                }
            } elsif ($item->kind eq 'block_open' && ($item->form // '') eq 'foreach') {
                my $iter = $item->node->schedule_data->iterator;
                my $iname = ref($iter) ? $iter->value : "$iter";
                $iname =~ s/^[\$\@\%]//;
                $declared_vars->{$iname} = true;
            } elsif ($item->kind eq 'catch') {
                my $var = $item->node->schedule_data->catch_var;
                my $cname = ref($var) ? $var->value : "$var";
                $cname =~ s/^[\$\@\%]//;
                $declared_vars->{$cname} = true;
            }
        }
        return;
    }
```

**`_collect_all_var_refs` (line 753)** — currently takes `($nodes, $declared_vars)`. New shape:

```perl
    method _collect_all_var_refs($schedule, $declared_vars) {
        my $walk;
        $walk = sub ($node) {
            return unless defined $node && ref($node);
            if ($node isa Chalk::IR::Node::Constant
                    && ($node->const_type // '') eq 'variable') {
                my $name = $node->value;
                $name =~ s/^[\$\@\%]//;
                $declared_vars->{$name} //= true;
            }
            if ($node isa Chalk::IR::Node) {
                for my $input ($node->inputs->@*) {
                    if (ref($input) eq 'ARRAY') {
                        $walk->($_) for $input->@*;
                    } else {
                        $walk->($input);
                    }
                }
            }
        };
        for my $item ($schedule->items->@*) {
            next unless $item->kind eq 'stmt';
            $walk->($item->node);
        }
        # Also walk foreach iterator schedule_data:
        for my $item ($schedule->items->@*) {
            if ($item->kind eq 'block_open' && ($item->form // '') eq 'foreach') {
                my $iter = $item->node->schedule_data->iterator;
                $walk->($iter) if ref($iter);
            }
        }
        return;
    }
```

- [ ] **Step 4: Run the new test to confirm it passes.**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-analysis-helpers-schedule.t 2>&1 | tail -15
```

Expected: all assertions PASS.

- [ ] **Step 5: Do NOT run `bnf-target-c.t` yet** — `_emit_method` and `_emit_complex_method` still call the old helpers with arrayref arguments, which will now fail. Tasks 2.4-2.6 fix the callers.

---

### Task 2.4: Rewrite `_emit_method` with schedule-driven simple-body shortcuts

**SEQUENCING NOTE:** After Task 2.3 rewrites the analysis helpers to take `$schedule`, the existing `_emit_method` / `_emit_complex_method` (which still pass `$body` arrayref to those helpers) will fail. Do NOT run `bnf-target-c.t` between Task 2.3 and Task 2.5. The migration is not back to a green state until Task 2.5 completes. The test gate for that intermediate state is Task 2.4's own narrow test (c-simple-body-shortcuts.t), which exercises only the simple-body shortcut path and doesn't invoke the analysis helpers.


**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (lines 98-204)
- Create: `t/bootstrap/c-simple-body-shortcuts.t`

- [ ] **Step 1: Write the failing test.**

Create `t/bootstrap/c-simple-body-shortcuts.t`:

```perl
# ABOUTME: Phase 7d test that simple-body shortcuts fire from the schedule path.
# ABOUTME: Verifies single-Return-of-Constant emits `return newSViv(1)`, not the complex-method template.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;

my $factory = Chalk::IR::NodeFactory->new;
my $graph   = Chalk::IR::Graph->new;
my $mop     = Chalk::MOP->new;
my $cls     = $mop->declare_class('Test::SimpleBody');

# Build IR: Start -> Return(Constant('42'))
# NOTE: use 42 not 1 — the simple-return path maps '1' to &PL_sv_yes
# and '0' to &PL_sv_no per legacy C.pm:129-132. Use a generic
# integer like 42 to exercise the `newSViv($raw)` path.
my $start = $factory->make('Start');
$graph->merge($start);
my $val = $factory->make('Constant', const_type => 'string', value => '42');
$graph->merge($val);
my $ret = $factory->make_cfg('Return', inputs => [$start, $val]);
$graph->merge($ret);

my $method = $cls->declare_method('answer',
    params => ['$self'],
    body   => [$ret],
    graph  => $graph,
);

my $target = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => 'Test::SimpleBody',
);
$target->_set_current_slug('simplebody');

my $result = $target->_emit_method($method);
ok(defined $result, '_emit_method returns defined result');
ok(ref($result) eq 'HASH' && defined $result->{helper}, 'result has helper key');

my $helper = join("\n", $result->{helper}->@*);

# Simple-body shortcut for integer-42 should emit `return newSViv(42);` directly.
like($helper, qr/newSViv\(42\)/, 'integer literal 42 uses newSViv');
unlike($helper, qr/SV \*retval = NULL/, 'simple body does NOT use RETVAL pattern');

# Bonus: verify the special-case for '1' → &PL_sv_yes still works.
{
    my $val_one = $factory->make('Constant', const_type => 'string', value => '1');
    $graph->merge($val_one);
    my $ret_one = $factory->make_cfg('Return', inputs => [$start, $val_one]);
    $graph->merge($ret_one);
    my $method_one = $cls->declare_method('one',
        params => ['$self'],
        body   => [$ret_one],
        graph  => $graph,
    );
    my $result_one = $target->_emit_method($method_one);
    my $helper_one = join("\n", $result_one->{helper}->@*);
    like($helper_one, qr/PL_sv_yes/, "integer '1' maps to &PL_sv_yes (legacy parity)");
}

done_testing();
```

- [ ] **Step 2: Run to confirm failure.**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-simple-body-shortcuts.t 2>&1 | tail -10
```

Expected: may fail because the legacy `_emit_method` reads `$method->body` arrayref; with the legacy helpers now schedule-only after Task 2.3, the legacy `_emit_method` is broken. The test surfaces this.

- [ ] **Step 3: Rewrite `_emit_method`.**

Edit `lib/Chalk/Bootstrap/Perl/Target/C.pm`. Find `_emit_method` (line 98) and replace the ENTIRE method (lines 98-204) with:

```perl
    method _emit_method($method) {
        my $name = $method->name;
        my $factory = Chalk::IR::NodeFactory->new();
        my $params = [
            map { $factory->make('Constant', const_type => 'variable', value => $_) }
                $method->params->@*
        ];
        my $func_name = "${\  $self->_get_current_slug()}_${name}";

        my $scheduler = Chalk::IR::Scheduler::EagerPinning->new;
        my $schedule  = $scheduler->schedule($method);

        # Simple-body shortcuts (schedule-driven).
        my @items = $schedule->items->@*;

        # Empty body shortcut.
        if (@items == 0) {
            return $self->_emit_simple_empty_method($func_name, $params);
        }

        # Single-stmt Return-of-Constant or Return-of-Interpolate shortcut.
        if (@items == 1 && $items[0]->kind eq 'stmt') {
            my $node = $items[0]->node;
            if ($node isa Chalk::IR::Node::Return) {
                my $value = $node->inputs->[1];
                if (defined $value && $value isa Chalk::IR::Node::Interpolate) {
                    return $self->_emit_interp_return($name, $value);
                }
                if (defined $value && $value isa Chalk::IR::Node::Constant
                        && ($value->const_type // '') ne 'variable'
                        && $value->value !~ /^[\$\@\%]/) {
                    return $self->_emit_simple_return_method(
                        $func_name, $params, $value
                    );
                }
            }
            if ($node isa Chalk::IR::Node::Unwind) {
                return $self->_emit_simple_die_method(
                    $func_name, $params, $node
                );
            }
        }

        my $return_type = $method->return_type;
        return $self->_emit_complex_method(
            $name, $params, $schedule, $scheduler, $return_type
        );
    }

    # Empty method body: emit `void NAME(pTHX_ SV *self) { /* empty */ }`.
    method _emit_simple_empty_method($func_name, $params) {
        my @helper;
        push @helper, "void ${func_name}(pTHX_ SV *self) {";
        push @helper, "    PERL_UNUSED_ARG(self);";
        push @helper, "    /* empty */";
        push @helper, "}";
        push @_exported_functions, {
            name        => $func_name,
            return_type => 'void',
            params      => 'pTHX_ SV *self',
        };
        return { helper => \@helper };
    }

    # Single-stmt Return-of-Constant: emit one-liner `return newSViv(N);`
    # (or &PL_sv_yes for true, etc.).
    method _emit_simple_return_method($func_name, $params, $value) {
        my $str = $self->_escape_c_string($value->value);
        my $c_expr = "newSVpvs(\"$str\")";
        my $raw = $value->value;
        if ($raw eq '1' || $raw eq 'true') {
            $c_expr = '&PL_sv_yes';
        } elsif ($raw eq '0' || $raw eq 'false' || $raw eq '') {
            $c_expr = '&PL_sv_no';
        } elsif ($raw eq 'undef') {
            $c_expr = '&PL_sv_undef';
        } elsif ($raw =~ /\A-?\d+\z/) {
            $c_expr = "newSViv($raw)";
        }
        my @c_params = ('SV *self');
        for my $p ($params->@*) {
            my $pname = $p->value;
            $pname =~ s/^\$//;
            push @c_params, "SV *$pname";
        }
        my @helper;
        push @helper, "SV * ${func_name}(pTHX_ " . join(', ', @c_params) . ") {";
        for my $p (@c_params) {
            push @helper, "    PERL_UNUSED_ARG(${\($p =~ s/^SV \*//r)});"
                unless $p =~ /^SV \*self$/;
        }
        push @helper, "    return $c_expr;";
        push @helper, "}";
        push @_exported_functions, {
            name        => $func_name,
            return_type => 'SV *',
            params      => 'pTHX_ ' . join(', ', @c_params),
        };
        return { helper => \@helper };
    }

    # Single-stmt Unwind (die): emit `croak("MSG");`.
    method _emit_simple_die_method($func_name, $params, $node) {
        my $args = $node->inputs->[0];
        my $msg = '';
        if (ref($args) eq 'ARRAY' && $args->@*) {
            $msg = $self->_escape_c_string($args->[0]->value);
        }
        my @c_params = ('SV *self');
        for my $p ($params->@*) {
            my $pname = $p->value;
            $pname =~ s/^\$//;
            push @c_params, "SV *$pname";
        }
        my @helper;
        push @helper, "void ${func_name}(pTHX_ " . join(', ', @c_params) . ") {";
        push @helper, "    croak(\"%s\", \"$msg\");";
        push @helper, "}";
        push @_exported_functions, {
            name        => $func_name,
            return_type => 'void',
            params      => 'pTHX_ ' . join(', ', @c_params),
        };
        return { helper => \@helper };
    }
```

- [ ] **Step 4: Run the test.**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-simple-body-shortcuts.t 2>&1 | tail -10
```

Expected: PASS — the simple integer-1 return goes through `_emit_simple_return_method` and emits `return newSViv(1);`.

- [ ] **Step 5: Do NOT run `bnf-target-c.t` yet.** `_emit_complex_method` still expects `$body` arrayref; Task 2.5 fixes it.

---

### Task 2.5: Rewrite `_emit_complex_method` to consume `$schedule`

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (lines 207-334)

- [ ] **Step 1: Replace the method body.**

Find `method _emit_complex_method($name, $params, $body, $ir_return_type = undef)` (line 207). Change the signature to accept `$schedule` and `$scheduler`. Replace the entire method (lines 207-334) with:

```perl
    # Emit a multi-statement method body as a C helper + XSUB wrapper.
    # Post-Phase-7d: consumes a Chalk::IR::Schedule produced by
    # Chalk::IR::Scheduler::EagerPinning. The wrapper logic (param
    # decls, %declared_vars, retval handling, function template) is
    # unchanged; only the inner body loop swaps from
    # `for my $stmt ($body->@*)` to `_emit_scheduled_c_body($method)`-
    # equivalent (here, the schedule is already built and passed in).
    method _emit_complex_method($name, $params, $schedule, $scheduler, $ir_return_type = undef) {
        my @code;

        # Find the last 'stmt' item to drive last-stmt analyses.
        my @stmt_items = grep { $_->kind eq 'stmt' } $schedule->items->@*;
        my $last_stmt = @stmt_items ? $stmt_items[-1] : undef;
        my $last_node = defined $last_stmt ? $last_stmt->node : undef;

        my $last_is_return = (defined $last_node
            && $last_node isa Chalk::IR::Node::Return);
        my $body_has_returns = $self->_body_contains_return($schedule);
        my $single_stmt_return = (!$last_is_return
            && scalar(@stmt_items) == 1
            && defined $last_node
            && $self->_is_single_stmt_return_expr($last_node));
        my $tail_expr_return = (!$last_is_return
            && defined $last_node
            && ($self->_is_unambiguous_value_expr($last_node)
                || ($body_has_returns && $self->_is_bare_return_expr($last_node)))
            );
        my $heuristic_has_return = $last_is_return || $tail_expr_return
               || $single_stmt_return || $body_has_returns;
        my $has_return;
        if (defined $ir_return_type && $ir_return_type eq 'Void'
                && ($last_is_return || $body_has_returns)) {
            $has_return = true;
            $ir_return_type = 'Any';
        } elsif (defined $ir_return_type) {
            $has_return = $ir_return_type ne 'Void';
        } else {
            $has_return = $heuristic_has_return;
        }

        my %declared_vars;

        my @xs_params = ('SV *self');
        for my $p ($params->@*) {
            my $pname = $p->value;
            $pname =~ s/^[\$\@\%]//;
            push @xs_params, "SV *$pname";
            $declared_vars{"param:$pname"} = true;
        }

        $self->_collect_var_decls($schedule, \%declared_vars);
        $self->_collect_all_var_refs($schedule, \%declared_vars);

        my $has_early_return = $self->_has_early_return($schedule);

        my $prev_return_context = $self->_get_return_context();
        $self->_set_return_context($has_return);

        # Body emission: walk schedule items into @code lines.
        my $indent = 0;
        for my $item ($schedule->items->@*) {
            $self->_emit_c_schedule_item(
                $item, \@code, \$indent, $scheduler, \%declared_vars
            );
        }

        # Retval tail rewriting: if the last code line is an expression
        # (no trailing semicolon stripping), wrap it as `retval = EXPR;`.
        if (!$last_is_return && @code) {
            my $last_code = $code[-1];
            if ($last_code =~ /\n/) {
                my @parts = split(/\n/, $last_code);
                my $final_line = pop @parts;
                $code[-1] = join("\n", @parts);
                if ($final_line =~ s/;\s*$//) {
                    if ($final_line =~ /^(?:sv_setsv|hv_clear|av_clear)\b/) {
                        push @code, "$final_line;";
                    } else {
                        my $wrapped = $self->_wrap_retval($final_line);
                        push @code, "retval = $wrapped;";
                    }
                } else {
                    push @code, $final_line;
                }
            } else {
                if ($last_code =~ s/;\s*$//) {
                    if ($last_code =~ /^(?:sv_setsv|hv_clear|av_clear)\b/) {
                        $code[-1] = "$last_code;";
                    } else {
                        my $wrapped = $self->_wrap_retval($last_code);
                        $code[-1] = "retval = $wrapped;";
                    }
                }
            }
        }

        $self->_set_return_context($prev_return_context);

        my @helper;
        my $func_name = "${\  $self->_get_current_slug()}_${name}";
        my $c_ret_type = $has_return ? $self->_xs_c_type_for($ir_return_type) : 'void';
        push @helper, "$c_ret_type ${func_name}(pTHX_ " . join(', ', @xs_params) . ") {";

        if ($has_return) {
            push @helper, '    SV *retval = NULL;';
        }
        for my $var (sort keys %declared_vars) {
            next if $var eq 'hash';
            next if $var =~ /^param:/;
            push @helper, "    SV *${var}_sv = NULL;";
        }

        for my $stmt (@code) {
            my $rewritten = $stmt;
            $rewritten =~ s/\bRETVAL\b/retval/g;
            $rewritten =~ s/\breturn\s*;/return \&PL_sv_undef;/g;
            for my $line (split /\n/, $rewritten) {
                push @helper, "    $line";
            }
        }

        if ($has_early_return) {
            push @helper, '    xsreturn:';
        }
        if ($has_return) {
            push @helper, '    return retval;';
        } elsif ($c_ret_type ne 'void') {
            push @helper, '    return &PL_sv_undef;';
        }
        push @helper, '}';

        push @_exported_functions, {
            name        => $func_name,
            return_type => $c_ret_type,
            params      => 'pTHX_ ' . join(', ', @xs_params),
        };

        return { helper => \@helper, returns => $has_return };
    }
```

The signature is now `($name, $params, $schedule, $scheduler, $ir_return_type)`. The body iteration uses `_emit_c_schedule_item` instead of `_emit_stmt` directly. Everything else (param plumbing, retval logic, function template) is preserved verbatim from the legacy code.

- [ ] **Step 2: Run the c-simple-body-shortcuts.t test again** (now `_emit_method` falls through to the new `_emit_complex_method` for non-simple bodies).

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-simple-body-shortcuts.t 2>&1 | tail -10
```

Expected: still PASS (the simple-body shortcut path was already wired).

- [ ] **Step 3: Run `bnf-target-c.t` for the first major integration check.**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -10
```

Expected: 178/178 PASS. If any tests fail, the migration has introduced a regression — investigate before proceeding to Task 2.6.

Common failure modes:
- `Can't locate object method "X" via package "Chalk::IR::Node::Y"` — schedule_data accessor missing; check Task 2.1's cross-reference table.
- Wrong C output (regex assertion fails) — schedule walker emits different text; cross-check against Target::Perl precedent.
- `Unknown block_open form: ...` — a form string from the scheduler that `_emit_c_block_open_head` doesn't dispatch on; add the case.

---

### Task 2.6: Rewrite `_emit_sub` with state save/restore + schedule (TDD)

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (lines 337-455 — full `_emit_sub` method)
- Modify: `lib/Chalk/Bootstrap/Perl/Target/C.pm` (the sub-emission loop in `_generate_c_files` around lines 1585-1604)
- Create: `t/bootstrap/c-sub-state-leak.t`

- [ ] **Step 1: Write the state-leak test.**

Create `t/bootstrap/c-sub-state-leak.t`:

```perl
# ABOUTME: Phase 7d test that _emit_sub's try/catch save/restore preserves state.
# ABOUTME: Verifies an exception during sub compilation does not leak _current_sub_name/_return_context.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;

my $factory = Chalk::IR::NodeFactory->new;
my $target = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => 'Test::SubStateLeak',
);
$target->_set_current_slug('substateleak');

# Verify initial state: empty sub name, false return context.
is($target->_get_current_sub_name, '', 'initial _current_sub_name is empty');

# Set a known prior state to test restore.
$target->_set_current_sub_name('prior_sub');
$target->_set_return_context(true);

# Build a deliberately-malformed MOP::Sub (graph has no schedule-able structure).
my $mop = Chalk::MOP->new;
my $cls = $mop->declare_class('Test::SubStateLeak');
my $broken_sub = $cls->declare_sub('broken',
    params => [],
    body   => [],
    graph  => Chalk::IR::Graph->new,  # empty graph; scheduler may handle or throw
);

# Try to emit. If it throws, that's expected; what matters is state restoration.
eval { $target->_emit_sub($broken_sub) };
# (The eval may or may not catch — depending on whether the broken sub
# triggers an exception. Either way, the test asserts state restoration.)

is($target->_get_current_sub_name, 'prior_sub',
   '_current_sub_name restored to prior value after emission attempt');
is($target->_get_return_context, true,
   '_return_context restored to prior value after emission attempt');

done_testing();
```

Note: this test relies on `_emit_sub` accepting a single `$sub` argument (MOP::Sub). If `_emit_sub` still has the legacy 3-arg signature, the test will fail at the call site — that's the trigger for Step 2.

- [ ] **Step 2: Run to confirm failure.**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-sub-state-leak.t 2>&1 | tail -10
```

Expected: FAIL — either signature mismatch or state-leak assertion fails.

- [ ] **Step 3: Rewrite `_emit_sub`.**

Edit `lib/Chalk/Bootstrap/Perl/Target/C.pm`. Find `method _emit_sub($name, $params, $body) {` (line 337). Replace the entire method (lines 337-455) with:

```perl
    # Emit a class-scope sub declaration as a static C helper function.
    # Post-Phase-7d: takes a MOP::Sub directly and builds its own
    # schedule. The try/catch save/restore wrapper for
    # _current_sub_name and _return_context is preserved — exceptions
    # during body compilation must not leak state into subsequent
    # method/sub compilation in the same class.
    method _emit_sub($sub) {
        my $name = $sub->name;
        my $params = $sub->params;

        # State save/restore: any exception below must not leak.
        my $prev_sub_name = $self->_get_current_sub_name();
        my $prev_return_context = $self->_get_return_context();
        $self->_set_current_sub_name($name);

        my $result;
        my $caught_error;
        try {
            my $scheduler = Chalk::IR::Scheduler::EagerPinning->new;
            my $schedule  = $scheduler->schedule($sub);

            # Simple-body shortcuts for subs (same shape as _emit_method).
            my @items = $schedule->items->@*;
            if (@items == 0) {
                $result = $self->_emit_simple_empty_sub($name);
            } elsif (@items == 1 && $items[0]->kind eq 'stmt') {
                my $node = $items[0]->node;
                if ($node isa Chalk::IR::Node::Return) {
                    my $value = $node->inputs->[1];
                    if (defined $value && $value isa Chalk::IR::Node::Constant
                            && ($value->const_type // '') ne 'variable'
                            && $value->value !~ /^[\$\@\%]/) {
                        $result = $self->_emit_simple_return_sub($name, $params, $value);
                    }
                }
                if (!defined $result && $node isa Chalk::IR::Node::Unwind) {
                    $result = $self->_emit_simple_die_sub($name, $params, $node);
                }
            }

            # Fall through to complex emission.
            if (!defined $result) {
                $result = $self->_emit_complex_sub_body(
                    $name, $params, $schedule, $scheduler
                );
            }
        } catch ($e) {
            $caught_error = $e;
        }

        # Always restore state, even if body compilation threw.
        $self->_set_current_sub_name($prev_sub_name);
        $self->_set_return_context($prev_return_context);

        die $caught_error if defined $caught_error;
        return $result;
    }

    # Empty sub: emit `static SV *NAME(pTHX) { return &PL_sv_undef; }`.
    method _emit_simple_empty_sub($name) {
        my @helper;
        my $helper_name = "${\  $self->_get_current_slug()}_${name}";
        push @helper, "static SV * $helper_name(pTHX) {";
        push @helper, '    return &PL_sv_undef;';
        push @helper, '}';
        return { helper => \@helper };
    }

    # Simple Return-of-Constant sub: emit static one-liner helper.
    method _emit_simple_return_sub($name, $params, $value) {
        my $str = $self->_escape_c_string($value->value);
        my $c_expr = "newSVpvs(\"$str\")";
        my $raw = $value->value;
        if ($raw eq '1' || $raw eq 'true') { $c_expr = '&PL_sv_yes'; }
        elsif ($raw eq '0' || $raw eq 'false' || $raw eq '') { $c_expr = '&PL_sv_no'; }
        elsif ($raw eq 'undef') { $c_expr = '&PL_sv_undef'; }
        elsif ($raw =~ /\A-?\d+\z/) { $c_expr = "newSViv($raw)"; }

        my @xs_params;
        for my $p ($params->@*) {
            my $pname = ref($p) ? $p->value : "$p";
            $pname =~ s/^[\$\@\%]//;
            push @xs_params, "SV *$pname";
        }
        my $helper_name = "${\  $self->_get_current_slug()}_${name}";
        my $param_str = @xs_params ? 'pTHX_ ' . join(', ', @xs_params) : 'pTHX';
        my @helper;
        push @helper, "static SV * $helper_name($param_str) {";
        push @helper, "    return $c_expr;";
        push @helper, '}';
        return { helper => \@helper };
    }

    # Simple Unwind sub: emit `croak("MSG");` and return undef.
    method _emit_simple_die_sub($name, $params, $node) {
        my $args = $node->inputs->[0];
        my $msg = '';
        if (ref($args) eq 'ARRAY' && $args->@*) {
            $msg = $self->_escape_c_string($args->[0]->value);
        }
        my @xs_params;
        for my $p ($params->@*) {
            my $pname = ref($p) ? $p->value : "$p";
            $pname =~ s/^[\$\@\%]//;
            push @xs_params, "SV *$pname";
        }
        my $helper_name = "${\  $self->_get_current_slug()}_${name}";
        my $param_str = @xs_params ? 'pTHX_ ' . join(', ', @xs_params) : 'pTHX';
        my @helper;
        push @helper, "static SV * $helper_name($param_str) {";
        push @helper, "    croak(\"%s\", \"$msg\");";
        push @helper, "    return &PL_sv_undef;  /* unreachable */";
        push @helper, '}';
        return { helper => \@helper };
    }

    # Complex sub body emission — schedule-driven, mirrors
    # _emit_complex_method but emits `static SV *` (not exported)
    # and handles the Constant.value eq 'return' last-stmt case
    # specific to subs.
    method _emit_complex_sub_body($name, $params, $schedule, $scheduler) {
        my @code;

        my @stmt_items = grep { $_->kind eq 'stmt' } $schedule->items->@*;
        my $last_stmt = @stmt_items ? $stmt_items[-1] : undef;
        my $last_node = defined $last_stmt ? $last_stmt->node : undef;

        my $last_is_return = (defined $last_node
            && $last_node isa Chalk::IR::Node::Return);
        # Sub-specific: a trailing Constant.value eq 'return' counts.
        $last_is_return ||= (defined $last_node
            && $last_node isa Chalk::IR::Node::Constant
            && ($last_node->value // '') eq 'return');
        my $body_has_returns = $self->_body_contains_return($schedule);
        my $single_stmt_return = (!$last_is_return
            && scalar(@stmt_items) == 1
            && defined $last_node
            && $self->_is_single_stmt_return_expr($last_node));
        my $tail_expr_return = (!$last_is_return
            && defined $last_node
            && ($self->_is_unambiguous_value_expr($last_node)
                || ($body_has_returns && $self->_is_bare_return_expr($last_node)))
            );
        my $has_return = $last_is_return || $tail_expr_return
               || $single_stmt_return || $body_has_returns;

        my %declared_vars;
        my @xs_params;
        for my $p ($params->@*) {
            my $pname = ref($p) ? $p->value : "$p";
            $pname =~ s/^[\$\@\%]//;
            push @xs_params, "SV *$pname";
            $declared_vars{"param:$pname"} = true;
        }

        $self->_collect_var_decls($schedule, \%declared_vars);
        $self->_collect_all_var_refs($schedule, \%declared_vars);

        my $has_early_return = $self->_has_early_return($schedule);
        $self->_set_return_context($has_return);

        # Body emission via schedule walker.
        my $indent = 0;
        for my $item ($schedule->items->@*) {
            $self->_emit_c_schedule_item(
                $item, \@code, \$indent, $scheduler, \%declared_vars
            );
        }

        # Retval tail rewriting (sub-specific: skip sv_setsv-style).
        if (!$last_is_return && @code) {
            my $last_code = $code[-1];
            if ($last_code =~ s/;\s*$//) {
                if ($last_code =~ /^(?:sv_setsv|hv_clear|av_clear)\b/) {
                    $code[-1] = "$last_code;";
                } else {
                    my $wrapped = $self->_wrap_retval($last_code);
                    $code[-1] = "retval = $wrapped;";
                    $has_return = true;
                }
            }
        }

        my @helper;
        my $helper_name = "${\  $self->_get_current_slug()}_${name}";
        my $param_str = @xs_params ? 'pTHX_ ' . join(', ', @xs_params) : 'pTHX';
        push @helper, "static SV * $helper_name($param_str) {";
        push @helper, '    SV *retval = NULL;';
        for my $var (sort keys %declared_vars) {
            next if $var eq 'hash';
            next if $var =~ /^param:/;
            push @helper, "    SV *${var}_sv = NULL;";
        }
        for my $stmt (@code) {
            my $rewritten = $stmt;
            $rewritten =~ s/\bRETVAL\b/retval/g;
            $rewritten =~ s/\breturn\s*;/return \&PL_sv_undef;/g;
            for my $line (split /\n/, $rewritten) {
                push @helper, "    $line";
            }
        }
        if ($has_early_return) {
            push @helper, '    xsreturn:';
        }
        if ($has_return) {
            push @helper, '    return retval;';
        } else {
            push @helper, '    return &PL_sv_undef;';
        }
        push @helper, '}';
        return { helper => \@helper };
    }
```

- [ ] **Step 4: Update the caller in `_generate_c_files`.**

Find the sub-emission loop in `_generate_c_files` (around lines 1585-1604 — the part with `for my $sub ($mop_class->subs) { ... _emit_sub($sname, $sparams, $sbody) ... }`):

```bash
grep -n '_emit_sub' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Target/C.pm
```

Replace the call to use the new single-arg signature. The relevant edit at lines 1585-1604:

```perl
        # Emit class-scope subs (static helpers) before methods.
        for my $sub ($mop_class->subs) {
            my $sname = $sub->name;
            my $result;
            try {
                $result = $self->_emit_sub($sub);
            } catch ($e) {
                # Emission failed — mark sub as not compiled
            }
            if (defined $result && ref $result eq 'HASH') {
                push @static_lines, $result->{helper}->@*;
                push @static_lines, '';
                $self->_set_class_sub_compiled($sname, true);
            } else {
                $self->_set_class_sub_compiled($sname, false);
            }
        }
```

The `$sparams = $sub->params; $sbody = $sub->body;` reads (former 7d-transitional reads) are GONE — `_emit_sub` does its own MOP-field access internally.

- [ ] **Step 5: Run the tests.**

```bash
PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/c-sub-state-leak.t 2>&1 | tail -10
$PERL -Ilib t/bootstrap/c-simple-body-shortcuts.t 2>&1 | tail -10
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -10
```

Expected: all PASS. The state-leak test passes (save/restore works). The bnf-target-c.t at 178/178 (sub emission used by some classes; the migration preserves output).

---

### Task 2.7: Smoke test for VarDecl-with-control-flow-init handling

**Files:**
- Create: `t/bootstrap/c-schedule-tail-control.t` (formerly named c-schedule-tail-control.t; renamed for accuracy — the test exercises a control-flow node at the tail-position implicit return, not a `my $x = if(...){...}` VarDecl-with-control-init pattern)

- [ ] **Step 1: Check if any corpus method exercises this pattern.**

```bash
grep -rn 'my .* = if (' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk 2>/dev/null | head -5
grep -rn 'my .* = while ' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk 2>/dev/null | head -5
```

If the corpus has natural cases, write a test that parses one and emits its C without crashing. If not, hand-construct a synthetic MOP fixture.

- [ ] **Step 2: Write a minimal smoke test.**

If natural cases exist, use one. Otherwise create a synthetic test:

```perl
# ABOUTME: Phase 7d smoke test for a control-flow node at the tail (implicit-return) position.
# ABOUTME: Verifies _emit_c_schedule_item handles synthetic Return wrapping If/Loop/TryCatch via _expand_node.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(parse_perl_source);
use Chalk::Bootstrap::Perl::Target::C;

# Construct a minimal class whose method has a control-flow value
# at the tail position (the implicit return).
my $src = <<'PERL';
class Test::VarDeclControl {
    method tail_if($self, $x) {
        if ($x) { 1 } else { 0 }
    }
}
PERL

my $mop = Chalk::MOP->new;
Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
my ($ir, $sa, $ctx) = parse_perl_source($src);
ok(defined $ctx, 'parse succeeds');

my $mop_class;
for my $cls ($mop->classes) {
    next if $cls->name eq 'main';
    $mop_class = $cls;
}
ok(defined $mop_class, 'class found in MOP');

SKIP: {
    skip 'no class', 1 unless defined $mop_class;
    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Test::VarDeclControl',
    );
    my $result = eval { $target->_generate_c_files($ir, $sa, $ctx) };
    ok(defined $result, '_generate_c_files succeeds for tail-if method') or do {
        diag "Error: $@";
    };
}

done_testing();
```

- [ ] **Step 3: Run the test.**

```bash
$HOME/.local/share/pvm/versions/5.42.0/bin/perl -Ilib t/bootstrap/c-schedule-tail-control.t 2>&1 | tail -10
```

Expected: PASS. If FAIL with `_emit_node` complaining about If/Loop/TryCatch as expressions, this means `_emit_c_schedule_item` needs the `_expand_node` recursion case from Perl.pm:260-286.

- [ ] **Step 4 (only if Step 3 failed):** Add the `_expand_node` recursion case to `_emit_c_schedule_item`.

In `_emit_c_schedule_item` (added in Task 2.2), find the 'stmt' case. Before calling `_emit_stmt`, add:

```perl
        if ($kind eq 'stmt') {
            my $node = $item->node;
            # Synthetic Return whose value is a control-flow node:
            # expand via the scheduler so the block_open/.../block_close
            # sequence emits rather than failing in _emit_node.
            if (blessed($node)
                    && $node isa Chalk::IR::Node::Return
                    && $node->can('synthetic')
                    && $node->synthetic)
            {
                my $val = $node->inputs->[1];
                if (defined $val && blessed($val)
                        && ($val isa Chalk::IR::Node::If
                         || $val isa Chalk::IR::Node::Loop
                         || $val isa Chalk::IR::Node::TryCatch))
                {
                    my @sub_items = $scheduler->_expand_node($val);
                    for my $sub_item (@sub_items) {
                        $self->_emit_c_schedule_item(
                            $sub_item, $lines, $indent_ref, $scheduler, $declared_vars
                        );
                    }
                    return;
                }
            }
            # ... existing _emit_stmt call ...
        }
```

Re-run the test; expect PASS.

---

### Task 2.8: Delete repairs proven dead by Commit 1's counters

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (delete dead repair methods)
- Modify: `t/bootstrap/c-emit-helpers-inheritance.t` (delete `can(...)` assertions for removed methods)

- [ ] **Step 1: Re-read the Commit 1 decision table.**

(Saved from the Pre-Commit-2 GATE step.)

For each repair with ZERO fires in the corpus, locate the method and delete it. For each non-zero repair, leave it alone and add a comment block above it (this happens in Commit 3 Case B).

- [ ] **Step 2: For each dead repair, delete the method.**

Example for `_repair_stale_merge` if it had zero fires:

```bash
# Find the method bounds:
grep -n 'method _repair_stale_merge\|method _is_stale_merge' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm
```

Read the method, find its closing `}`, delete the full block. Also find any callers (grep for the method name) and delete those calls.

For `_is_stale_merge` (paired with `_repair_stale_merge`): if BOTH are dead, delete both. If `_is_stale_merge` fires but `_repair_stale_merge` doesn't, that's a contradiction — investigate (detection without repair means the call site does something else with the result).

For the textual fixups (`_fixup_xs_list_destructuring`, `_fixup_ternary_assignment`, `_fixup_filtercomposite_add_destructuring`): each method has multiple internal patterns; if some patterns fired and others didn't, you can either delete the method entirely (if it's all-dead) or surgically remove just the dead branches (if some patterns fired). Prefer the surgical approach for partial deletion.

For `emit_cfg_loop` chart-re-read: this is a branch inside the larger `emit_cfg_loop` method. `emit_cfg_loop` is part of the cfg_lookup infrastructure that becomes unreachable post-7d and gets entirely deleted in 7g. **Do NOT surgically delete just the chart-re-read branch.** Document the zero-fire result in the decision table but leave `emit_cfg_loop` intact for 7g to sweep with the rest of the cfg infrastructure. Mid-method partial edits add churn with no lasting impact since the whole method dies in 7g regardless.

- [ ] **Step 3: Delete `can(...)` assertions for removed methods from c-emit-helpers-inheritance.t.**

```bash
grep -n 'can(.*repair\|can(.*fixup\|can(.*stale' /home/perigrin/dev/chalk/.claude/worktrees/pu/t/bootstrap/c-emit-helpers-inheritance.t
```

For each method you deleted in Step 2, find the matching `ok($target->can('METHOD'), 'METHOD is available');` line and delete it.

- [ ] **Step 4: Run the tests to confirm no regression.**

```bash
PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -5
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -5
$PERL -Ilib t/bootstrap/c-repair-coverage.t 2>&1 | tail -10
```

Expected:
- `c-emit-helpers-inheritance.t`: count drops by however many `can` assertions you removed.
- `bnf-target-c.t`: still 178/178 (deletions should NOT change emission output; if they do, the repair was load-bearing despite zero counter fires).
- `c-repair-coverage.t`: still passes (the counter for deleted repairs is now never incremented but the test only reports counts, doesn't require non-zero).

---

### Task 2.9: Commit 2

- [ ] **Step 1: Final test run.**

```bash
PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl
for t in t/bootstrap/mop/*.t \
         t/bootstrap/c-emit-helpers-inheritance.t \
         t/bootstrap/bnf-target-c.t \
         t/bootstrap/xs-isa-inheritance.t \
         t/bootstrap/xs-athx-no-args.t \
         t/bootstrap/xs-polymorphic-dispatch.t \
         t/bootstrap/xs-int-specialization.t \
         t/bootstrap/c-schedule-walker.t \
         t/bootstrap/c-analysis-helpers-schedule.t \
         t/bootstrap/c-simple-body-shortcuts.t \
         t/bootstrap/c-sub-state-leak.t \
         t/bootstrap/c-schedule-tail-control.t \
         t/bootstrap/c-repair-coverage.t; do
    echo "=== $t ===";
    $PERL -Ilib "$t" 2>&1 | tail -3;
done
```

Expected: all green except the pre-existing failures (xs-polymorphic-dispatch.t 59/60, xs-int-specialization.t 2/6) — preserved at baseline counts.

- [ ] **Step 2: Stage and commit.**

```bash
git status
git add lib/Chalk/Bootstrap/Perl/Target/C.pm \
        lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm \
        t/bootstrap/c-emit-helpers-inheritance.t \
        t/bootstrap/c-schedule-walker.t \
        t/bootstrap/c-analysis-helpers-schedule.t \
        t/bootstrap/c-simple-body-shortcuts.t \
        t/bootstrap/c-sub-state-leak.t \
        t/bootstrap/c-schedule-tail-control.t
git status   # verify nothing extra staged
git commit -m "$(cat <<'EOF'
feat(target-c): Phase 7d — schedule-driven body emission

Migrate Target::C's method/sub body emission from $method->body
arrayref iteration to consuming Chalk::IR::Schedule instances
produced by Chalk::IR::Scheduler::EagerPinning. Mirrors
Target::Perl's existing _emit_scheduled_body / _emit_schedule_item
shape.

Sites migrated:
- _emit_method: now builds schedule and detects simple-body
  shortcuts (empty / single-Return-of-Constant / single-Unwind)
  from the schedule shape, not from $body->[0]. Falls through to
  _emit_complex_method for multi-stmt bodies.
- _emit_complex_method: signature changes from
  ($name, $params, $body, $ir_return_type) to
  ($name, $params, $schedule, $scheduler, $ir_return_type).
  Body iteration uses _emit_c_schedule_item instead of direct
  _emit_stmt calls. All other logic (param plumbing, retval
  template, exported_functions push, helper assembly) preserved.
- _emit_sub: signature changes to ($sub) where $sub isa
  Chalk::MOP::Sub. Try/catch state save/restore for
  _current_sub_name and _return_context preserved exactly.
  New _emit_complex_sub_body separates the static-emission +
  Constant.value eq 'return' last-stmt case from
  _emit_complex_method.
- Simple-body emission templates extracted: _emit_simple_empty_method,
  _emit_simple_return_method, _emit_simple_die_method (method
  variants), plus _emit_simple_empty_sub, _emit_simple_return_sub,
  _emit_simple_die_sub (sub variants).

New helpers in C.pm:
- _emit_scheduled_c_body($method) — schedule entry point.
- _emit_c_schedule_item($item, ...) — per-item dispatcher.
- _emit_c_block_open_head, _emit_c_block_close_tail — form-aware
  block markers (foreach emits TWO `}` for AV+for-loop pair).
- _emit_c_if_head, _emit_c_while_head, _emit_c_foreach_head,
  _emit_c_for_head, _emit_c_catch_head — form-specific heads.
- _loop_condition_c — extracts condition from a Loop's
  controlled If.

Analysis helpers rewritten (6 schedule-substrate, 3 node-level
unchanged):
- _is_complex_method($schedule) — now takes schedule.
- _has_early_return($schedule) — walks all 'stmt' items except
  the trailing synthetic-Return; branch-internal Returns ARE
  counted (per correctness invariant).
- _body_contains_return($schedule), _body_contains_bare_return($schedule)
- _collect_var_decls($schedule, $declared) — handles foreach
  iterator name extraction from schedule_data.
- _collect_all_var_refs($schedule, $declared) — same.
- _is_bare_return_expr($node), _is_unambiguous_value_expr($node),
  _is_single_stmt_return_expr($node) — node-level, signature
  preserved; calling pattern changes (callers locate the
  relevant 'stmt' node from schedule iteration).

Repairs deleted (proven dead by Commit 1's counter coverage):
- <list each deleted repair name + its zero counter from
  c-repair-coverage.t output>

Repairs preserved (live counter fires):
- <list each surviving repair + brief why it remains>

Test gates:
- bnf-target-c.t: 178/178 (unchanged; schedule path produces
  byte-identical output for the corpus).
- c-emit-helpers-inheritance.t: 55-N (N = `can` assertions
  removed for deleted repairs).
- All new test files pass.

Pre-existing failures preserved at baseline (NOT regressed):
- xs-polymorphic-dispatch.t 59/60
- xs-int-specialization.t 2/6

Out of scope (Phase 7g):
- Deletion of cfg_lookup infrastructure (%_cfg_lookup,
  _build_cfg_lookup, emit_cfg_if/loop/try_catch/phi_if,
  emit_from_cfg_state). Unreachable from emission layer after
  this commit; 7g sweeps.
- MOP::Method.body / MOP::Sub.body deletion.

Design: docs/plans/2026-05-25-phase-7d-design.md
Plan:   docs/plans/2026-05-25-phase-7d-plan.md
EOF
)" && git log --oneline -3
```

**STOP — placeholder guard.** The "Repairs deleted" and "Repairs preserved" lines have `<list ...>` placeholders. These MUST be filled in with actual repair-name results from the decision table BEFORE running `git commit`. Verify with:

```bash
echo "$COMMIT_MSG" | grep -E '<list|<fill' && echo 'STOP: placeholders remain in commit message' && exit 1
```

Or simpler: read the staged commit message before pressing enter and ensure no `<...>` placeholders survive. Shipping a commit with literal `<list each deleted repair name>` text would be embarrassing and require an amend.

---

## COMMIT 3 — repair-counter outcome documentation

Always ships. Content depends on Commit 2's deletion outcome.

### Task 3.1 (Case A: all repairs were dead): Delete counter infrastructure

If Commit 2 deleted all repair methods AND `c-repair-coverage.t`'s totals all read zero:

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` — delete `%_repair_counters`, `_record_repair`, `repair_counters`, `reset_repair_counters`.
- Delete: `t/bootstrap/c-repair-coverage.t`.

- [ ] **Step 1: Delete the field and accessors.**

```bash
grep -n '_repair_counters\|_record_repair\|repair_counters\|reset_repair_counters' /home/perigrin/dev/chalk/.claude/worktrees/pu/lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm
```

For each match, delete the surrounding declaration (field, method body).

- [ ] **Step 2: Delete the test file.**

```bash
rm /home/perigrin/dev/chalk/.claude/worktrees/pu/t/bootstrap/c-repair-coverage.t
git status
```

- [ ] **Step 3: Run the regression suite.**

```bash
PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/c-emit-helpers-inheritance.t 2>&1 | tail -5
$PERL -Ilib t/bootstrap/bnf-target-c.t 2>&1 | tail -5
```

Expected: all green; counts unchanged from Commit 2 final.

- [ ] **Step 4: Commit.**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm
git rm t/bootstrap/c-repair-coverage.t
git commit -m "$(cat <<'EOF'
chore(target-c): retire repair-counter instrumentation (all dead)

Commit 1's repair-counter instrumentation served its purpose:
the c-repair-coverage.t totals showed zero fires across the
corpus for all instrumented repairs. Commit 2 deleted the
corresponding repair methods. With nothing left to count, the
counter infrastructure (%_repair_counters, _record_repair,
repair_counters, reset_repair_counters) is removed, along with
the t/bootstrap/c-repair-coverage.t test.

Design: docs/plans/2026-05-25-phase-7d-design.md
EOF
)"
```

### Task 3.2 (Case B: some repairs survived): Document survivors

If any repair counter showed non-zero fires AND Commit 2 preserved the repair, document why.

**Files:**
- Modify: `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` — add doc comments above each surviving repair counter site.

- [ ] **Step 1: For each surviving repair, add a documentation comment.**

Above each `$self->_record_repair('NAME')` call site, add a comment block:

```perl
    # MONITORED REPAIR: <name>
    # <One-paragraph explanation of what artifact this patches.>
    # <Why it was NOT deleted in Phase 7d (e.g., "the schedule
    # path produces the same artifact"; "the underlying parser
    # bug has not been fixed at source").>
    # Counter retained for ongoing regression monitoring; if this
    # fires unexpectedly post-deployment, it's evidence the
    # repair is still load-bearing.
    $self->_record_repair('NAME');
```

- [ ] **Step 2: Run tests.**

```bash
PERL=$HOME/.local/share/pvm/versions/5.42.0/bin/perl
$PERL -Ilib t/bootstrap/c-repair-coverage.t 2>&1 | tail -10
```

Expected: still passes; diag still reports the surviving counters' fires.

- [ ] **Step 3: Commit.**

```bash
git add lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm
git commit -m "$(cat <<'EOF'
chore(target-c): document surviving repair-counter monitors

Commit 1's repair-counter instrumentation surfaced N repairs
that continue to fire post-Phase-7d migration: <list>. For each,
the documentation comment block above its _record_repair call
explains what artifact it patches and why the schedule path
doesn't make it obsolete.

The counter infrastructure (%_repair_counters, _record_repair,
repair_counters) stays alive as ongoing regression coverage.

Design: docs/plans/2026-05-25-phase-7d-design.md
EOF
)"
```

---

## Final acceptance checks (post all three commits)

- [ ] All test gates listed under "Baseline capture" pass at expected counts (Commit 2's count change for `c-emit-helpers-inheritance.t` accounted for).
- [ ] `bnf-target-c.t` at 178/178.
- [ ] `git status` is clean.
- [ ] `git log --oneline -5` shows the three commits + design + plan + 7c-proper commits.
- [ ] `ag '$method->body\|$sub->body' lib/Chalk/Bootstrap/Perl/Target/C.pm` returns zero matches in `_emit_method` / `_emit_complex_method` / `_emit_sub` (the body reads in those entry points are gone; reads elsewhere are 7g's concern).
- [ ] `ag '_cfg_lookup' lib/Chalk/Bootstrap/Perl/Target/C.pm` returns zero matches outside of `_build_cfg_lookup` and the legacy cfg-dispatch in `_emit_stmt` (those remain for 7g to delete).
- [ ] Branch is NOT pushed (per spec hard constraint).

If all hold, Phase 7d is complete. Next phase: **Phase 7d-aux** (pre-emission fixup audit in Actions.pm — see design doc's "Tracked: pre-emission fixup audit" section). After that, **Phase 7e** (TestXSHelpers + hand-built test migration).
