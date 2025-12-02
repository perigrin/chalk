# Loop Iteration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement actual loop iteration in CEKDataflow interpreter so Sea of Nodes IR with loops can be executed.

**Architecture:** Track active control path in Loop nodes, use path index for Phi value selection in loops, reset and re-queue loop body nodes on backedge traversal. Adapts Simple compiler's GraphEvaluator approach for dataflow scheduling.

**Tech Stack:** Perl 5.42, Perl OO with `class` keyword, Test2::V0

**Related:** Issue #273, design doc `docs/plans/2025-12-02-loop-iteration-design.md`

---

## Task 1: Add active_input_index Tracking to Loop Node

**Files:**
- Modify: `lib/Chalk/IR/Node/Loop.pm`
- Create: `t/interpreter/cek-loop-execution.t`

**Step 1: Write failing test for active_input_index accessor**

Create new test file `t/interpreter/cek-loop-execution.t`:

```perl
#!/usr/bin/env perl
# ABOUTME: Test CEK interpreter execution with loop iteration
# ABOUTME: Tests Loop iteration, Phi value selection, and backedge traversal

use 5.42.0;
use utf8;
use lib 'lib';
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Loop;
use Chalk::IR::Node::Constant;

subtest 'Loop node tracks active_input_index' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    # Create a Loop with entry control from Start
    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id],
    );
    $graph->add_node($loop);

    # Initial active_input_index should be 0 (not yet executed)
    is($loop->active_input_index, 0, 'Loop active_input_index defaults to 0');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: FAIL - `active_input_index` method not found

**Step 3: Add active_input_index field to Loop.pm**

Modify `lib/Chalk/IR/Node/Loop.pm` - add field after line 7:

```perl
class Chalk::IR::Node::Loop :isa(Chalk::IR::Node::Base) {
    field $active_input_index :reader = 0;

    method op() { 'Loop' }
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Loop.pm t/interpreter/cek-loop-execution.t
git commit -m "feat(Loop): Add active_input_index field for iteration tracking"
```

---

## Task 2: Update Loop.execute() to Track Active Path

**Files:**
- Modify: `lib/Chalk/IR/Node/Loop.pm`
- Modify: `t/interpreter/cek-loop-execution.t`

**Step 1: Write failing test for execute() updating active_input_index**

Add to `t/interpreter/cek-loop-execution.t`:

```perl
subtest 'Loop.execute() sets active_input_index based on active path' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id, 'backedge_placeholder'],
    );
    $graph->add_node($loop);

    # Mock context where entry control (index 0) is active
    my %node_values = (
        $start->id => 1,  # Entry path active
        'backedge_placeholder' => 0,  # Backedge not active
    );
    my $context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };

    my $result = $loop->execute($context);

    is($result, 0, 'Loop returns 0 for entry path');
    is($loop->active_input_index, 0, 'active_input_index set to 0 for entry');
};

subtest 'Loop.execute() returns 1 when backedge is active' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id, 'backedge_ctrl'],
    );
    $graph->add_node($loop);

    # Mock context where backedge (index 1) is active
    my %node_values = (
        $start->id => 0,  # Entry path not active
        'backedge_ctrl' => 1,  # Backedge active (continue iterating)
    );
    my $context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };

    my $result = $loop->execute($context);

    is($result, 1, 'Loop returns 1 for backedge path');
    is($loop->active_input_index, 1, 'active_input_index set to 1 for backedge');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: Tests fail because `active_input_index` is not updated by execute()

**Step 3: Update Loop.execute() to set active_input_index**

Replace the `execute` method in `lib/Chalk/IR/Node/Loop.pm`:

```perl
    method execute($context) {
        # Loop merges control from entry and backedge paths
        # Works like Region: returns index of active path
        # inputs[0] = entry control
        # inputs[1] = backedge control (if present)
        my @inputs = $self->inputs->@*;

        for my $i (0..$#inputs) {
            my $input_id = $inputs[$i];
            my $ctrl_result = $context->("node:$input_id");
            if ($ctrl_result) {
                $active_input_index = $i;  # Track which path is active
                return $i;  # Return index of active path
            }
        }

        # No active path found - shouldn't happen in valid IR
        die "Loop node has no active input path";
    }
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Loop.pm t/interpreter/cek-loop-execution.t
git commit -m "feat(Loop): Update execute() to track active_input_index"
```

---

## Task 3: Update Phi Node to Use Loop's active_input_index

**Files:**
- Modify: `lib/Chalk/IR/Node/Phi.pm`
- Modify: `t/interpreter/cek-loop-execution.t`

**Step 1: Write failing test for Phi selecting loop values**

Add to `t/interpreter/cek-loop-execution.t`:

```perl
use Chalk::IR::Node::Phi;

subtest 'Phi selects entry value (index 0) on first iteration' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id, 'backedge_ctrl'],
    );
    $graph->add_node($loop);

    my $init_val = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_val);

    my $loop_val = Chalk::IR::Node::Constant->new(value => 42, type => 'int');
    $graph->add_node($loop_val);

    # Phi with Loop region: inputs = [region_id, entry_value, backedge_value]
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_val->id, $loop_val->id],
    );
    $graph->add_node($phi);

    # Simulate entry path active (index 0)
    my %node_values = (
        $start->id => 1,
        'backedge_ctrl' => 0,
        $init_val->id => 0,
        $loop_val->id => 42,
    );

    # First execute Loop to set active_input_index
    my $loop_context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };
    $loop->execute($loop_context);

    # Now execute Phi - should select entry value
    my $phi_context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };
    my $result = $phi->execute($phi_context);

    is($result, 0, 'Phi selects entry value (0) when Loop active_input_index is 0');
};

subtest 'Phi selects backedge value (index 1) on subsequent iterations' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id, 'backedge_ctrl'],
    );
    $graph->add_node($loop);

    my $init_val = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_val);

    my $loop_val = Chalk::IR::Node::Constant->new(value => 42, type => 'int');
    $graph->add_node($loop_val);

    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_val->id, $loop_val->id],
    );
    $graph->add_node($phi);

    # Simulate backedge path active (index 1)
    my %node_values = (
        $start->id => 0,
        'backedge_ctrl' => 1,
        $init_val->id => 0,
        $loop_val->id => 42,
    );

    # First execute Loop to set active_input_index = 1
    my $loop_context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };
    $loop->execute($loop_context);

    # Now execute Phi - should select backedge value
    my $phi_context = sub ($key) {
        return $graph if $key eq 'graph:';
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1} // 0;
        }
        return undef;
    };
    my $result = $phi->execute($phi_context);

    is($result, 42, 'Phi selects backedge value (42) when Loop active_input_index is 1');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: Tests fail because Phi doesn't use Loop's active_input_index

**Step 3: Update Phi.execute() to handle Loop regions**

Modify `lib/Chalk/IR/Node/Phi.pm`, update the `execute` method to check for Loop first:

```perl
    method execute($context) {
        # Phi selects value based on which Region input path is active
        # For Loop regions, use the Loop's active_input_index directly
        # For regular Regions, find which Proj returned 1
        my @inputs = $self->inputs->@*;

        # Get the Region/Loop node
        my $graph = $context->("graph:");
        my $region_node = $graph->nodes->{$region_id};

        # Special handling for Loop regions
        if ($region_node->op eq 'Loop') {
            # Use Loop's active_input_index directly
            my $idx = $region_node->active_input_index;
            my $value_index = $idx + 1;  # inputs[0] is region_id, inputs[1] is entry, inputs[2] is backedge
            if ($value_index >= @inputs) {
                die "Phi node: Loop active path $idx out of range (only " . (@inputs - 1) . " data inputs)";
            }
            my $value_id = $inputs[$value_index];
            return $context->("node:$value_id");
        }

        # For regular Regions, find which Proj returned 1 (active path)
        my $region_inputs = $region_node->inputs;

        for my $i (0..$#$region_inputs) {
            my $proj_id = $region_inputs->[$i];
            my $proj_result = $context->("node:$proj_id");

            if ($proj_result == 1) {
                # This is the active path - select corresponding data value
                # Phi inputs are offset by 1 (input[0] is region, input[1] is first value)
                my $value_index = $i + 1;
                if ($value_index >= @inputs) {
                    die "Phi node: active path $i out of range";
                }
                my $value_id = $inputs[$value_index];
                return $context->("node:$value_id");
            }
        }

        die "Phi node: no active path found in Region $region_id";
    }
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Phi.pm t/interpreter/cek-loop-execution.t
git commit -m "feat(Phi): Use Loop's active_input_index for value selection"
```

---

## Task 4: Add Loop Body Detection to CEKDataflow

**Files:**
- Modify: `lib/Chalk/Interpreter/CEKDataflow.pm`
- Modify: `t/interpreter/cek-loop-execution.t`

**Step 1: Write failing test for find_loop_body_nodes**

Add to `t/interpreter/cek-loop-execution.t`:

```perl
use Chalk::Interpreter::CEKDataflow;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::LT;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Return;

subtest 'CEKDataflow.find_loop_body_nodes identifies loop-dependent nodes' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build: while (i < 10) { i = i + 1; } return i;
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $init_i = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_i);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id],
    );
    $graph->add_node($loop);

    my $phi_i = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_i->id],
    );
    $graph->add_node($phi_i);

    my $const_10 = Chalk::IR::Node::Constant->new(value => 10, type => 'int');
    $graph->add_node($const_10);

    my $lt = Chalk::IR::Node::LT->new(
        left_id => $phi_i->id,
        right_id => $const_10->id,
    );
    $graph->add_node($lt);

    my $const_1 = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    $graph->add_node($const_1);

    my $add = Chalk::IR::Node::Add->new(
        left => $phi_i,
        right => $const_1,
    );
    $graph->add_node($add);

    # Complete phi backedge
    push $phi_i->inputs->@*, $add->id;
    # Add backedge to loop (simplified - would normally be from Proj)
    push $loop->inputs->@*, $loop->id;

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my @body_nodes = $interp->find_loop_body_nodes($loop->id);

    # Should find: phi_i, lt, add (nodes that depend on Loop or its Phis)
    ok(scalar(@body_nodes) >= 1, 'Found at least the Phi node in loop body');
    ok((grep { $_ eq $phi_i->id } @body_nodes), 'Phi node is in loop body');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: FAIL - `find_loop_body_nodes` method not found

**Step 3: Add find_loop_body_nodes method to CEKDataflow**

Add to `lib/Chalk/Interpreter/CEKDataflow.pm` before the final `1;`:

```perl
    method find_loop_body_nodes($loop_id) {
        # Find all nodes that are part of the loop body
        # These are nodes that need to be re-executed on each iteration
        my $nodes = $graph->nodes;
        my %body_nodes;
        my @to_process;

        # Start with Phi nodes attached to this Loop
        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            if ($node->op eq 'Phi') {
                # Check if this Phi is attached to our Loop
                if ($node->can('region_id') && $node->region_id eq $loop_id) {
                    $body_nodes{$node_id} = 1;
                    push @to_process, $node_id;
                }
            }
        }

        # Find dependents of the Phi nodes (nodes that use Phi outputs)
        while (@to_process) {
            my $current_id = shift @to_process;
            for my $node_id (keys $nodes->%*) {
                next if $body_nodes{$node_id};  # Already found
                my $node = $nodes->{$node_id};
                my $inputs = $node->inputs;
                if (grep { $_ eq $current_id } $inputs->@*) {
                    # This node depends on a loop body node
                    # Only include if it's not a control flow exit (Return, etc.)
                    next if $node->op eq 'Return';
                    next if $node->op eq 'Stop';
                    $body_nodes{$node_id} = 1;
                    push @to_process, $node_id;
                }
            }
        }

        return keys %body_nodes;
    }
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Interpreter/CEKDataflow.pm t/interpreter/cek-loop-execution.t
git commit -m "feat(CEKDataflow): Add find_loop_body_nodes for loop iteration"
```

---

## Task 5: Add Loop Iteration Logic to CEKDataflow.execute()

**Files:**
- Modify: `lib/Chalk/Interpreter/CEKDataflow.pm`
- Modify: `t/interpreter/cek-loop-execution.t`

**Step 1: Write failing test for simple counter loop execution**

Add to `t/interpreter/cek-loop-execution.t`:

```perl
subtest 'Execute simple counter loop: while (i < 3) { i++ } return i' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build IR for: i = 0; while (i < 3) { i = i + 1; } return i;
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $init_i = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_i);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id],
    );
    $graph->add_node($loop);

    my $phi_i = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_i->id],
    );
    $graph->add_node($phi_i);

    my $const_3 = Chalk::IR::Node::Constant->new(value => 3, type => 'int');
    $graph->add_node($const_3);

    my $lt = Chalk::IR::Node::LT->new(
        left_id => $phi_i->id,
        right_id => $const_3->id,
    );
    $graph->add_node($lt);

    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$loop->id, $lt->id],
        condition_id => $lt->id,
        condition => $lt,
    );
    $graph->add_node($if_node);

    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    $graph->add_node($proj_true);

    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    $graph->add_node($proj_false);

    my $const_1 = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    $graph->add_node($const_1);

    my $add = Chalk::IR::Node::Add->new(
        left => $phi_i,
        right => $const_1,
    );
    $graph->add_node($add);

    # Complete phi backedge with the incremented value
    push $phi_i->inputs->@*, $add->id;
    # Add backedge to loop from true projection
    push $loop->inputs->@*, $proj_true->id;

    # Return on false path
    my $return_node = Chalk::IR::Node::Return->new(
        control => $proj_false,
        value => $phi_i,
    );
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();

    is($result, 3, 'Counter loop executes: while (i < 3) returns 3');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: FAIL - loop doesn't iterate (returns 0 or hangs)

**Step 3: Add loop iteration logic to CEKDataflow.execute()**

Modify `lib/Chalk/Interpreter/CEKDataflow.pm`. Add field for iteration tracking and update execute():

Add after the existing fields (around line 34):

```perl
    field $max_iterations = 10000;  # Safety limit for loop iterations
```

Then modify the execute() method. After the node execution and before updating waiting nodes, add loop iteration handling. Find this section (around line 107):

```perl
            # Store result in environment
            $environment->set_node($node_id, $value);
            $computed{$node_id} = 1;
```

Replace that section and add loop handling:

```perl
            # Store result in environment
            $environment->set_node($node_id, $value);
            $computed{$node_id} = 1;

            # Handle Loop iteration
            if ($node->op eq 'Loop') {
                my $active_idx = $value;  # Loop.execute returns active path index

                if ($active_idx > 0) {
                    # Backedge is active - need to iterate
                    $loop_iterations{$node_id}++;
                    if ($loop_iterations{$node_id} > $max_iterations) {
                        die "Loop exceeded iteration limit ($max_iterations iterations)";
                    }

                    # Reset loop body nodes for re-execution
                    my @body_nodes = $self->find_loop_body_nodes($node_id);
                    for my $body_id (@body_nodes) {
                        delete $computed{$body_id};
                        # Re-calculate waiting dependencies
                        my $body_node = $nodes->{$body_id};
                        my $inputs = $body_node->inputs;
                        if ($inputs->@* > 0) {
                            my %deps;
                            for my $input_id ($inputs->@*) {
                                # Only wait on inputs that aren't computed
                                unless ($computed{$input_id}) {
                                    $deps{$input_id} = 1;
                                }
                            }
                            if (keys %deps) {
                                $waiting{$body_id} = \%deps;
                            } else {
                                # All deps satisfied, add to ready queue
                                push $ready_queue->@*, $body_id;
                            }
                        } else {
                            push $ready_queue->@*, $body_id;
                        }
                    }
                }
            }
```

Also add the loop_iterations hash initialization at the start of execute(), after `my %computed;`:

```perl
        my %loop_iterations;  # Track iterations per loop node
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Interpreter/CEKDataflow.pm t/interpreter/cek-loop-execution.t
git commit -m "feat(CEKDataflow): Add loop iteration with body reset"
```

---

## Task 6: Add Accumulator Loop Test

**Files:**
- Modify: `t/interpreter/cek-loop-execution.t`

**Step 1: Write test for accumulator loop**

Add to `t/interpreter/cek-loop-execution.t`:

```perl
subtest 'Execute accumulator loop: sum = 0+1+2+3+4 = 10' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build IR for: sum = 0; i = 0; while (i < 5) { sum = sum + i; i = i + 1; } return sum;
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $init_sum = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_sum);

    my $init_i = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($init_i);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id],
    );
    $graph->add_node($loop);

    my $phi_sum = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_sum->id],
    );
    $graph->add_node($phi_sum);

    my $phi_i = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $init_i->id],
    );
    $graph->add_node($phi_i);

    my $const_5 = Chalk::IR::Node::Constant->new(value => 5, type => 'int');
    $graph->add_node($const_5);

    my $lt = Chalk::IR::Node::LT->new(
        left_id => $phi_i->id,
        right_id => $const_5->id,
    );
    $graph->add_node($lt);

    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$loop->id, $lt->id],
        condition_id => $lt->id,
        condition => $lt,
    );
    $graph->add_node($if_node);

    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    $graph->add_node($proj_true);

    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    $graph->add_node($proj_false);

    # sum = sum + i
    my $add_sum = Chalk::IR::Node::Add->new(
        left => $phi_sum,
        right => $phi_i,
    );
    $graph->add_node($add_sum);

    # i = i + 1
    my $const_1 = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    $graph->add_node($const_1);

    my $add_i = Chalk::IR::Node::Add->new(
        left => $phi_i,
        right => $const_1,
    );
    $graph->add_node($add_i);

    # Complete phi backedges
    push $phi_sum->inputs->@*, $add_sum->id;
    push $phi_i->inputs->@*, $add_i->id;
    push $loop->inputs->@*, $proj_true->id;

    # Return sum on false path
    my $return_node = Chalk::IR::Node::Return->new(
        control => $proj_false,
        value => $phi_sum,
    );
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();

    is($result, 10, 'Accumulator loop: 0+1+2+3+4 = 10');
};
```

**Step 2: Run test**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: PASS (if Task 5 is complete, this should already work)

**Step 3: Commit**

```bash
git add t/interpreter/cek-loop-execution.t
git commit -m "test(loop): Add accumulator loop test case"
```

---

## Task 7: Add Iteration Limit Test

**Files:**
- Modify: `t/interpreter/cek-loop-execution.t`

**Step 1: Write test for iteration limit enforcement**

Add to `t/interpreter/cek-loop-execution.t`:

```perl
subtest 'Loop iteration limit prevents infinite loops' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build IR for: while (true) { } - infinite loop
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    $graph->add_node($start);

    my $loop = Chalk::IR::Node::Loop->new(
        inputs => [$start->id],
    );
    $graph->add_node($loop);

    my $const_true = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    $graph->add_node($const_true);

    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$loop->id, $const_true->id],
        condition_id => $const_true->id,
        condition => $const_true,
    );
    $graph->add_node($if_node);

    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    $graph->add_node($proj_true);

    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    $graph->add_node($proj_false);

    # Backedge to loop
    push $loop->inputs->@*, $proj_true->id;

    # Return 0 on false path (never reached in infinite loop)
    my $const_0 = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    $graph->add_node($const_0);

    my $return_node = Chalk::IR::Node::Return->new(
        control => $proj_false,
        value => $const_0,
    );
    $graph->add_node($return_node);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);

    like(
        dies { $interp->execute() },
        qr/Loop exceeded iteration limit/,
        'Infinite loop hits iteration limit'
    );
};
```

**Step 2: Run test**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/cek-loop-execution.t`

Expected: PASS

**Step 3: Commit**

```bash
git add t/interpreter/cek-loop-execution.t
git commit -m "test(loop): Add iteration limit enforcement test"
```

---

## Task 8: Run Full Test Suite and Verify No Regressions

**Files:**
- None (verification only)

**Step 1: Run all interpreter tests**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/interpreter/`

Expected: All tests pass

**Step 2: Run chapter07 structural tests**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/chapter07.t`

Expected: All tests pass (structural tests should be unaffected)

**Step 3: Run full test suite**

Run: `PLENV_VERSION=5.42.0 plenv exec ./prove`

Expected: All tests pass

**Step 4: Commit verification**

```bash
git status
# Should show clean working tree if all tests pass
```

---

## Task 9: Create Pull Request

**Step 1: Push branch**

```bash
git push origin HEAD:feat/issue-273-loop-iteration
```

**Step 2: Create PR**

```bash
gh pr create --title "feat(interpreter): Implement loop iteration in CEKDataflow (#273)" --body "$(cat <<'EOF'
## Summary
- Add `active_input_index` tracking to Loop nodes
- Update Phi nodes to use Loop's path index for value selection in loops
- Add loop body detection and reset logic to CEKDataflow
- Add iteration limit to prevent infinite loops (prep for #247)

## Test plan
- [ ] Simple counter loop: `while (i < 3) { i++ }` returns 3
- [ ] Accumulator loop: `sum = 0+1+2+3+4` returns 10
- [ ] Infinite loop hits iteration limit
- [ ] All existing tests pass

Fixes #273
EOF
)"
```

**Step 3: Return PR URL**

Report the PR URL to user.

---

## Summary

This plan implements loop iteration in 9 tasks:

1. Add `active_input_index` field to Loop.pm
2. Update Loop.execute() to track active path
3. Update Phi.execute() to use Loop's path index
4. Add `find_loop_body_nodes()` to CEKDataflow
5. Add loop iteration logic to CEKDataflow.execute()
6. Add accumulator loop test
7. Add iteration limit test
8. Run full test suite
9. Create PR

Each task follows TDD: write failing test, implement, verify pass, commit.
